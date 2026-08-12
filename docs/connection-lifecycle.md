# Design: separating domain lifecycle from connection lifecycle

## Summary

Today a connection profile has a single control — `enabled` — that fuses two
concerns: **does the File Provider domain exist** (and therefore its local
cache) and **should we be connecting to the server**. The only way to edit an
enabled profile is to disable it, and disabling calls `ExtensionController.remove()`,
which **deletes all locally cached files**. So a profile that fails for an
unrecoverable reason — the server-side auth changed, the host key rotated, the
remote path moved — forces the user to choose between an unusable connection and
throwing away their cache to fix it.

This document proposes decoupling the two. An enabled domain stays enabled (and
cached) while its SSH connection can be intentionally stood down — either by the
user (a **pause**) or by the supervisor on an unrecoverable error — so the user
can edit the profile and reconnect. The mechanics already exist:
`suspend(reason:options:)` preserves the domain and its cache — it is `disable()`
(→ `remove()`) that is destructive. What is missing is (1) a supervisor state for
"stopped, waiting for the user," (2) a `reconfigure` path that rebuilds the
`Session` with a new config without touching the domain, and (3) UI to surface
connection health and drive the pause / edit / reconnect flow.

## Terminology

The app-side connection has four distinct verb pairs, one per protocol the
supervisor drives. Keep them separate in code, comments, and log messages.

| Layer                    | Verbs                    | Mechanism                                                                                                                           |
| ------------------------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| App ↔ extension XPC link | **broker / teardown**    | `XPCBroker.broker(exporting:)` / `teardown()` (`DomainXPCBroker` wraps the `NSXPCConnection`)                                       |
| Domain sync state        | **suspend / resume**     | `ExtensionController.suspend(reason:options:)` / `resume()` → `NSFileProviderManager.disconnect` / `reconnect`                      |
| App ↔ remote SSH server  | **connect / disconnect** | a `SessionProvider` builds a `Session` (`SSHClient.connect`) / `Session.close`                                                      |
| Domain existence + cache | **enable / disable**     | `SessionSupervisor.enable()` / `disable()`; disable calls `ExtensionController.remove()` — **destructive, deletes the local cache** |

The crucial asymmetry this design leans on: **suspend preserves the cache;
disable (→ `remove()`) destroys it.** "Stand down the connection so the user can
edit" is a **suspend + disconnect**, never a disable.

## Background: current architecture

The `SessionSupervisor` and connection-resilience work has landed. The shape
below reflects the code as it actually is: a per-domain `SessionSupervisor` owns
the live SSH `Session`, its single-flight connect and backoff retry, and the
domain suspend/resume decision, with the XPC and extension arms injected as
protocols.

- `ConnectionConfigModel.enabled` (SwiftData) is the single persisted control.
  `enable()` builds a resolved `ConnectionConfig(from:)`, tests SSH
  (`SSHClient.test`), and calls `DomainRegistry.shared.enable(config:)`;
  `disable()` calls `DomainRegistry.shared.disable(id:)`. Both then flip
  `enabled`.
- `DomainRegistry` (actor) is a thin `[UUID: SessionSupervisor]` registry plus a
  `[UUID: ConnectionConfig]` map, lazily creating a supervisor in
  `supervisor(for:)`. `enable(config:)` opens the `DomainDB`, stores the config,
  and calls `supervisor.enable()`; `disable(id:)` removes and `disable()`s the
  supervisor and drops the config.
- `SessionSupervisor` (actor) owns SSH state as
  `SSHState { case offline; case online(Session) }` plus a single-flight
  `connectTask` that retries on an exponential backoff (`startConnecting` /
  `stopConnecting`). `enable()` starts connecting; `goOnline()` builds the
  `Session` via the injected `SessionProvider`, **resume**s the domain, **broker**s
  XPC, stores `.online`, and starts polling; `goOffline()` **teardown**s XPC,
  **suspend**s the domain with a reason, closes the session, and restarts the
  backoff loop; `disable()` stops connecting, tears down XPC, and **remove**s the
  domain (destructive). Its `SessionProvider`, `XPCBroker`, and
  `ExtensionController` are injected (default to `DomainXPCBroker` / the
  `NSFileProviderDomain`) so tests can substitute them.
- `Session` (actor) holds one connected `ssh`/`sftp`/`db`/`cache`, owns the poll
  loop (`startPolling(every:)` / `stopPolling`), and detects connection loss in
  its own `mapError`: an `isConnectionFailed` or sftp `connectionLost` /
  `noConnection` / `failure` error invokes the injected `ConnectionLostHandler`
  (wired by the supervisor to `goOffline`) and rethrows `CoreError.serverUnreachable`.
