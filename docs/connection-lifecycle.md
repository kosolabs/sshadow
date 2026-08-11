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
  the cache and surviving app relaunch.
- Stop retrying on unrecoverable errors; instead suspend with an actionable
  reason and wait for the user.
- Surface live SSH connection health in the app UI, with a path to fix a broken
  connection in place.
- Keep the existing transient auto-recovery (the `.offline` backoff/reconnect
  loop) untouched — this is an orthogonal state, not a change to it.

## Non-goals

- A second _domain_ toggle. `enabled` (domain existence, and thus the cache)
  stays the only destructive control. A new persisted `paused` flag is added, but
  it is non-destructive: it records user intent to stand the connection down
  while the domain — and its cache — stay in place.
- A raw always-visible "connect/disconnect" switch. Pausing/resuming is exposed
  as explicit **Pause** and **Reconnect** actions surfaced with connection
  status, not as a second toggle sitting next to Enabled.
- Offline write queueing (still out of scope).

## Proposed design

### Core: a third `SSHState`

Today the supervisor's `SSHState` has two cases — `.offline` (with the
`connectTask` backoff loop running) and `.online(Session)`. Add a
terminal-until-user `.paused` case that carries _why_ it was paused:

```swift
private enum SSHState {
    case offline
    case online(Session)
    case paused(PauseReason)
}

enum PauseReason {
    case user                   // the user asked to pause
    case authenticationFailed
    case hostKeyChanged
    case remotePathNotFound
    // …future unrecoverable causes
}
```

```
online ⇄ offline (connectTask backoff retry)          (transient, self-heals)
   │         │
   │  user   │ unrecoverable error
   │  pause  ▼
   └──────▶ paused(reason)                             (stopped, waits for user)
```

- `.offline` keeps its current meaning: transient, the `connectTask` auto-retries
  on backoff.
- `.paused` **stops the connect/poll loop** (`stopConnecting` + `session.stopPolling`),
  closes the session, tears down XPC, and suspends the domain with a reason string
  derived from the `PauseReason`. It is entered by a user pause **or** an
  unrecoverable error, and exited **only** by an explicit user action (`reconnect`
  / `reconfigure`), never by the backoff loop.

The `PauseReason` drives the Finder suspend reason and the app's status copy:
`.user` → "Connection paused"; the error cases → specific, actionable messages.

