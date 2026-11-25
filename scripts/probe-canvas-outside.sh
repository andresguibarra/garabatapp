#!/bin/bash
# Build the real editor in a private source copy and draw past a narrow canvas:
# clicks in the empty area, live growth, fit-to-window while typing, undo.
# Renders only the probe window to PNGs.
# Runs sandboxed with the shipping entitlements; touches no real preferences,
# history or captures (separate bundle id and container).
set -euo pipefail
cd "$(dirname "$0")/.."
probe_directory=$(mktemp -d "${TMPDIR:-/tmp}/macshot-canvas-outside-probe.XXXXXX")
cp -R macshot macshotOCRService macshot.xcodeproj "$probe_directory/"
cp scripts/probe-canvas-outside.swift "$probe_directory/macshot/main.swift"
echo "PROBE DIRECTORY: $probe_directory"
xcodebuild -project "$probe_directory/macshot.xcodeproj" -scheme macshot -configuration "${CONFIGURATION:-Release}" \
  -derivedDataPath "$probe_directory/build" -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  MACSHOT_BUNDLE_ID=com.macshot.canvas-outside-probe \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) OFFLINE' \
  build > "$probe_directory/build.log" 2>&1 || { grep -E "error:" "$probe_directory/build.log" | head -20; exit 1; }
probe_bundle="$probe_directory/build/Build/Products/${CONFIGURATION:-Release}/macshot Offline.app"
[[ -d "$probe_bundle" ]] || probe_bundle=$(ls -d "$probe_directory"/build/Build/Products/*/*.app | head -1)
codesign --force --sign - --entitlements "$probe_directory/macshot/macshot.entitlements" "$probe_bundle"
echo "PROBE APP: $probe_bundle"
open -n -W --stdout "$probe_directory/run.log" --stderr "$probe_directory/run.err" "$probe_bundle"
cat "$probe_directory/run.log"
echo "OUTPUT: $HOME/Library/Containers/com.macshot.canvas-outside-probe/Data/Library/Application Support/canvas-outside-probe"