- `SessionSupervisor.withSession` just guards `.online` and throws
  `CoreError.serverUnreachable` when `.offline`; it no longer catches or drops the
  session — that moved into `Session.mapError` / the `ConnectionLostHandler`.
- `CoreService` is the per-supervisor object exported over XPC to the extension.
  Its `mapError` translates `SSHError.connectionFailed → .serverUnreachable`,
  `authenticationFailed → .notAuthenticated`, and `sftpError(.noSuchFile) →
.remotePathNotFound` for the request result, but nothing in it changes
  supervisor state or suspends the domain.
- `ConnectionConfigEditView` disables **every** field while `enabled`, with the
  footer "Disable this connection to edit its settings." Editing is impossible
  without a destructive disable. `ConnectionCoordinator` tracks only the
  enable/disable task and its one-shot error per profile.

### Problems

1. **Editing an enabled profile requires cache loss.** The only edit path is
   disable (→ `ExtensionController.remove()`) → edit → enable. All cached files
   are gone.
2. **Unrecoverable failures spin.** An auth failure, host-key mismatch, or moved
   remote path thrown while connecting is caught by the generic `catch` in the
   `connectTask` backoff loop and retried **forever** — repeatedly hammering the
   server with input that will never work. On the request path the same errors
   surface as `.notAuthenticated` / `.remotePathNotFound` but neither stops the
   connect loop nor signals the user that intervention is needed.
3. **No user-visible connection health.** The domain suspends with a Finder
   reason on a server drop, but the app UI shows only a binary enabled switch —
   no "connected / reconnecting / needs attention," and no affordance to fix a
   broken connection short of the destructive disable.

## Goals

- Let the user edit an enabled profile and reconnect **without losing the local
  cache**.
- Let the user **pause** an enabled connection (and later reconnect), preserving
  the cache. Pause is **session-only**: it is not persisted, so an app relaunch
  reconnects every enabled profile, including any that were paused.
- Stop retrying on unrecoverable errors; instead suspend with an actionable
  reason and wait for the user.
- Surface live SSH connection health in the app UI, with a path to fix a broken
  connection in place.
- Keep the existing transient auto-recovery (the `.offline` backoff/reconnect
  loop) untouched — this is an orthogonal state, not a change to it.

## Non-goals

- A second _domain_ toggle. `enabled` (domain existence, and thus the cache)
  stays the only destructive control. Pause is a non-destructive, **session-only**
  intent to stand the connection down while the domain — and its cache — stay in
  place; it is **not** persisted (no model flag) and does not survive relaunch.
- A raw always-visible "connect/disconnect" switch. Pausing/resuming is exposed
  as explicit **Pause** and **Reconnect** actions surfaced with connection
  status, not as a second toggle sitting next to Enabled.
- Offline write queueing (still out of scope).

## Proposed design

### Core: the `SSHState` machine

The supervisor's two SSH states were `.offline` (with a separate `connectTask`
field running the backoff loop) and `.online(Session)`. Rework this into three
states that make the connect loop and its terminal-until-user counterpart
explicit, **folding the loop's `Task` into the state** so the "is the loop
running" fact can't drift from a separate field:

```swift
private enum OfflineReason {
    case user                   // the user asked to pause
    // …future unrecoverable causes (PR 3)
}

private enum SSHState {
    case offline(OfflineReason)         // stopped, waits for the user
    case connecting(Task<Void, Never>)  // backoff retry loop is running
    case online(Session)
}
```

```
offline(reason) ──enable / reconfigure──▶ connecting ⇄ online
       ▲                                       │  (backoff retry; self-heals)
       └──────────── user pause / disable ─────┘
```

- `.connecting` carries the backoff `Task`. It self-heals: on connection loss
  from `.online`, `reconnectSession` tears the session down and re-enters
  `.connecting` (unchanged transient behavior).
- `.offline(reason)` **stops the connect/poll loop**, closes the session, tears
  down XPC, and suspends the domain with a reason derived from the
  `OfflineReason`. It is entered by a user pause **or** (PR 3) an unrecoverable
  error, and left **only** by an explicit user action (`enable` / `reconfigure`),
  never by the backoff loop. The default initial state is `.offline(.user)`.

