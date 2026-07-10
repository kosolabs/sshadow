# SSHadow — XPC Listener "Operation not permitted" Investigation

## Problem
SSHadow fails to start its XPC listener when launched **outside Xcode's debugger**
(Finder double-click, `open`, or notarized build). It works **only** under Xcode. Error:

```
Failed to create XPC listener: Unable to activate listener: Connection init failed
at listener activation with error 1 - Operation not permitted
```

This is **not a regression** — the app worked from Finder in the past, but that was before
the XPC service existed. The user is now building a notarized beta for the first time and
discovered the app has *only ever worked under the debugger*.

## Architecture context
- App vends an XPC mach-service listener via `XPCListener(service: SSHadow.appServiceName)`
  in `AgentKit/Agent.swift:47`.
- `SSHadow.appServiceName = "group.com.kosolabs.SSHadow.App"` (`Common/SSHadow.swift:11`),
  where `appGroup = "group.com.kosolabs.SSHadow"` — **iOS-style `group.` prefix, NOT
  Team-ID-prefixed**.
- Extension is the XPC **client** (`Common/AgentClient.swift`, `machService: SSHadow.appServiceName`);
  main app is the **server/listener**. The agent runs **in the main app process** and shares
  live state with the SwiftUI UI (`Transfers`, `ConnectionCoordinator`, SwiftData container).
- Team ID: `A5S59GAS97`. Hardened Runtime is ON (`flags=0x10000(runtime)`).
- Listener creation failure is now `logger.fatal(...)` (crashes) in `SSHadow/SSHadowApp.swift:41`
  (recent commit 2f20ec2).

## What was ruled out
1. **Entitlements are correct** — app-sandbox + `com.apple.security.application-groups`
   (`group.com.kosolabs.SSHadow`) present and correctly signed. Not the cause.
2. **`sandboxd` logs NO denial** — the sandbox profile permits it. It is **launchd** that
   refuses the check-in.
3. Debug-only red herring - in the **Debug** build, the log also shows a `kernel` 
   Library Validation failure rejecting a **loose ad-hoc-signed** copy of SwiftLibSSH at 
   `Build/Products/Debug/PackageFrameworks/…` (Team ID: none), because the Debug binary's 
   `LC_RPATH` lists that build dir *before* `@executable_path/../Frameworks` (which holds a 
   correctly Team-signed copy). This is **Debug-only** - the notarized build's launch log 
   shows **no Library Validation line** — only the launchd EPERM. This rules the LV failure 
   out as the cause.
4. **Team-ID-prefixed app group + service name (TESTED 2026-07-09, DOES NOT WORK).** Added
   `A5S59GAS97.com.kosolabs.SSHadow` to `com.apple.security.application-groups` in both
   entitlements and set `appServiceName = "A5S59GAS97.com.kosolabs.SSHadow.Agent"` (a child of
   the Team-ID group). Launched non-debugger — **still `EPERM`**:
   ```
   [com.apple.xpc:connection] activating connection: mach=true listener=true peer=false
       name=A5S59GAS97.com.kosolabs.SSHadow.Agent
   [com.apple.xpc:connection] listener failed to activate: xpc_error=[1: Operation not permitted]
   ```
   This falsifies the "app-group carve-out is keyed on the Team-ID form" theory: the service
   name was a proper child of a Team-ID-prefixed app group and launchd still refused the
   listener check-in. The app-group carve-out evidently does **not** extend to vending a
   dynamic mach-service *listener* from a sandboxed GUI app, regardless of the prefix form.

## Root-cause finding (from unified log, launched via `open`)
Key log line:
```
launchd: failed activation: name = group.com.kosolabs.SSHadow.App,
         requestor = SSHadow[pid], error = 1: Operation not permitted
```
Leading theory: **a sandboxed GUI app cannot dynamically register a mach-service *listener*
that isn't advertised to launchd.** Apple docs for `XPC_CONNECTION_MACH_SERVICE_LISTENER`
(verbatim): *"Only pass this flag for services in the process's `launchd.plist`. You may not
use this flag to dynamically add services to the Mach bootstrap namespace."* The debugger
relaxes this check, masking the problem.

Sources:
- https://developer.apple.com/documentation/xpc/xpc_connection_mach_service_listener
- https://developer.apple.com/documentation/xpc/xpc_connection_create_mach_service(_:_:_:)
  (name "must exist in a Mach bootstrap that is accessible to the process and be advertised
  in a `launchd.plist`")

## Open questions / next steps (unresolved)
1. **LEADING PATH: anonymous listener + endpoint handoff over the FileProvider service channel
   (keeps agent in-process, no LaunchAgent).** The EPERM is specifically the launchd *name
   registration* step. An **anonymous** `XPCListener` (`XPCListener(targetQueue:...)`, the
   no-service initializer already used by `Agent.testListener` at `AgentKit/Agent.swift:66`)
   creates an in-process receive right and never registers a name in launchd's bootstrap
   namespace — so it should sidestep the EPERM entirely. The remaining problem is handing the
   listener's `XPCEndpoint` to the extension over a **live** channel (it cannot be persisted to
   disk/`UserDefaults` — the endpoint carries a mach send right that only survives transfer over
   an active XPC connection, despite `XPCEndpoint` being `Codable`). FileProvider supplies such a
   channel with no launchd advertisement and no portal registration:
   - The **extension** vends a small bootstrap service via `NSFileProviderServiceSource`
     (`supportedServiceSources`).
   - The **app** connects to it through `FileManager.getFileProviderServicesForItem(at:)` — the
     framework brokers this connection.
   - Over that connection the app **pushes its anonymous listener's `XPCEndpoint`** to the
     extension; the extension does `XPCSession(endpoint:)` back to the app and runs all real
     agent traffic over it. SSH stays in the main app process; current architecture preserved.

   Unverified caveat worth prototyping first: whether the sandbox lets the extension vend a
   service source the container app can reach without additional entitlements.
2. **FALLBACK: advertisement is truly required → register via `SMAppService` (LaunchAgent).**
   If the anonymous-listener path fails, the surviving theory says the listener must be
   advertised to launchd. This means the agent becomes a **separate launchd-owned process**, no
   longer sharing memory with the SwiftUI app (would coordinate via XPC/app group). User
   explicitly wants to avoid this because the agent currently runs in-app. (A LaunchAgent
   pointing at the main app executable can keep one process but is fragile with a
   MenuBarExtra/LSUIElement app — not recommended.)

## How to reproduce/observe (non-debugger launch)
```sh
APP=$(find ~/Library/Developer/Xcode/DerivedData/SSHadow-*/Build/Products -maxdepth 2 -name SSHadow.app | head -1)
log stream --predicate 'process == "SSHadow" OR sender == "SSHadow" OR subsystem == "com.kosolabs.SSHadow" OR eventMessage CONTAINS[c] "SSHadow"' &
LOGPID=$!
open -W "$APP"
sleep 1
kill "$LOGPID"
```
