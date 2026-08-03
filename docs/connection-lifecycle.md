# Design: separating domain lifecycle from connection lifecycle

## Status

Proposed — not yet implemented. Builds on `docs/session-supervisor.md` (PRs 1–4
done); this is effectively PR 6 of that effort.

## Summary

Today a connection profile has a single control — `enabled` — that fuses two
concerns: **does the File Provider domain exist** (and therefore its local
cache) and **should we be connecting to the server**. The only way to edit an
enabled profile is to disable it, and disabling calls `domain.remove()`, which
**deletes all locally cached files**. So a profile that fails for an
unrecoverable reason — the server-side auth changed, the host key rotated, the
remote path moved — forces the user to choose between an unusable connection and
throwing away their cache to fix it.

This document proposes decoupling the two. An enabled domain stays enabled (and
cached) while its SSH connection can be intentionally stood down — either by the
user (a **pause**) or by the supervisor on an unrecoverable error — so the user
can edit the profile and reconnect. The mechanics already exist:
`suspend(reason:)` preserves the domain and its cache — it is `disable()` that is
destructive. What is missing is (1) a supervisor health state for "stopped,
waiting for the user," (2) a `reconfigure` path that rebuilds the `Session` with
a new config without touching the domain, and (3) UI to surface connection health
and drive the pause / edit / reconnect flow.

## Terminology

Reuses the three-layer vocabulary from `docs/session-supervisor.md`:

| Layer                   | Verbs                    | Mechanism                                                                    |
| ----------------------- | ------------------------ | ---------------------------------------------------------------------------- |
| App ↔ extension link    | **resume / suspend**     | `NSFileProviderManager.reconnect()` / `disconnect(reason:)`                  |
| App ↔ remote SSH server | **connect / disconnect** | `SSHClient.connect` / `close`                                                |
| File Provider domains   | **enable / disable**     | `NSFileProviderManager.add` / `remove` — **disable deletes the local cache** |

The crucial asymmetry this design leans on: **suspend preserves the cache;
disable destroys it.** "Stand down the connection so the user can edit" is a
**suspend + disconnect**, never a disable.

## Background: current architecture

- `ConnectionConfigModel.enabled` (SwiftData) is the single persisted control.
  `enable()` saves the model, tests SSH, `register`s the config, `domain.add()`s,
  and brokers XPC. `disable()` tears down XPC, `domain.remove()`s (destructive),
  and `forget`s the config.
- `ConnectionConfigEditView` disables **every** field while `enabled`, with the
  footer "Disable this connection to edit its settings." Editing is impossible
  without a destructive disable.
- `SessionSupervisor` health is a three-state machine: `connecting → connected`,
  and `disconnected`, which auto-retries `connect()` on a backoff **forever**.
  `withSession` drops the session only on `error.isConnectionFailed`; the poll
  loop `run()` catches _all_ errors generically and retries indefinitely.
- `mapError` in `CoreService` translates `SSHError.authenticationFailed →
.notAuthenticated` for the request result, but nothing changes supervisor
  health or suspends the domain on an auth failure.

### Problems

1. **Editing an enabled profile requires cache loss.** The only edit path is
   disable (→ `domain.remove()`) → edit → enable. All cached files are gone.
2. **Unrecoverable failures spin.** An auth failure or host-key mismatch is not
   `connectionFailed`, so `withSession` does not drop, and the poll loop retries
   it forever on a backoff — repeatedly hammering the server with credentials
   that will never work, with no signal to the user that intervention is needed.
3. **No user-visible connection health.** The domain suspends with a Finder
   reason on a server drop (PR 4), but the app UI shows only a binary enabled
   switch — no "connected / reconnecting / needs attention," and no affordance
   to fix a broken connection short of the destructive disable.

## Goals

- Let the user edit an enabled profile and reconnect **without losing the local
  cache**.
- Let the user **pause** an enabled connection (and later reconnect), preserving
  the cache and surviving app relaunch.
- Stop retrying on unrecoverable errors; instead suspend with an actionable
  reason and wait for the user.
- Surface live SSH connection health in the app UI, with a path to fix a broken
  connection in place.
- Keep the transient auto-recovery from `docs/session-supervisor.md` untouched —
  this is an orthogonal state, not a change to backoff/reconnect.

## Non-goals

- A second _domain_ toggle. `enabled` (domain existence, and thus the cache)
  stays the only destructive control. A new persisted `paused` flag is added, but
  it is non-destructive: it records user intent to stand the connection down
  while the domain — and its cache — stay in place.
- A raw always-visible "connect/disconnect" switch. Pausing/resuming is exposed
  as explicit **Pause** and **Reconnect** actions surfaced with connection
  status, not as a second toggle sitting next to Enabled.
- Offline write queueing (still out of scope, per the parent doc).

## Proposed design

### Core: a fourth health state

Extend `SessionSupervisor.Health` with a terminal-until-user `paused` state that
carries _why_ it was paused:

```swift
enum Health {
    case connecting
    case connected
    case disconnected
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
connecting ──▶ connected ──▶ disconnected ⇄ retry     (transient, self-heals)
                   │
        user pause │ unrecoverable error
                   ▼
             paused(reason)                            (stopped, waits for user)
```

- `disconnected` keeps its current meaning: transient, auto-retry on backoff.
- `paused` **stops the poll/retry loop**, closes the session, and suspends the
  domain with a reason string derived from the `PauseReason`. It is entered by a
  user pause **or** an unrecoverable error, and exited **only** by an explicit
  user action (`reconnect` / `reconfigure`), never by the backoff loop.