Since the supervisor needs to project this state to the app UI (see "Sourcing
live health"), expose a small `Sendable` health snapshot rather than leaking the
private `SSHState`; a computed `isPaused` keeps tests off the payload.

### Core: error classification

Introduce an `isUnrecoverable` bucket alongside the connection-loss bucket that
`Session.mapError` already keys on:

| Error                                             | Bucket        | Reaction                                             |
| ------------------------------------------------- | ------------- | ---------------------------------------------------- |
| `SSHError.connectionFailed` / sftp connectionLost | recoverable   | `goOffline` → `.offline` → backoff retry (unchanged) |
| `SSHError.authenticationFailed`                   | unrecoverable | → `paused(.authenticationFailed)`                    |
| host-key mismatch                                 | unrecoverable | → `paused(.hostKeyChanged)`                          |
| `SSHError.sftpError(.noSuchFile…)` (remote path)  | unrecoverable | → `paused(.remotePathNotFound)`                      |

Two paths must honor the new bucket:

1. The **`connectTask` backoff loop** (`startConnecting`) — today the generic
   `catch` logs and retries _everything_ forever. Add a branch that, on
   `isUnrecoverable`, transitions to `.paused(reason)` (suspend + stop the loop)
   instead of retrying. This is the concrete fix for problem #2.
2. The **connection-loss path** in `Session.mapError` / the `ConnectionLostHandler`
   — today only recoverable connection-loss errors reach `goOffline`. An
   unrecoverable error hit on a live session must route to `paused(reason)` rather
   than to the retrying `goOffline`.

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
- The supervisor: cancels any in-flight connect (`stopConnecting`), closes the old
  session, swaps its stored config, clears the `paused` state, then starts
  connecting again — `goOnline` **resume**s on success. **No
  `ExtensionController.remove()` / re-add**, so the cache and `DomainDB` survive.

This only requires the supervisor's `config` to become mutable (today a `let`).
The injected `SessionProvider` already takes the `ConnectionConfig` as a call-time
parameter (`connect(config) { … }`), so there is **no closure to rebuild** —
`goOnline` just passes the current `config`. The edited `ConnectionConfig` is a
resolved value type (secrets pulled from Keychain at build time), so the app
builds a fresh one from the model via the existing `ConnectionConfig(from:)` and
passes it down.

`DomainRegistry` also needs to update its `configs[id]` entry so a later
lazily-created supervisor uses the new config.

### Core: user-initiated pause and its persistence

`pause()` on the supervisor: cancels in-flight connect, closes the session,
transitions to `paused(.user)`, and suspends the domain ("Connection paused").
`reconnect()` (shared with the reconfigure exit) clears `paused`, starts
connecting, and resumes on success. Both thread through `DomainRegistry` like
`reconfigure` (not through `CoreService`).

Unlike an error pause, a **user** pause has nothing to re-derive it from on
relaunch, so it must persist. Add a `paused` bool to `ConnectionConfigModel`,
distinct from `enabled`:

| Field     | Meaning                                 | On launch (when `enabled`)                                                                        |
| --------- | --------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `enabled` | domain exists; local cache exists       | domain is added                                                                                   |
| `paused`  | user asked to stand the connection down | connect only if **not** `paused`; a paused domain is added but left suspended, no connect attempt |

Error pauses (`.authenticationFailed`, `.hostKeyChanged`, `.remotePathNotFound`)
stay **ephemeral** — they are not written to `paused`; on relaunch the connection
re-attempts and re-derives the same error, re-entering `paused(reason)` naturally.
Only `.user` sets the persisted `paused` flag.

### UI: status + contextual action, one switch

Keep the single **Enabled** switch as the domain-lifecycle control (still
guarded, still destructive-off). Surface connection state as **status + a
contextual action** rather than a second toggle.

**`ConnectionConfigEditView`.** Replace the "disable to edit" lock with:

- A **connection status row** under the Enabled toggle showing live SSH health:
  _Connected_ / _Connecting…_ / _Reconnecting…_ / **Paused** / **Needs attention**
  (with the reason string, for error pauses).
- A **Pause** button (shown while connected) transitions to `paused(.user)`;
  while paused it becomes **Reconnect**. Pausing unlocks the config fields.
- Fields stay read-only during normal healthy operation. Whenever the connection
  is paused — by the user or by an error — the fields unlock so the profile can
  be edited in place.
- **Reconnect** saves the model and calls the `reconnect`/`reconfigure` path.
  This is the "stand the connection down, edit, bring it back" flow — cache is
  never at risk, and no destructive disable occurs.

**`RichMenuProfileToggle`.** Add a small health glyph next to the profile: green
dot (connected), spinner (connecting/reconnecting), pause glyph (user-paused),
amber `exclamationmark.triangle` (error pause / needs attention). Clicking a
paused or needs-attention row deep-links to that profile's editor. The switch
stays as-is (enabled).

**Sourcing live health.** The Settings UI and `DomainRegistry.shared` (with its
supervisors) run in the **same app process**, so this needs no XPC plumbing:
expose a per-domain health snapshot from the supervisor (an `@Observable`
snapshot or an `AsyncStream`) and have the app subscribe.
`ConnectionCoordinator` today tracks only the enable/disable task and its
one-shot error; extend it (or add a sibling) to carry live per-domain health.
The extension continues to learn state via the suspend reason in Finder.

## Rollout (PR sequence)

PR 1 is a full vertical slice — it lands the user-pause **payoff** end-to-end so
the feature is usable immediately: an editor button that stands the connection
down, unlocks the fields, and applies the edit via `reconfigure` **without
removing the domain**. PR 2 then makes connection health visible, and PR 3 folds
unrecoverable errors into the same pause machinery.

### PR 1 — Reconfigure in the editor: pause, edit, reconnect (end-to-end)

The complete user-pause slice, from the supervisor to the button.

- **Core.** Add a `.paused(PauseReason)` case to `SSHState` (only `.user` for
  now) — the "stopped, waiting for the user" state that halts the connect/poll
  loop. Add `pause()`, `reconnect()`, and `reconfigure(config:)` on
  `SessionSupervisor` → `DomainRegistry`, making the supervisor's `config`
  mutable. `pause()` suspends + closes + `.paused(.user)`; `reconnect()` /
  `reconfigure(config:)` clear `.paused`, swap the config, and start connecting
  again. **No `ExtensionController.remove()` / re-add**, so the cache and
  `DomainDB` survive.
- **Model.** Add the persisted `paused` bool to `ConnectionConfigModel`, distinct
  from `enabled`, and honor it at launch: a paused enabled domain has its
  `DomainDB` opened and config registered but is **not** connected (`enable()`
  skips `startConnecting`). Only `.user` writes this flag.
- **UI.** In `ConnectionConfigEditView`, add a **Pause** button (shown while
  enabled and running) that stands the connection down and unlocks the fields;
  while paused it becomes **Reconnect**, which saves the model and calls
  `reconfigure`. The button drives entirely off the persisted `paused` flag plus
  the `ConnectionCoordinator` busy/error state, so **no live-health plumbing is
  needed yet**. The old "disable to edit" lock is replaced by "pause to edit."

Manual test: pause a healthy connection → domain suspends ("Connection paused"),
fields unlock; edit host/path → Reconnect → resumes with the new config, **cache
intact, no `remove()`**. User pause survives an app relaunch (still paused).
Tests: reconfigure from `.paused` reconnects with the new config; user pause
persists across a simulated relaunch.

### PR 2 — Live SSH health surfaced to the app

Expose a per-domain health snapshot from the supervisor (an `@Observable`
snapshot or an `AsyncStream`) and wire `ConnectionCoordinator` to observe it.
Add the read-only **connection status row** to `ConnectionConfigEditView`
(_Connected_ / _Connecting…_ / _Reconnecting…_ / **Paused**) and the health glyph
+ deep-link in `RichMenuProfileToggle`. No new behavior beyond reflecting state
that PR 1 already produces. Tests/manual: health transitions reflected in the
status row and the menu glyph.

### PR 3 — Auto-pause on unrecoverable errors

Extend `PauseReason` with `.authenticationFailed`, `.hostKeyChanged`, and
`.remotePathNotFound`, add the `isUnrecoverable` bucket, and route the two paths
to `.paused(reason)` instead of retrying: the `connectTask` backoff loop and the
`ConnectionLostHandler` / `Session.mapError` path (suspend + stop retrying). This
reuses PR 1's pause machinery and Reconnect flow and PR 2's health surface — an
error pause now shows **Needs attention** with the reason and unlocks the fields,
exactly like a user pause. Error pauses stay **ephemeral** (not written to
`paused`); on relaunch the connection re-attempts and re-derives the same error.
Tests: an unrecoverable connect error suspends and stops the backoff loop; a
transient `connectionFailed` still `goOffline`s and auto-retries (regression
guard); error pause does not persist. Manual: break auth server-side → editor
shows "needs attention" with reason, fields unlocked, cache present in Finder;
fix credentials → Reconnect → domain resumes and sync catches up, **no files
lost**.

## Risks and open questions

- **Persistence split (decided).** A **user** pause persists via the model's
  `paused` flag and survives relaunch. **Error** pauses stay ephemeral and
  re-derive on relaunch by re-hitting the error. Only `.user` writes `paused`.
- **`remotePathNotFound` is unrecoverable (decided).** Treated as a config error
  → `paused(.remotePathNotFound)`. A path that vanishes transiently on a healthy
  server will therefore require an explicit reconnect rather than auto-recovering;
  accepted trade-off.
- **Host-key mismatch UX.** Shares the `paused` path here with its own reason; a
  dedicated "trust new key" affordance is a follow-up.
- **In-flight transfers during reconfigure.** Fail on the old session (correct),
  the same guarantee the existing SSH-disconnect recovery relies on; confirm no
  partial state is left in `FileCache`.
- **Edit concurrency.** While fields are unlocked, the running config and the
  edited model diverge; "Reconnect" is the only apply path, and the model save in
  `reconfigure` must be the source of truth handed to the supervisor.
