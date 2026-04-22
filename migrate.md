# Migrate SSH/SFTP to Agent XPC Service

## Context

SSH connections are currently established and maintained directly in the FileProvider Extension (`Extension/SessionManager.swift` -> `Extension/Session.swift` -> SwiftLibSSH). The goal is to move all SSH/SFTP operations into the Agent XPC service so the Extension becomes a thin proxy that translates FileProvider callbacks into XPC calls.

**Before:**
```
FileProvider -> Extension -> SessionManager -> Session -> SSHClient/SFTPClient
                                                       -> SSHadowDB
```

**After:**
```
FileProvider -> Extension -> AgentClient -(XPC)-> Agent -> SessionManager -> Session -> SSHClient/SFTPClient
                                                                                     -> SSHadowDB
```

## Key Design Decisions

- **SSHadowDB moves to the Agent** — Session uses it for path resolution before every SFTP op. Keeping it in the Extension would add per-operation XPC round-trips.
- **File transfers use shared filesystem** — Extension passes temp file paths over XPC. Agent reads/writes directly. Both processes share the app group (`group.com.kosolabs.SSHadow`). Agent already has the app group entitlement.
- **DTOs encoded as JSON Data** — Complex types (`AgentFileAttributes`, `AgentItem`) are `Message`-conforming structs in Common, serialized as `Data` for XPC transport.
- **AgentListenerDelegate shares a single Agent instance** — All XPC connections share one Agent, which holds a dictionary of `SessionManager` instances keyed by domain ID.
- **Error mapping happens in the Agent** — `SSHError` -> `NSFileProviderError` conversion moves to the Agent so errors arrive at the Extension ready to return to FileProvider.

## Phase 1: DTO Types

Create serializable types in Common that can cross the XPC boundary.

### 1a. `Common/AgentFileAttributes.swift` (new)

```swift
public struct AgentFileAttributes: Message {
    public enum FileType: String, Message {
        case regular, directory, symlink, special, unknown
    }
    public let name: String?
    public let type: FileType
    public let size: UInt64
    public let permissions: UInt32
    public let accessTime: Date?
    public let createTime: Date?
    public let modifyTime: Date?
}
```

Mirror the fields from `SFTPAttributes` that `Item.swift` uses (lines 43-65): `size`, `accessTime`, `modifyTime`, `createTime`, `type`, `permissions`.

### 1b. `Common/AgentItem.swift` (new)

```swift
public struct AgentItem: Message {
    public let identifier: String        // NSFileProviderItemIdentifier.rawValue
    public let parentIdentifier: String
    public let filename: String
    public let attributes: AgentFileAttributes
}
```

### 1c. `Common/AgentConnectionInfo.swift` (new)

```swift
public struct AgentConnectionInfo: Message {
    public let domainId: String
    public let domainDisplayName: String
    public let config: ConnectionConfig
}
```

### 1d. `AgentKit/SFTPAttributes+Agent.swift` (new)

Conversion extension from `SFTPAttributes` -> `AgentFileAttributes`. Lives in AgentKit because it imports SwiftLibSSH.

### Verify

Unit tests for DTO encoding/decoding round-trips in CommonTests.

---

## Phase 2: Expand AgentProtocol & AgentClient

Replace the `sayHello` placeholder with the real SFTP operation interface.

### 2a. `Common/AgentProtocol.swift` — rewrite

All methods use the `@objc` callback pattern. Complex types are passed as `Data` (JSON-encoded). Connection identity is `domainId: String`.

```
Connection lifecycle:
  connect(connectionInfo: Data, reply: (NSError?) -> Void)
  disconnect(domainId: String, reply: () -> Void)

Metadata:
  item(domainId:, itemId:, reply: (Data?, NSError?) -> Void)          // -> AgentItem
  exists(domainId:, itemId:, reply: (Bool) -> Void)

Mutations:
  setAttributes(domainId:, itemId:, permissions:, accessTime:, modifyTime:, reply:)
  move(domainId:, itemId:, toParentId:, name:, createParentIfMissing:, reply:)
  removeFile(domainId:, itemId:, reply:)
  createDirectory(domainId:, itemId:, mode:, succeedIfExists:, reply:)
  removeDirectory(domainId:, itemId:, reply:)

File transfer (paths on shared filesystem):
  downloadFile(domainId:, itemId:, toLocalPath:, reply:)
  uploadFile(domainId:, itemId:, fromLocalPath:, mode:, reply:)
  streamFile(domainId:, itemId:, rangeLocation:, rangeLength:, alignment:, fileSize:, toLocalPath:, reply:)

Directory enumeration:
  enumerateDirectory(domainId:, itemId:, reply: (Data?, NSError?) -> Void)  // -> [AgentItem]

Composite operations (reduce XPC round-trips for multi-step FileProvider ops):
  createItem(domainId:, parentId:, filename:, isDirectory:, contentPath:, mode:, permissions:, accessTime:, modifyTime:, reply:)  // -> AgentItem
  modifyItem(domainId:, itemId:, newParentId:, newFilename:, contentPath:, mode:, permissions:, accessTime:, modifyTime:, createParentIfMissing:, reply:)  // -> AgentItem
```

