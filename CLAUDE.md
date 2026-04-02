# CLAUDE.md

## Project Overview

SSHadow is a macOS app that mounts remote SSH/SFTP servers as native Finder volumes using the FileProvider framework. Users manage connection profiles in the app, and a FileProvider extension handles all file operations (read, write, create, rename, delete, trash) over SFTP.

## Architecture

### Targets

| Target | Type | Purpose |
|--------|------|---------|
| **SSHadow** | macOS App | SwiftUI interface for managing connection profiles |
| **Provider** | App Extension | FileProvider extension entry point (`main.swift`) |
| **Extension** | Framework | Core FileProvider logic — SFTP operations, session management, enumeration |
| **Common** | Framework | Shared models and services used by both the app and extension |
| **CommonTests** | Test Bundle | Unit tests for Common (uses UnitTests.xctestplan) |
| **ExtensionTests** | Test Bundle | Integration tests for Extension (uses UnitTests.xctestplan) |
| **UITests** | UI Test Bundle | UI automation tests (uses UITests.xctestplan) |

### Key Files

- `Extension/Extension.swift` — `NSFileProviderReplicatedExtension` implementation
- `Extension/SessionManager.swift` — Actor managing SSH/SFTP connection lifecycle
- `Extension/Session.swift` — SFTP file operations on an active connection
- `Extension/Enumerator.swift` — Directory enumeration for FileProvider
- `Extension/Item.swift` — `NSFileProviderItem` conformance for remote files
- `Common/ConnectionConfig.swift` — SSH connection parameters (host, port, auth)
- `Common/ConnectionProfile.swift` — SwiftData model for saved connections
- `Common/SSHItem.swift` — SwiftData model for tracking items
- `Common/SSHItemStore.swift` — Actor-based SwiftData store for items
- `Common/Keychain.swift` — Secure credential storage via app group keychain
- `Common/Logger.swift` — Unified `os.Logger` wrapper with subsystem `com.kosolabs.SSHadow`

### Dependencies

- **SwiftLibSSH** — SSH/SFTP client library owned by us (can make changes)
- Apple frameworks: FileProvider, SwiftData, SwiftUI, Security

## Code Conventions

- **Naming**: PascalCase for types, camelCase for properties/methods
- **Concurrency**: Swift `async`/`await` throughout; avoid Combine. `SessionManager` is an `actor`. Types conform to `Sendable` where needed.
- **Progress tracking**: FileProvider operations return `Progress` objects. Use `Speedometer` for throughput measurement.
- **Logging**: Use the project's `Logger` wrapper (in `Common/Logger.swift`), not `print`. Categories follow the pattern `"DomainName:ComponentName"`.
- **Error handling**: Map SSH errors to `NSFileProviderError` codes (`.notAuthenticated`, `.serverUnreachable`, etc.). Use `StackTrace.capture()` for error context.
- **SwiftUI state**: `@State private var` for local state, `@Query` for SwiftData, `@Environment` for injected dependencies. Custom `Binding` helpers for derived state.
- **Item identifiers**: `NSFileProviderItemIdentifier` extended with helpers for parent/child path relationships.
- **App group**: `group.com.kosolabs.SSHadow` — shared between app and extension for keychain and SwiftData.
- **Testing**: Swift Testing framework (`import Testing`, `@Test`). Never use XCTest for new unit tests.

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

### Test Plans

- `UnitTests.xctestplan` — CommonTests + ExtensionTests
- `UITests.xctestplan` — UITests

### CI

GitHub Actions runs on PRs to `main` (`.github/workflows/ci.yml`). Code signing is disabled for CI builds.

### Viewing Logs

```sh
just log  # Streams os_log output for com.kosolabs.SSHadow, formatted with jq
```

## Git Conventions

Conventional commits: `feat:`, `fix:`, `test:`, `chore:`, `refactor:`. Keep messages concise.