`enable()` is the single "start the connect loop" primitive: it guards against a
double-start (`if case .connecting = state { return }`) and installs the
`.connecting(Task)`. `reconfigure` and the connection-loss handler both funnel
through it, so there is no separate `startConnecting`. `connectSession` re-checks
`case .connecting` after the connect returns and closes the session if the state
changed underneath it (a pause/disable landed mid-connect on a provider that
ignored cancellation) — see Risks.

The `OfflineReason` drives the Finder suspend reason and (PR 2) the app's status
copy: `.user` → "The connection is paused."; the PR 3 error cases → specific,
actionable messages.

### Core: error classification

Introduce an `isUnrecoverable` bucket alongside the connection-loss bucket that
`Session.mapError` already keys on:

| Error                                             | Bucket        | Reaction                                                    |
| ------------------------------------------------- | ------------- | ----------------------------------------------------------- |
| `SSHError.connectionFailed` / sftp connectionLost | recoverable   | `reconnectSession` → `.connecting` → backoff retry (unchanged) |
| `SSHError.authenticationFailed`                   | unrecoverable | → `.offline(.authenticationFailed)`                         |
| host-key mismatch                                 | unrecoverable | → `.offline(.hostKeyChanged)`                               |
| `SSHError.sftpError(.noSuchFile…)` (remote path)  | unrecoverable | → `.offline(.remotePathNotFound)`                           |

Two paths must honor the new bucket:

1. The **backoff loop** (`connectLoop`, inside `.connecting`) — today the generic
   `catch` logs and retries _everything_ forever. Add a branch that, on
   `isUnrecoverable`, transitions to `.offline(reason)` (suspend + stop the loop)
   instead of retrying. This is the concrete fix for problem #2.
2. The **connection-loss path** in `Session.mapError` / the `ConnectionLostHandler`
   — today only recoverable connection-loss errors reach `reconnectSession`. An
   unrecoverable error hit on a live session must route to `.offline(reason)`
   rather than to the retrying `reconnectSession`.

Host-key mismatch is worth a distinct affordance later ("trust the new key");
for this pass it shares the `paused` path with its own reason string.

### Core: the `reconfigure` path

Add `reconfigure(config:)` down the stack so the app can hand the supervisor a
freshly resolved `ConnectionConfig` after an edit:

- `DomainRegistry.reconfigure(config:)` → `SessionSupervisor.reconfigure(config:)`.
  This runs entirely app-side: the app already talks to `DomainRegistry.shared`
  directly (via `ConnectionConfigModel`), and `CoreService` is now the
  per-supervisor _extension-facing_ XPC object, so reconfigure does **not** thread
  through it.
- The supervisor: `reconfigure` is only ever reached from `.offline` (the user
  paused first, so there is no live session or connect task), which it asserts
  with `guard case .offline = state`. It swaps its stored `config` and calls
  `enable()` to re-enter `.connecting`; `connectSession` **resume**s on success.
  **No `ExtensionController.remove()` / re-add**, so the cache and `DomainDB`
  survive. Because `enable()` is the shared start-the-loop primitive, no separate
  `reconnect()` is needed — a reconnect with no edits is just `reconfigure` with
  the same values.

This only requires the supervisor's `config` to become mutable (today a `let`).
The injected `SessionProvider` already takes the `ConnectionConfig` as a call-time
parameter (`connect(config) { … }`), so there is **no closure to rebuild** —
`connectSession` just passes the current `config`. The edited `ConnectionConfig`
is a resolved value type (secrets pulled from Keychain at build time), so the app
builds a fresh one from the model via the existing `ConnectionConfig(from:)` and
passes it down.

`DomainRegistry` also needs to update its `configs[id]` entry so a later
lazily-created supervisor uses the new config.

### Core + app: user-initiated pause (session-only)

`pause()` on the supervisor: cancels the in-flight connect, stops polling, tears
down XPC, suspends the domain ("The connection is paused."), closes the session,
and transitions to `.offline(.user)`. It threads through `DomainRegistry.pause(id:)`
like `reconfigure` (not through `CoreService`). The reverse trip is just
`reconfigure` → `enable()`.

**Pause is not persisted.** It is deliberately session-only: there is no `paused`
flag on `ConnectionConfigModel` and no change to the launch path. On relaunch,
`enabledConfigs()` still hands every enabled profile to
`DomainRegistry.enable(config:)`, which connects — so a profile that was paused
before quitting comes back online. `enable`/`enabledConfigs`/`SSHadowApp` are
therefore untouched by this work.