### 2b. `Common/AgentClient.swift` — add async wrappers

One `async throws` method per protocol method, following the existing `withCheckedThrowingContinuation` + `proxy(errorHandler:)` pattern. Methods returning DTOs decode from `Data`.

### Verify

Build succeeds. Existing `sayHello` test still passes (remove it last).

---

## Phase 3: Move Session & SessionManager to AgentKit

### 3a. Move files

- `Extension/SessionManager.swift` -> `AgentKit/SessionManager.swift`
- `Extension/Session.swift` -> `AgentKit/Session.swift`

Adjust imports: add `import SwiftLibSSH`, remove `import FileProvider` where possible (Session uses `NSFileProviderItemIdentifier` and `NSFileProviderDomain` — these come from FileProvider framework, so AgentKit will need to link FileProvider).

### 3b. Remove `agent: AgentClient` from Session

Session no longer needs an XPC client — it *is* the server side now.

### 3c. Implement Agent protocol methods

`AgentKit/Agent.swift` — implement all protocol methods:
- Holds `private var sessions: [String: SessionManager]` (keyed by domain ID)
- Each method: look up SessionManager -> `getSession()` -> call Session method -> encode result -> reply
- Error mapping (`SSHError` -> `NSFileProviderError`) happens here at the reply boundary
- Use `Task { }` to bridge from `@objc` callbacks to async/await

### 3d. Make AgentListenerDelegate share a single Agent

```swift
public class AgentListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let agent = Agent()
    // shouldAcceptNewConnection sets connection.exportedObject = agent
}
```

### Verify

AgentKit builds. Write integration tests in AgentKitTests that test Agent through XPC using `TestData.getAgentClient()` with a real SSH connection to the test server.

---

## Phase 4: Migrate Extension to use AgentClient

### 4a. `Extension/Extension.swift` — rewrite to use AgentClient

- `init(domain:)`: Create `AgentClient`, call `agent.connect(info:)` instead of creating a local SessionManager
- `invalidate()`: Call `agent.disconnect(domainId:)`
- All FileProvider methods (`item(for:)`, `fetchContents`, `createItem`, `modifyItem`, `deleteItem`): Call corresponding `AgentClient` methods instead of `manager.withSession()`

### 4b. `Extension/Item.swift` — construct from AgentItem

Change `init` to accept `AgentItem` instead of `SFTPAttributes`. Map `AgentFileAttributes.FileType` to `UTType`.

### 4c. `Extension/Enumerator.swift` — use AgentClient

Replace `manager.getSession()` -> `session.enumerateItems()` with `agent.enumerateDirectory()`. Construct `Item` objects from returned `[AgentItem]`.

### 4d. Progress tracking

For downloads/uploads, the Extension still owns `Progress` and `Speedometer`. Since the Agent writes to shared files, the Extension can check file size after completion. Real-time progress can be deferred to a future enhancement (Apple's `NSProgress` XPC reporting mechanism).

### Verify

Build succeeds. Extension no longer imports SwiftLibSSH.

---

## Phase 5: Cleanup

- Remove `SessionManager.swift` and `Session.swift` from Extension target (they now live in AgentKit)
- Remove SwiftLibSSH dependency from Extension framework target
- Remove `sayHello` from AgentProtocol, AgentClient, Agent, and tests
- Move SessionTests from ExtensionTests to AgentKitTests (they test Session directly)
- Update ExtensionTests to test Extension -> AgentClient flow
- Update `TestData` if needed for new Agent integration tests

### Verify

- `just unit-test` — all tests pass
- `just ui-test` — UI tests pass
- Manual test: mount a volume in Finder, browse files, upload/download

---

## Critical Files

| File | Action |
|------|--------|
| `Common/AgentProtocol.swift` | Rewrite with full SFTP interface |
| `Common/AgentClient.swift` | Add async wrappers for all new methods |
| `Common/AgentFileAttributes.swift` | New DTO |
| `Common/AgentItem.swift` | New DTO |
| `Common/AgentConnectionInfo.swift` | New DTO |
| `AgentKit/Agent.swift` | Implement all protocol methods, manage SessionManagers |
| `AgentKit/AgentListenerDelegate.swift` | Share single Agent instance |
| `AgentKit/SessionManager.swift` | Move from Extension (minor adjustments) |
| `AgentKit/Session.swift` | Move from Extension (remove agent property) |
| `AgentKit/SFTPAttributes+Agent.swift` | New conversion extension |
| `Extension/Extension.swift` | Rewrite to call AgentClient |
| `Extension/Item.swift` | Construct from AgentItem |
| `Extension/Enumerator.swift` | Use AgentClient |
