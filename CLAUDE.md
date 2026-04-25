# CLAUDE.md

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

### Viewing Logs

```sh
just log  # Streams os_log output for com.kosolabs.SSHadow, formatted with jq
```

## Git Conventions

Conventional commits: `feat:`, `fix:`, `test:`, `chore:`, `refactor:`. Keep messages concise.
