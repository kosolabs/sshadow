# SSHadow

A macOS menu bar app that mounts remote directories over SSH in Finder.

SSHadow uses the File Provider framework, so each connection shows up as a location in Finder's sidebar. Files are listed and downloaded on demand rather than synced up front, and edits are uploaded back to the server.

## Features

- Multiple connections, each mapping a remote path on an SSH server to a Finder location.
- Password and private key (with optional passphrase) authentication.
- Credentials stored in the macOS Keychain.
- Automatic reconnects with exponential backoff when a connection drops.
- Connections can be paused and resumed without removing them from Finder.
- Browse remote tree without pulling all of it.
- Stream file contents with read-ahead caching for sequential reads.
- Downloaded files can be removed to free up local space while staying listed in Finder.
- Edits are uploaded back to the server.
- Periodic polling picks up remote changes so Finder stays in sync with the server.
- Ignore files (`.sshadowignore` by default, configurable per connection) keep matching items from being uploaded or downloaded.
- Fast uploads and downloads, with a transfer progress summary in the menu bar.
- An event log of every remote change, with search and filters.

## Architecture

- Built on our own libssh wrapper, [SwiftLibSSH](https://github.com/kosolabs/swift-lib-ssh/) for much faster uploads and downloads than other pure Swift SSH implementations.
- Runs inside the macOS App Sandbox, with the following entitlements:
  - Outgoing network access to reach SSH servers.
  - Shared app group between the app and its File Provider extension
  - Security-scoped bookmarks for accessing user-selected files (like private keys) outside the sandbox.

## Requirements

- macOS 15.0 or later
- An SSH server with SFTP enabled

## License

See [LICENSE](LICENSE).