Because the connection is otherwise indistinguishable from a healthy one
(`enabled == true`, not busy, no error), the UI needs an in-process record of
"the user paused this." That lives in `ConnectionCoordinator` — the `@Observable`
app-process object the editor already watches — as an in-memory `Set<UUID>`
(`pausedIds`), added on `pause` and removed on a successful `reconnect`. It is
created fresh each launch, which _is_ the desired forget-on-relaunch behavior.
The coordinator is the sole initiator of a user pause, so it cannot diverge from
the supervisor's `.offline(.user)`. (PR 3's error pauses are set by the supervisor,
not the coordinator; PR 2's health snapshot is what sources those.)

### UI: status + contextual action, one switch

Keep the single **Enabled** switch as the domain-lifecycle control (still
guarded, still destructive-off). Surface connection state as **status + a
contextual action** rather than a second toggle.

**`ConnectionConfigEditView`.** Replace the "disable to edit" lock with:

- A **Status row** under the Enabled toggle (shown while `enabled`). It reuses
  the existing `ConnectionTestStatusView`, driven by `ConnectionCoordinator`'s
  busy/error state — so the pause/reconnect action shows the same "Verifying…"
  spinner and the same validation/`SSHClient.TestError` labels that the Enabled
  toggle already produces, for free.
- A **Pause** button (shown while `enabled` and not paused) calls
  `coordinator.pause(config)`; while `coordinator.isPaused(config)` it becomes
  **Reconnect**. Pausing unlocks the config fields.
- Fields lock only during healthy operation (`enabled && !isPaused`). While
  paused, the fields unlock so the profile can be edited in place.
- **Reconnect** validates + tests the edited model and calls the `reconfigure`
  path. This is the "stand the connection down, edit, bring it back" flow — cache
  is never at risk, and no destructive disable occurs. On a validation/test
  failure the profile stays paused (fields stay unlocked) and the error renders
  in the Status row.
- The richer live-health vocabulary (_Connected_ / _Connecting…_ / _Reconnecting…_
  / **Needs attention**) arrives in PR 2 with the health snapshot; PR 1's row
  shows only the busy/error state plus the Pause/Reconnect action.

**`RichMenuProfileToggle`.** Add a small health glyph next to the profile: green
dot (connected), spinner (connecting/reconnecting), pause glyph (user-paused),
amber `exclamationmark.triangle` (error pause / needs attention). Clicking a
paused or needs-attention row deep-links to that profile's editor. The switch
stays as-is (enabled).

**Sourcing live health (PR 2).** The Settings UI and `DomainRegistry.shared`
(with its supervisors) run in the **same app process**, so this needs no XPC
plumbing: expose a per-domain health snapshot from the supervisor (an
`@Observable` snapshot or an `AsyncStream`) and have the app subscribe.
`ConnectionCoordinator` today tracks only the enable/disable task and its
one-shot error; PR 1 adds its in-memory `pausedIds` for the user-pause action,
and PR 2 extends it to carry live per-domain health. The extension continues to
learn state via the suspend reason in Finder.

## Rollout (PR sequence)

PR 1 is a full vertical slice — it lands the user-pause **payoff** end-to-end so
the feature is usable immediately: an editor button that stands the connection
down, unlocks the fields, and applies the edit via `reconfigure` **without
removing the domain**. PR 2 then makes connection health visible, and PR 3 folds
unrecoverable errors into the same pause machinery.

### PR 1 — Reconfigure in the editor: pause, edit, reconnect (end-to-end)

The complete user-pause slice, from the supervisor to the button.

- **Core.** Rework `SSHState` into `.offline(OfflineReason)` / `.connecting(Task)`
  / `.online(Session)` (only `OfflineReason.user` for now), folding the backoff
  `Task` into `.connecting`. `enable()` becomes the single start-the-loop
  primitive; `connectSession` re-checks `.connecting` after connecting. Add
  `pause()` and `reconfigure(config:)` on `SessionSupervisor` →
  `DomainRegistry`, making the supervisor's `config` mutable. `pause()` suspends +
  closes + `.offline(.user)`; `reconfigure(config:)` (guarding `case .offline`)
  swaps the config and calls `enable()`. **No `ExtensionController.remove()` /
  re-add**, so the cache and `DomainDB` survive.
- **Model / launch.** No persistence changes. `ConnectionConfigModel` gains thin
  `pause()` / `reconnect()` passthroughs (`reconnect()` validates + tests, then
  calls `DomainRegistry.reconfigure`); `enable`, `AppDB.enabledConfigs`, and
  `SSHadowApp` are untouched, so relaunch reconnects every enabled profile.
