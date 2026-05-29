# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SSHadow is a macOS app that mounts remote SSH/SFTP servers as native Finder volumes using the FileProvider framework. Users manage connection profiles in the app, and a FileProvider extension handles all file operations (read, write, create, rename, delete, trash) over SFTP.

### Dependencies

- **SwiftLibSSH** — SSH/SFTP client library owned by us (can make changes)
- Apple frameworks: FileProvider, SwiftData, SwiftUI, Security

## Build & Test

The project uses an Xcode project (`SSHadow.xcodeproj`) with a single scheme `SSHadow`.

### Running Tests Locally

Tests require a local SSH test server. Use the Justfile:

```sh
just unit-test    # Start test server, run unit tests
just ui-test      # Start test server, run UI tests
just test-all     # Run both
```

Or manage the server manually:

```sh
./ci_scripts/ci_pre_xcodebuild.sh   # Start test server (localhost:2248)
./ci_scripts/ci_post_xcodebuild.sh  # Stop test server
```

To run a single test:

```sh
xcodebuild test -scheme SSHadow -testPlan UnitTests \
  -destination 'platform=macOS' \
  -only-testing:AgentKitTests/SessionTests/testUpload
```

### Viewing Logs

```sh
just log  # Streams os_log output for com.kosolabs.SSHadow, formatted with jq
```

## Architecture

SSHadow spans **three OS processes** that communicate over XPC:

```
macOS FileProvider ──► Extension.appex ──► [XPC] ──► SSHadow.app ──► SwiftLibSSH ──► Remote SFTP
                       (ExtensionKit)              (AgentKit)
```

1. **SSHadow (main app)** — SwiftUI profile manager. On launch it starts an `XPCListener` (via `Agent.create()`) that the extension connects to. The app itself never touches SSH directly.
2. **Extension.appex** — A `NSFileProviderReplicatedExtension` that macOS calls for every file operation. It holds an `AgentClient` and forwards every call as an XPC request to the main app.
3. **Shared app group** `group.com.kosolabs.SSHadow` — Used for both XPC service name resolution and the shared file URL where downloaded content is written (`SSHadow.groupUrl`).

### Request lifecycle

For a file read (fetchContents):
1. macOS calls `Extension.fetchContents(for:)`
2. Extension calls `agent.download(itemId:progress:)` (AgentClient → XPC)
3. Main app's `Agent.handle(.download(_))` finds the `Session` via `SessionManager`
4. `Session.download()` writes the file to `SSHadow.groupUrl/<itemId>` via SFTP
5. The local URL is returned back through XPC to the extension, then handed to macOS

## Module Structure

### `Common` (shared by app + extension + agent)
- **`AgentProtocol.swift`** — All XPC message types: `AgentRequest`/`AgentResponse` enums and the request/response struct pairs for every operation. This is the contract between extension and agent.
- **`AgentClient.swift`** — Sends `AgentRequest` over XPC and decodes `AgentResponse`. Used by both the extension and the app UI (for connection testing).
- **`ConnectionProfile.swift`** — SwiftData `@Model` persisting SSH connection settings. Credentials (password, private key passphrase) are stored in Keychain; private key files are referenced via security-scoped bookmarks.
- **`ConnectionConfig.swift`** — Codable struct derived from `ConnectionProfile`, passed over XPC to the agent so the extension process never touches credentials directly.
- **`AppDB.swift`** — `@ModelActor` wrapping the SwiftData container for `ConnectionProfile`.
- **`FileInfo.swift`** — File metadata (id, parentId, name, size, permissions, timestamps) returned from agent to extension.

### `AgentKit` (main app only)
- **`Agent.swift`** — Decodes incoming `AgentRequest`, dispatches to the matching `func` on itself, and returns `AgentResult`. Manages one `Agent` instance per XPC session.
- **`Session.swift`** — Per-domain object holding `SSHClient`, `SFTPClient`, and `DomainDB`. All SFTP operations live here. Translates `NSFileProviderItemIdentifier` → SFTP path via `DomainDB`, then calls SwiftLibSSH.
- **`SessionManager.swift`** — Creates and caches `Session` instances keyed by domain UUID. Called by `Agent` for every request.
- **`DomainDB.swift`** — `@ModelActor` per domain. Stores `ItemModel` (itemId ↔ parent + name tree) and `FileChunk` (chunk-level download cache). Lives in the app group container.

### `ExtensionKit` (extension process only)
- **`Extension.swift`** — Implements `NSFileProviderReplicatedExtension` + `NSFileProviderPartialContentFetching`. Wraps every callback in `withProgress { }` and delegates to `AgentClient`.
- **`Enumerator.swift`** — `NSFileProviderEnumerator` that calls `agent.list(for:)`.
- **`Item.swift`** — `NSFileProviderItem` wrapping `FileInfo`.

## Key Patterns

### Item identifiers and path resolution

FileProvider identifies files by opaque `NSFileProviderItemIdentifier` strings. SSHadow maps these to SFTP paths through `DomainDB`:
- `DomainDB` stores a tree of `ItemModel(id, parentId, name)`.
- `Session.path(for: itemId)` walks the tree to the root and joins segments, then prepends the connection's configured remote path.
- When the extension encounters an identifier it hasn't seen before, `child(of:path:ifNotExists:.create)` registers it in the DB.

### Adding a new agent operation

1. Add `XxxRequest` / `XxxResponse` structs to `Common/AgentProtocol.swift`
2. Add `.xxx(XxxRequest)` / `.xxx(XxxResponse)` cases to `AgentRequest` / `AgentResponse`
3. Add `func xxx(_ request: XxxRequest) async throws -> XxxResponse` to `AgentKit/Agent.swift`
4. Add the `.xxx` case to `Agent.handle()` dispatch switch
5. Add the corresponding method to `Common/AgentClient.swift`

### Streaming / chunk cache

`Session.stream()` implements partial content fetching. It divides a file into fixed-size chunks, checks `DomainDB` for already-cached chunks, skips those, and fetches only the missing ones. `FileChunk.chunkRange(for:)` converts a byte range to chunk indices.

### Error mapping

`Session.mapError(with:_:)` converts SwiftLibSSH errors to `NSFileProviderError` at the boundary (`.noSuchFile` → `errorForNonExistentItem`, `.fileAlreadyExists` → `.filenameCollision`). Wrap all SFTP calls in this helper when adding new operations.

### Testing

- All tests use in-memory SwiftData: `ModelConfiguration(isStoredInMemoryOnly: true)`.
- `TestSandbox.swift` provides helpers to stand up a `Session` connected to the local test sshd (port 2248) and to create test files/directories.
- `Agent.createAnonymous()` is used in tests to get an agent without a named XPC service.
- The UI tests pass `-uiTesting` as a launch argument, which causes `SSHadowApp` to use an in-memory model container.

## Git Conventions

Conventional commits: `feat:`, `fix:`, `test:`, `chore:`, `refactor:`. Keep messages concise.
