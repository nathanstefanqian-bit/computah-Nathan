#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
case "${1:-}" in
  "") ;;
  *) print -u2 'Usage: zsh scripts/build.sh'; exit 2 ;;
esac
cd "$project_dir"
swift build
app_dir="$project_dir/outputs/Computah.app"
# Replace generated resources so files from older builds cannot survive a rebuild.
rm -rf "$app_dir/Contents/Resources"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/debug/Computah "$app_dir/Contents/MacOS/Computah"
ditto .build/debug/Computah_ComputahCore.bundle "$app_dir/Contents/Resources/Computah_ComputahCore.bundle"
ditto .build/debug/Computah_Computah.bundle "$app_dir/Contents/Resources/Computah_Computah.bundle"
python3 - "$app_dir/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'local.computah.v3',
        'CFBundleName': 'Computah',
        'CFBundleDisplayName': 'Computah',
        'CFBundleExecutable': 'Computah',
        'CFBundlePackageType': 'APPL',
        'LSUIElement': True,
        'NSHighResolutionCapable': True,
        'NSPrefersDisplaySafeAreaCompatibilityMode': False,
        'NSMicrophoneUsageDescription': 'Computah sends microphone audio to your configured speech provider while dictation is on.',
    }, output)
PY
# A stable identity keeps macOS TCC permissions valid across rebuilds.
local_identity="Computah Local Code Signing"
if [[ -n "${COMPUTAH_CODESIGN_IDENTITY:-}" ]]; then
    signing_identity="$COMPUTAH_CODESIGN_IDENTITY"
elif security find-identity -p codesigning | awk -F'"' -v name="$local_identity" '$2 == name { found=1 } END { exit !found }'; then
    signing_identity="$local_identity"
else
    signing_identity="$(security find-identity -v -p codesigning | awk -F'"' '$2 != "" {print $2; exit}')"
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    print -u2 "Warning: using ad-hoc signing. Accessibility permission will not survive a rebuild."
    print -u2 "Run zsh scripts/setup-local-codesign.sh once to create a stable local identity."
fi
codesign --force --sign "$signing_identity" --timestamp=none "$app_dir"
codesign --verify --strict "$app_dir"
print "Built $app_dir"
print "Signed with $signing_identity"
