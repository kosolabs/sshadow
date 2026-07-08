#!/bin/bash
# Full local reset for SSHadow development.
#
# clean.sh wipes on-disk DATA (containers, keychain prompts, caches). This script
# additionally clears the two live REGISTRIES that clean.sh + a reboot don't touch:
#   - LaunchServices  (source of FileProvider error -2004 "A newer version is already installed")
#   - fileproviderd's domain registry (orphaned SSHadow domains)
#
# Archive/distribution copies of SSHadow.app under ~/Downloads and
# ~/Library/Developer/Xcode/Archives are UNREGISTERED but left on disk.

set -uo pipefail  # not -e: unregistering an already-absent path is a harmless failure

BUNDLE=com.kosolabs.SSHadow
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister

echo "==> 1. Quit running SSHadow app + extension"
pkill -f 'SSHadow.app/Contents/MacOS/SSHadow'          2>/dev/null || true
pkill -f 'Extension.appex/Contents/MacOS/Extension'    2>/dev/null || true

echo "==> 2. Delete regenerable on-disk copies (build artifacts + Trash copy)"
rm -rf ~/Developer/sshadow/build
rm -rf ~/Library/Developer/Xcode/DerivedData/SSHadow*

echo "==> 3. Unregister every SSHadow copy from LaunchServices"
# Fixes FileProvider error -2004: LaunchServices remembers every copy of the
# bundle it has ever seen (Downloads, archives, old build products); if any
# has a higher CFBundleVersion than your dev build, the extension refuses to
# register its domain. (`lsregister -kill` was removed in recent macOS, so we
# unregister each path individually — this also drops phantom records for the
# copies deleted in step 2. Files on disk are left intact.)
"$LSREGISTER" -dump \
    | awk -F'path: *' '/^[[:space:]]*path:.*SSHadow\.app/{p=$2; sub(/ \([0-9a-fx]+\)$/,"",p); print p}' \
    | sort -u \
    | while IFS= read -r app; do
        [ -n "$app" ] || continue
        echo "    unregister: $app"
        "$LSREGISTER" -u "$app"
    done

echo "==> 5. Remove FileProvider extension plug-in registration"
pluginkit -r "$(pluginkit -m -v -i ${BUNDLE}.Extension 2>/dev/null | awk '{print $NF}')" 2>/dev/null || true

echo "==> 6. Wipe on-disk data (containers, group data, app scripts, FileProvider state, TCC)"
tccutil reset All ${BUNDLE} 2>/dev/null || true
# NOTE: ~/Library/Containers/<id> holds a containermanagerd-protected metadata
# plist. Deleting it needs Full Disk Access for this terminal (or drag it to
# Trash in Finder). The app's actual data lives in the Group Container below,
# which removes cleanly, so this failing is usually fine.
rm -rf ~/Library/Containers/${BUNDLE}* 2>/dev/null || \
    echo "    (containers are SIP-protected; grant Full Disk Access or remove via Finder)"
rm -rf ~/Library/Group\ Containers/group.${BUNDLE}*
rm -rf ~/Library/Application\ Scripts/${BUNDLE}*
rm -rf ~/Library/Application\ Scripts/group.${BUNDLE}*
rm -rf ~/Library/Application\ Support/FileProvider/${BUNDLE}*
rm -rf ~/Library/Logs/DiagnosticReports/SSHadow*

echo "==> 7. Restart FileProvider + LaunchServices daemons so orphaned domains drop"
killall fileproviderd          2>/dev/null || true
killall lsd                    2>/dev/null || true
killall CoreServicesUIAgent    2>/dev/null || true

echo ""
echo "Reset complete. Verify:"
echo "  fileproviderctl dump | grep -i sshadow      # expect nothing"
echo "  $LSREGISTER -dump | grep -i 'SSHadow.app'   # expect only paths you chose to keep"