- **UI.** In `ConnectionCoordinator`, track pause intent in an in-memory
  `pausedIds: Set<UUID>` (added on `pause`, removed on a successful `reconnect`)
  and route both actions through the existing task/error bookkeeping. In
  `ConnectionConfigEditView`, add the **Status row** (reusing
  `ConnectionTestStatusView`) with a **Pause** button that stands the connection
  down and unlocks the fields; while `coordinator.isPaused(config)` it becomes
  **Reconnect**, which calls `reconfigure`. This drives entirely off `pausedIds`
  plus the coordinator's busy/error state, so **no live-health plumbing is needed
  yet**. The old "disable to edit" lock is replaced by "pause to edit."

Manual test: pause a healthy connection → domain suspends ("The connection is
paused."), fields unlock; edit host/path → Reconnect → resumes with the new
config, **cache intact, no `remove()`**. Quit and relaunch → the profile
reconnects (pause is forgotten). Tests: `reconfigure` from `.offline` reconnects
with the new config; `pause` from `.online` ends in `.offline(.user)` with the
session closed and the domain suspended.

### PR 2 — Live SSH health surfaced to the app

Expose a per-domain health snapshot from the supervisor (an `@Observable`
snapshot or an `AsyncStream`) and wire `ConnectionCoordinator` to observe it.
Enrich PR 1's **Status row** with live health copy (_Connected_ / _Connecting…_ /
_Reconnecting…_ / **Paused**) and add the health glyph + deep-link in
`RichMenuProfileToggle`. No new behavior beyond reflecting state that PR 1
already produces. Tests/manual: health transitions reflected in the status row
and the menu glyph.

### PR 3 — Auto-pause on unrecoverable errors

Extend `OfflineReason` with `.authenticationFailed`, `.hostKeyChanged`, and
`.remotePathNotFound`, add the `isUnrecoverable` bucket, and route the two paths
to `.offline(reason)` instead of retrying: the `connectLoop` backoff loop and the
`ConnectionLostHandler` / `Session.mapError` path (suspend + stop retrying). This
reuses PR 1's `.offline` machinery and Reconnect flow and PR 2's health surface —
an error pause now shows **Needs attention** with the reason and unlocks the
fields, exactly like a user pause. Like the user pause, error pauses are
**ephemeral**; on relaunch the connection re-attempts and re-derives the same
error, re-entering `.offline(reason)` naturally. Tests: an unrecoverable connect
error suspends and stops the backoff loop; a transient `connectionFailed` still
`reconnectSession`s and auto-retries (regression guard). Manual: break auth
server-side → editor shows "needs attention" with reason, fields unlocked, cache
present in Finder; fix credentials → Reconnect → domain resumes and sync catches
up, **no files lost**.

## Risks and open questions

- **Pause is session-only (decided).** Neither user nor error pauses are
  persisted; there is no model flag. On relaunch every enabled profile reconnects
  — a user pause is simply forgotten, and an error pause re-derives by re-hitting
  the error. This trades "a paused profile stays paused across relaunch" for a
  much simpler PR 1 (no SwiftData migration, no launch-path threading) and the
  behavior the user wanted: relaunch always attempts to connect.
- **Connect racing a pause (decided).** `pause()` / `disable()` cancel the
  in-flight connect, but a `SessionProvider` that ignores cancellation could still
  return a live session. `connectSession` therefore re-checks `case .connecting`
  after the connect returns and closes the session if the state changed
  underneath it, so a pause landing mid-connect cannot be clobbered back to
  `.online`.
- **`remotePathNotFound` is unrecoverable (decided).** Treated as a config error
  → `.offline(.remotePathNotFound)`. A path that vanishes transiently on a healthy
  server will therefore require an explicit reconnect rather than auto-recovering;
  accepted trade-off.
- **Host-key mismatch UX.** Shares the `.offline(reason)` path here with its own
  reason; a dedicated "trust new key" affordance is a follow-up.
- **In-flight transfers during reconfigure.** Fail on the old session (correct),
  the same guarantee the existing SSH-disconnect recovery relies on; confirm no
  partial state is left in `FileCache`.
- **Edit concurrency.** While fields are unlocked, the running config and the
  edited model diverge; "Reconnect" is the only apply path, and the model save in
  `reconfigure` must be the source of truth handed to the supervisor.
