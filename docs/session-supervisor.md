# Design: SessionSupervisor and connection resilience

## Status

Proposed — not yet implemented.

## Summary

The app currently assumes that once an SSH session is established it stays alive.
When a remote server goes offline there is no coherent recovery: the background
poll loop spins on a dead connection, a stale session can be handed back out, and
the domain's connection state (suspend/resume) is written by three uncoordinated
places. This document proposes a per-domain `SessionSupervisor` that owns the live
SSH session and its reconnection, folds in the per-domain `NSXPCConnection` (today's
`DomainXPCBroker`), and becomes the single authority that suspends and resumes a
domain based on composite health.

## Terminology

Three distinct connection/state layers, each with its own verb pair. Keep them
separate in code, comments, and log messages.

| Layer                   | Verbs                    | Mechanism                                                                                                    |
| ----------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| App ↔ extension link    | **resume / suspend**     | `NSFileProviderManager.reconnect()` / `disconnect(reason:)`; raw `NSXPCConnection.resume()` / `invalidate()` |
| App ↔ remote SSH server | **connect / disconnect** | `SSHClient.connect` / `close`                                                                                |
| File Provider domains   | **enable / disable**     | `NSFileProviderManager.add` / `remove`                                                                       |

So "the server went offline" is an **SSH disconnect**, and the desired reaction is
to **suspend** the domain with a reason, then **connect** again and **resume**.

## Background: current architecture

- `Session` (actor, CoreKit) — holds a single `ssh`/`sftp`/`db`/`FileCache` created
  once at connect time. Its `ssh`/`sftp` are `let`s, so it cannot reconnect itself;
  reconnecting fundamentally means replacing the whole `Session`. It also owns the
  background poll loop (`run`/`start`).
- `SessionManager` (actor, CoreKit) — maps `UUID → Session`, with single-flight
  connect via `connectTasks`. Caches sessions; returns a cached session if present.
- `CoreService` (CoreKit) — the object exported over XPC to the extension. Every
  request calls `sessions.connect(id: request.domainId)` then delegates to the
  session. `mapError` catches `SSHError.connectionFailed`, calls
  `sessions.disconnect(id:)`, and returns `.serverUnreachable`.
- `DomainXPCBroker` (`@MainActor` singleton, CoreKit) — maps `UUID → NSXPCConnection`,
  sets `CoreService.shared` as the exported object, handles invalidation/interruption
  by re-brokering, and calls `domain.resume()` at the top of every broker.
- `CoreClient` (Common, extension side) — suspends the domain when it loses its XPC
  link to the app.

### Problems

1. **The poll loop never recovers.** `Session.run` catches errors, logs, and loops on
   the same dead `Session` forever. Only the request path drops the session.
2. **No proactive recovery or liveness detection.** Recovery is purely lazy (next
   request re-connects) and only on the request path.
3. **Domain connection state has three uncoordinated writers.** The extension suspends
   on XPC loss; `DomainXPCBroker.broker` unconditionally calls `domain.resume()`;
   and (proposed) SSH health wants to suspend/resume too. Concretely, this is a race:
   an SSH-disconnect suspend can be clobbered by a re-broker's unconditional
   `domain.resume()`, resuming a domain whose server is still down.

## Goals

- A single per-domain owner of the live SSH session that can rebuild it after a
  disconnect, with single-flight connect preserved.
- The poll loop participates in recovery instead of spinning.
- One authority decides domain suspend/resume, using **both** the XPC-link health and
  the SSH health, so the two can never fight.
- On SSH disconnect, suspend the domain with a user-facing reason
  ("The server is currently unreachable; check your network connection."), retry the
  connection on a backoff, and resume when it recovers.

## Non-goals

- Changing the SSH library or the SFTP operation set.
- Reworking the File Provider enumeration/change-tracking model.
- Offline write queueing. Suspended domains remain browsable (per
  `NSFileProviderManager.disconnect` semantics) but do not accept new sync while down.

## Proposed design

### Types

| Name                                    | Isolation          | Responsibility                                                                                                                                              |
| --------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Session` (keep)                        | actor              | One _connected_ SSH session: `ssh`+`sftp`+`db`+`cache` and the file operations. Immutable connection; replaced wholesale on reconnect. Loses the poll loop. |
| `DomainRegistry` (was `SessionManager`) | actor              | Thin `[UUID: SessionSupervisor]` registry. `register`/`connect`/`disconnect`/`forget` delegate to a supervisor.                                             |
| `SessionSupervisor` (new)               | actor              | Per-domain owner of the live `Session`: single-flight connect, reconnect, poll loop, health state, and the single decision-maker for suspend/resume.        |
| `DomainLink` (new)                      | `@MainActor` class | Per-domain owner of the `NSXPCConnection` to the extension plus domain suspend/resume. The supervisor's main-actor arm. Absorbs `DomainXPCBroker`.          |
| `DomainXPCBroker`                       | —                  | Removed. Per-domain slice becomes `DomainLink`; the singleton-with-a-dict disappears.                                                                       |

### Isolation rationale

SSH work must stay off the main actor; `NSXPCConnection` setup and
`NSFileProviderManager` calls must be on it. Rather than smear one object across both,
`SessionSupervisor` is a (non-main) actor that _holds_ a `@MainActor DomainLink`. The
supervisor is the single authority that decides suspend/resume; `DomainLink` is only
its main-actor hands. `DomainXPCBroker` still goes away — its responsibilities split
into `DomainLink` (mechanism) and the supervisor (policy).

### Health model

`SessionSupervisor` tracks SSH health as a small state machine:

```
connecting ──success──▶ connected
    ▲                       │
    │                    disconnect
    └────── retry ◀── disconnected
