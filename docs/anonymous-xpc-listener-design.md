# SSHadow — Anonymous XPC Listener: Design Notes & Findings

**Status:** Investigation complete, no code changed. Ready to pick a transport and implement.
**Date:** 2026-07-09
**Prereq reading:** [`xpc-listener-investigation.md`](./xpc-listener-investigation.md) — establishes *why*
we need an anonymous listener (sandboxed GUI app cannot register a mach-service **listener** name
in launchd; EPERM outside the debugger).

## Goal

Replace the app's launchd-registered mach-service listener
(`XPCListener(service: SSHadow.appServiceName)` in `AgentKit/Agent.swift:47`) with an **anonymous**
listener that never registers a name in launchd's bootstrap namespace, then hand its endpoint to
the extension over a live channel. Keep the agent (SSH state) in the main app process. This is the
"LEADING PATH" from the investigation doc.

## Current architecture (what we're changing)

- Transport is the **modern Swift `XPC` framework**: `XPCListener` / `XPCSession` /
  `XPCReceivedMessage` / `XPCEndpoint`, with `Codable` payloads (`Message = Codable & Sendable &
  Equatable & Hashable`, `Common/Message.swift`).
- **App = server/listener.** `Agent.listener()` builds `XPCListener(service:)`; `accept()` decodes
  `AgentRequest`, dispatches via `Agent.handle()`, replies `AgentResult`. Single choke point:
  `Agent.accept()` (`AgentKit/Agent.swift:71`).
- **Extension = client.** `AgentClient` builds `XPCSession(machService: SSHadow.appServiceName)` and
  sends requests. Single choke point: `AgentClient.perform()` (`Common/AgentClient.swift:37`).
- **Progress** (`Common/XPCProgress.swift`) rides the same framework: `XPCProgressSubscriber`
  (extension) stands up its **own** anonymous `XPCListener` and passes its `XPCEndpoint` *inside* the
  request (`UploadRequest.progressEndpoint`, etc. — `Common/AgentProtocol.swift:502/535/564`);
  `XPCProgressPublisher` (app) connects to it via `XPCSession(endpoint:)` and streams
  `totalUnitCount`/`completedUnitCount`. This already proves an `XPCEndpoint` travels fine **as a
  Codable field over a live modern-XPC connection**.

## Findings (compile-probed against the SDK in this project)

These were verified with `XcodeRefreshCodeIssuesInFile` (compile-only) unless noted.

1. **The modern `XPC` framework is a closed box at the raw boundary.**
   - `XPCEndpoint` has **no** `rawValue` / accessor for its underlying `xpc_endpoint_t`.
   - `endpoint as? xpc_object_t` — *"Cast … always fails"* (unrelated types).
   - `XPCSession(connection: xpc_connection_t)` — **no such initializer**.
   - `XPCReceivedMessage(someXpcObject)` — *"no accessible initializers"*.
   - ⇒ You cannot get a transferable raw endpoint **out** of a modern `XPCListener`, and you cannot
     feed a raw `xpc_connection_t`/message **into** the modern types.

2. **What *does* compile / exist (the raw-C ↔ modern bridge, one-directional):**
   - `xpc_endpoint_create(_ conn: xpc_connection_t) -> xpc_endpoint_t` (`xpc_endpoint_t == xpc_object_t`).
   - `XPCEndpoint(_ raw: xpc_endpoint_t)` — build a modern endpoint **from** a raw one.
   - `NSXPCCoder.encodeXPCObject(_ :xpc_object_t, forKey:)` / `decodeXPCObject(ofType:forKey:)` — can
     carry a raw `xpc_object_t` **over an `NSXPCConnection`**.
   - So: a raw endpoint can be created from a raw connection, shipped over NSXPC, and wrapped back
     into a modern `XPCEndpoint` on the far side.

3. **`XPCEndpoint` cannot cross the FileProvider service channel.**
   - The FileProvider service is `NSXPCConnection`-only (`NSFileProviderServiceSource.makeListenerEndpoint()`
     → `NSXPCListenerEndpoint`; app side uses `getFileProviderServicesForItem` →
     `getFileProviderConnection` → `NSXPCConnection`).
   - `XPCEndpoint` is `Codable` but **not** `NSSecureCoding`/@objc, so it can't be an NSXPC argument.
   - Its mach send-right won't survive flat-`Data` serialization (can't persist to disk/UserDefaults,
     can't `JSONEncoder` it across processes). Confirmed conceptually + consistent with the framework
     docs ("can be passed around **in an XPC message**").

### Consequence

To transfer *any* endpoint over the FileProvider (NSXPC) channel, it must be a raw `xpc_endpoint_t`
(shipped via `NSXPCCoder.encodeXPCObject`) **or** an `NSXPCListenerEndpoint` (which *is*
`NSSecureCoding`). A raw endpoint only comes from a raw `xpc_connection_t` listener — and a raw
listener can't hand its accepted peers to the modern framework (see finding 1), so its **message
handling** would also be raw-C, and there is **no public Codable↔xpc coder** to reuse
(`XPCReceivedMessage.decode`/`XPCSession.send` are the only entry points and are not constructible
standalone).

**Bottom line:** "Keep the modern `XPCListener`, just make it anonymous and hand off its endpoint"
is **not achievable** — the modern listener's endpoint cannot reach the extension over the only
available live channel. Going anonymous forces a transport change.

> Not yet verified at runtime (RunCodeSnippet couldn't be used — it launches the full app, which
> hangs on the menu-bar/listener): whether a modern `XPCSession(endpoint: XPCEndpoint(rawEndpoint))`
> can actually **connect to and interoperate with** a raw `xpc_connection_t` anonymous listener, and
> what wire format the modern framework puts on the connection. If it *does* cleanly interop with a
> plain xpc dictionary, a "raw-C listener in app + modern XPCSession in extension" hybrid becomes
> possible — but it depends on an undocumented wire format and is not recommended.

