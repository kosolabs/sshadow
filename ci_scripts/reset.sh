#!/bin/bash
#
# Full local reset. Run this to get a machine back to a "never had SSHadow installed" 
# state for testing.

set -uo pipefail

BUNDLE=com.kosolabs.SSHadow
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister

echo "==> 1. Quit running SSHadow app + extension"
pkill -f 'SSHadow.app/Contents/MacOS/SSHadow'          2>/dev/null || true
pkill -f 'Extension.appex/Contents/MacOS/Extension'    2>/dev/null || true

echo "==> 2. Delete regenerable on-disk copies (build artifacts + Trash copy)"
rm -rf ~/Developer/sshadow/build
rm -rf ~/Library/Developer/Xcode/DerivedData/SSHadow*

echo "==> 3. Unregister every SSHadow copy from LaunchServices"
$LSREGISTER -dump \
    | awk -F'path: *' '/^[[:space:]]*path:.*SSHadow\.app/{p=$2; sub(/ \([0-9a-fx]+\)$/,"",p); print p}' \
    | sort -u \
    | while IFS= read -r app; do
        [ -n "$app" ] || continue
        echo "    unregister: $app"
        $LSREGISTER -u "$app"
    done

echo "==> 5. Remove FileProvider extension plug-in registration"
pluginkit -r "$(pluginkit -m -v -i ${BUNDLE}.Extension 2>/dev/null | awk '{print $NF}')" 2>/dev/null || true

echo "==> 6. Wipe on-disk data (containers, group data, app scripts, FileProvider state, TCC)"
tccutil reset All ${BUNDLE} 2>/dev/null || true

rm -rf ~/Library/Containers/${BUNDLE}* 2>/dev/null
rm -rf ~/Library/Group\ Containers/group.${BUNDLE}*
rm -rf ~/Library/Application\ Scripts/${BUNDLE}*
rm -rf ~/Library/Application\ Scripts/group.${BUNDLE}*
rm -rf ~/Library/Application\ Support/FileProvider/${BUNDLE}*
rm -rf ~/Library/Logs/DiagnosticReports/SSHadow*

echo "==> 7. Restart FileProvider + LaunchServices daemons so orphaned domains drop"
killall fileproviderd          2>/dev/null || true
killall lsd                    2>/dev/null || true
killall CoreServicesUIAgent    2>/dev/null || true
