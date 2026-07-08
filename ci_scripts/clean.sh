#!/bin/bash
set -euo pipefail

# Reset TCC permissions (network, file access, etc.) so macOS re-prompts on next launch
tccutil reset All com.kosolabs.SSHadow

# Remove app sandbox containers (SwiftData database, preferences, caches)
rm -rf ~/Library/Containers/com.kosolabs.SSHadow*

# Remove app group shared data (shared state between app and extension)
rm -rf ~/Library/Group\ Containers/group.com.kosolabs.SSHadow*

# Remove Application Scripts directories
rm -rf ~/Library/Application\ Scripts/com.kosolabs.SSHadow*
rm -rf ~/Library/Application\ Scripts/group.com.kosolabs.SSHadow*

# Remove FileProvider extension state and caches
rm -rf ~/Library/Application\ Support/FileProvider/com.kosolabs.SSHadow*

# Remove Xcode derived data (build artifacts)
rm -rf ~/Library/Developer/Xcode/DerivedData/SSHadow*

# Remove Xcode archives
rm -rf ~/Library/Developer/Xcode/Archives/*/SSHadow*

# Remove crash and diagnostic reports
rm -rf ~/Library/Logs/DiagnosticReports/SSHadow*