## Options

### Option A — Anonymous `NSXPCListener` + endpoint handoff (recommended)

- App vends `NSXPCListener.anonymous()`. Its `NSXPCListenerEndpoint` is `NSSecureCoding` → transfers
  trivially over NSXPC.
- Extension implements `NSFileProviderServiceSource` (`supportedServiceSources(for:)`). App reaches it
  via `FileManager.getFileProviderServicesForItem(at:)` → `getFileProviderConnection`.
- Over that FileProvider connection the **app pushes its `NSXPCListenerEndpoint`** to the extension;
  the extension does `NSXPCConnection(listenerEndpoint:)` back to the app and runs all agent traffic
  over it. (This is the doc's leading path, realized with NSXPC instead of modern XPC.)
- Transport conversion: define one `@objc` protocol, e.g.
  `func handle(_ request: Data, reply: @escaping (Data) -> Void)`. Keep the existing `Codable`
  `AgentRequest`/`AgentResult` **as-is**, just JSON/plist-encode them to `Data` at
  `AgentClient.perform()` (encode) and `Agent.accept()` (decode) — both are single choke points.
- **Progress rework required.** `progressEndpoint: XPCEndpoint` fields must go. Replace with either:
  (a) an `NSXPCListenerEndpoint` passed as a *separate* NSXPC arg on transfer methods (mirrors today's
  design), or (b) an NSXPC callback proxy object the extension exports and the app calls back with
  progress. Touches `XPCProgress.swift`, the 3 transfer requests, `Agent.upload/download/stream`,
  `AgentClient.upload/download/stream`.
- Pros: fully supported, no private API, matches the doc. Cons: multi-file change; retires the modern
  `XPC` framework usage; progress rework is the fiddliest part.

### Option B — Reuse the FileProvider-brokered NSXPC connection directly

- Don't stand up any separate listener. Run **all** agent traffic over the single `NSXPCConnection`
  the FileProvider service already brokers (it's bidirectional: extension→app calls via
  `remoteObjectProxy`, app exports the handler object).
- Same transport conversion + progress rework as Option A, minus the listener/endpoint-handoff wiring.
- Pros: least wiring, still no launchd registration. Cons: not a distinct "anonymous listener"
  (semantically further from the literal request); connection lifecycle tied to FileProvider service
  brokering per item/domain.

### Option C — Fallback: `SMAppService` LaunchAgent

- From the investigation doc's fallback. Advertises the listener to launchd via a LaunchAgent; agent
  becomes a separate launchd-owned process (loses in-process shared state with the SwiftUI app).
  Explicitly **not** wanted. Listed only for completeness.

## Recommendation

**Option A.** It's the fully-supported realization of the investigation doc's leading path and keeps
the agent in-process. The bulk of the work is mechanical (Data-tunnel the existing Codable types at
two choke points; add the service source + endpoint push); the only genuinely new design work is
**progress reporting over NSXPC**.

## Open questions to resolve before/while implementing

1. **Progress mechanism** — separate `NSXPCListenerEndpoint` arg (mirror current design) vs. an NSXPC
   callback-proxy object? Proxy is cleaner but needs an `@objc` progress protocol + interface config.
2. **Encoding for the Data tunnel** — `PropertyListEncoder` (handles `Data`/`Date`/`mode_t` well) vs.
   `JSONEncoder`. Note `UploadRequest.file` is a `URL`, `mode: mode_t`, `Date?` fields — plist is the
   safer default.
3. **Connection lifecycle / reconnect** — today the extension's `AgentClient.cancellationHandler`
   calls `domain.manager.disconnect(...)` when the app dies. With Option A the extension must (a) pull
   the endpoint from the app on init and on reconnect, and (b) re-fetch it when the app relaunches.
   Who initiates the handoff, and when? Likely: app pushes to every domain's service on launch
   (`reconnectAllDomains` is the natural hook, `SSHadow/SSHadowApp.swift:10`) **and** the extension
   requests-on-demand if it has no endpoint yet. Need a pull path too, not just push.
4. **Sandbox caveat (from investigation doc, still unverified):** can the sandboxed extension vend a
   service source the container app can reach without extra entitlements? Prototype this first — it's
   the cheapest thing that can invalidate the whole approach.
5. **`SSHadow.appServiceName`** becomes unused for listening — decide whether to delete it or keep a
   constant for the FileProvider service name (`NSFileProviderServiceName`).
6. **Tests** — `Agent.testListener` currently returns a modern anonymous `XPCListener`
   (`AgentKit/Agent.swift:52`) and `AgentClient(session:)` takes an `XPCSession`. These will need
   NSXPC equivalents (anonymous `NSXPCListener` in-process, connected to the client) so
   `CommonTests`/`AgentKitTests`/`ExtensionKitTests` keep working.

## Files in scope (Option A)

- `AgentKit/Agent.swift` — listener creation + `accept()` → NSXPC exported object; `testListener`.
- `Common/AgentClient.swift` — session setup + `perform()` → NSXPC proxy; test init.
- `Common/AgentProtocol.swift` — drop `progressEndpoint: XPCEndpoint` fields; add progress channel type.
- `Common/XPCProgress.swift` — reimplement over NSXPC (or replace).
- `ExtensionKit/Extension.swift` — add `supportedServiceSources(for:)`; obtain/hold the connection.
- `SSHadow/SSHadowApp.swift` — build anonymous `NSXPCListener`; push endpoint to domains' services.
- New: `@objc` service protocol(s) shared in `Common` (agent handler + bootstrap/endpoint push + progress).