The `PauseReason` drives the Finder suspend reason and the app's status copy:
`.user` → "Connection paused"; the error cases → specific, actionable messages.

`Health` stops being trivially `Equatable`-by-case once it carries a payload;
tests asserting on health should compare the case (or a computed `isPaused`).

### Core: error classification

Introduce an `isUnrecoverable` bucket alongside the existing `isConnectionFailed`:

| Error                                            | Bucket        | Reaction                                          |
| ------------------------------------------------ | ------------- | ------------------------------------------------- |
| `SSHError.connectionFailed`                      | recoverable   | drop → `disconnected` → backoff retry (unchanged) |
| `SSHError.authenticationFailed`                  | unrecoverable | → `paused(.authenticationFailed)`                 |
| host-key mismatch                                | unrecoverable | → `paused(.hostKeyChanged)`                       |
| `SSHError.sftpError(.noSuchFile…)` (remote path) | unrecoverable | → `paused(.remotePathNotFound)`                   |

Two call sites must honor the new bucket:

1. `withSession` — today `catch let error as SSHError where
error.isConnectionFailed`. Add a branch that, on `isUnrecoverable`,
   transitions to `paused(reason)` (close session + suspend) and rethrows.
2. `run()` (the poll loop) — today the generic `catch` retries _everything_. It
   must break out to `paused` on unrecoverable errors instead of looping. This is
   the concrete fix for problem #2.

Host-key mismatch is worth a distinct affordance later ("trust the new key");
for this pass it shares the `paused` path with its own reason string.

### Core: the `reconfigure` path

Add `reconfigure(config:)` down the stack so the app can hand the supervisor a
freshly resolved `ConnectionConfig` after an edit:

- `CoreService.reconfigure(config:)` → `DomainRegistry.reconfigure(config:)` →
  `SessionSupervisor.reconfigure(config:)`.
- The supervisor: cancels any in-flight connect, closes the old session, swaps
  its stored config, clears the `paused` state, then `connect()`s and (on
  success, gated on composite health) resumes. **No `domain.remove()` /
  `add()`**, so the cache and `DomainDB` survive.

This requires the supervisor to hold `config` as mutable state and rebuild its
`makeSession` closure from it — today `config` is captured immutably in the
closure at `init`. The edited `ConnectionConfig` is a resolved value type
(secrets pulled from Keychain at build time), so the app builds a fresh one from
the model via the existing `ConnectionConfig(from:)` and passes it down.

`DomainRegistry` also needs to update its `configs[id]` entry so a later
lazily-created supervisor uses the new config.

### Core: user-initiated pause and its persistence

`pause()` on the supervisor: cancels in-flight connect, closes the session,
transitions to `paused(.user)`, and suspends the domain ("Connection paused").
`reconnect()` (shared with the reconfigure exit) clears `paused`, connects, and
resumes on success. Both thread through `DomainRegistry` and `CoreService` like
`reconfigure`.

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

**Sourcing live health.** The Settings UI and `CoreService.shared` run in the
**same app process**, so this needs no XPC plumbing: expose a per-domain health
snapshot from the supervisor (an `@Observable` snapshot or an `AsyncStream`) and
have the app subscribe. `ConnectionCoordinator` today tracks only the
enable/disable task and its one-shot error; extend it (or add a sibling) to
carry live per-domain health. The extension continues to learn state via the
suspend reason in Finder.

## Rollout (PR sequence)

### PR A — Health state + error classification (core only)

Add `paused(PauseReason)` to `Health`, the `isUnrecoverable` bucket, and the
`withSession` / `run()` branches that route to it (close session + suspend + stop
retrying). No `reconfigure`, no user pause, no UI yet. Move the current
auth-failure handling so there is one recovery policy. Tests: unrecoverable error
suspends and stops the poll loop; transient error still auto-retries (regression
guard).

### PR B — `reconfigure` + user pause down the stack (core only)

Add `reconfigure(config:)`, `pause()`, and `reconnect()` on supervisor →
registry → `CoreService`, making the supervisor's config mutable. Add the
persisted `paused` flag to `ConnectionConfigModel` and honor it at launch (a
paused enabled domain is added but not connected). Verify no `domain.remove`/`add`
occurs and the cache/`DomainDB` survive a reconfigure or a pause/reconnect cycle.
Tests: reconfigure from `paused` rebuilds with new config and resumes; user pause
persists across a simulated relaunch; error pause does not.

### PR C — Live health surfaced to the app

Expose the per-domain health snapshot from the supervisor and wire
`ConnectionCoordinator` to observe it. No behavior change yet beyond the app
being able to read health. Tests/manual: health transitions reflected in a
simple debug read-out.

### PR D — Editor + menu UI (the payoff)

Replace the "disable to edit" lock with the status row + Pause/Reconnect flow in
`ConnectionConfigEditView`; add the health glyph and deep-link in
`RichMenuProfileToggle`. Manual tests: (1) break auth server-side → domain
suspends with reason, profile shows "needs attention," cache still present in
Finder; fix credentials → Reconnect → domain resumes and sync catches up, **no
files lost**. (2) Pause a healthy connection → suspends, fields unlock, survives
app relaunch still paused; Reconnect → resumes.

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
  same guarantee PR 4 relies on; confirm no partial state is left in `FileCache`.
- **Edit concurrency.** While fields are unlocked, the running config and the
  edited model diverge; "Reconnect" is the only apply path, and the model save in
  `reconfigure` must be the source of truth handed to the supervisor.