```

Inputs that drive a transition to `disconnected`: an `SSHError.connectionFailed` from
a request, or a failed poll. On entering `disconnected` the dead `Session` is dropped.
`currentSession()` connects if needed, coalescing concurrent callers onto one in-flight
`Task` (the existing `connectTasks` single-flight pattern, moved into the supervisor).
While `disconnected`, a retry loop attempts `connect` on a backoff.

Domain resume is **gated on composite health**: the supervisor resumes only when the
XPC link is up _and_ SSH is connected. This is what prevents a re-broker from resuming
a domain whose server is still down.

### Extension-side fallback

The supervisor can only act while the app process is alive. So `CoreClient`'s
self-suspend on XPC loss stays, demoted to the app-absent fallback: it suspends when
the extension can't reach the app, but when the app is present the supervisor is the
resume authority.

## Rollout (PR sequence)

Strict order 1 → 2 → 3 → 4; PR 5 depends on 3. PRs 1 and 3 are behavior-preserving
relocations; the user-visible win lands in PR 4.

### PR 1 — Extract `SessionSupervisor` (no behavior change) [DONE]

Introduce the supervisor as a pure refactor. Move single-flight connect
(`connectTasks`), `start()`, and the poll loop (`run`) out of `Session`/`SessionManager`
into `SessionSupervisor`. `Session` shrinks to "a connected session + operations" and
no longer holds `bgTask`. Rename `SessionManager` → `DomainRegistry`, now a
`[UUID: SessionSupervisor]` map. `CoreService` keeps calling `registry.connect(id:)`
per request. Behavior identical; update `SessionTests`.

### PR 2 — Reconnect + health state [DONE]

Add the health state machine to `SessionSupervisor`. On `SSHError.connectionFailed`
(request _or_ poll), transition to `disconnected` and drop the dead `Session`; next
`currentSession()` reconnects via single-flight. The poll loop stops spinning on a dead
session — on failure it transitions health and retries connect with backoff. Move the
recovery currently in `CoreService.mapError` (`sessions.disconnect` on
`connectionFailed`) into the supervisor so there is one recovery path. Still
app-internal — no domain suspend/resume yet. Tests: reconnect-after-drop, poll recovers
after a transient disconnect.

### PR 3 — Move XPC ownership into `DomainLink`; retire `DomainXPCBroker` [DONE]

Introduce `@MainActor DomainLink` owning the per-domain `NSXPCConnection`, exported
object, and the invalidation/interruption/re-broker handling from
`DomainXPCBroker.broker`. Each `SessionSupervisor` creates and holds its `DomainLink`.
Delete the `DomainXPCBroker` singleton; domain registration now creates supervisors.
Keep resume behavior equivalent for now (centralized, not yet gated). Tests: attach/
detach and re-broker-on-invalidation still work.

### PR 4 — Wire SSH health to domain suspend/resume (the payoff) [DONE]

On transition to `disconnected`, call
`link.suspend(reason: "The server is currently unreachable; check your network connection.")`.
The retry loop connects with backoff; on success it resumes — gated on composite health
(XPC up _and_ SSH connected), closing the re-broker race. Demote `CoreClient.suspend`
to the app-absent fallback. Manual test: kill the server → domain suspends with the
reason in Finder; restore → domain resumes and sync catches up.

**Verify before merge** (behaviors the retry loop leans on, not documented explicitly):

1. `reconnect()` is a safe no-op when already connected, and repeated
   `disconnect(reason:)` updates the displayed reason.
2. Suspend / re-broker ordering plays nicely with `waitForStabilization`.

### PR 5 (optional) — Drop `domainId` routing in `CoreService`

Now that each `DomainLink` exports a domain-scoped object, refactor
`CoreXPC`/`CoreProtocol` so requests no longer carry `domainId`; the per-domain exported
object routes straight to its own supervisor. Removes the
`registry.connect(id: request.domainId)` boilerplate at the top of every `CoreService`
method and simplifies every `*Request`. Protocol-wide change, so it earns its own PR —
and it is the concrete simplification that justifies folding XPC into the per-domain
object.

## Optional naming cleanup

Align method names with the terminology table: `SSHClient.close` → `disconnect`, and if
desired `FileProviderDomain.add`/`remove` → `enable`/`disable`. Can ride along with an
existing PR or stand alone.

## Risks and open questions

- **`NSFileProviderManager` idempotency** — see PR 4 verification items; the retry loop
  assumes repeated suspend/resume is safe.
- **In-flight transfers during a disconnect** — an upload/download in progress fails on
  the old `Session` (correct); the retry gets a fresh session. Confirm no partial state
  is left in `FileCache` or the staged-file paths.
- **Backoff policy** — interval, jitter, and cap unspecified; pick something that keeps
  the poll loop cheap while recovering promptly once the server returns.
- **Detection latency** — without SSH keepalives, a disconnect is only noticed on the
  next request/poll (up to `pollInterval`, currently 30s). A keepalive would tighten
  this; treat as a follow-up.
