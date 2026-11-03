#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
if [ -z "${SDK:-}" ]; then
    if [ -d "$DEVELOPER_DIR/SDKs/MacOSX26.5.sdk" ]; then
        SDK="$DEVELOPER_DIR/SDKs/MacOSX26.5.sdk"
    else
        SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
        if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
            SDK="$DEVELOPER_DIR/SDKs/MacOSX.sdk"
        fi
    fi
fi
mkdir -p .cache/modules
"$DEVELOPER_DIR/usr/bin/swiftc" -sdk "$SDK" -target "$(uname -m)-apple-macosx13.0" -parse-as-library -module-cache-path "$PWD/.cache/modules" Sources/BrandMark.swift Tools/MakeIcon.swift -o .cache/MakeIcon
.cache/MakeIcon .cache/AppIcon.iconset Resources/AppIcon.icns
"$DEVELOPER_DIR/usr/bin/swiftc" -sdk "$SDK" -target "$(uname -m)-apple-macosx13.0" -parse-as-library -module-cache-path "$PWD/.cache/modules" Sources/*.swift -o .cache/APIBar
STAGING="$(mktemp -d /tmp/apibar-build.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/API Bar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Write bytes into a fresh bundle to avoid inherited Finder/provider metadata.
python3 - "$PWD" "$APP" <<'PYBUILD'
import sys
from pathlib import Path
root, app = map(Path,sys.argv[1:])
for src,dst in [(".cache/APIBar","MacOS/APIBar"),("Resources/Info.plist","Info.plist"),("Resources/AppIcon.icns","Resources/APIBarConverge.icns"),("Resources/AppIcon.icns","Resources/AppIcon.icns"),("Resources/crowbot-mask.png","Resources/crowbot-mask.png"),("Resources/fireworks-mask.png","Resources/fireworks-mask.png"),("Resources/vertex-mask.png","Resources/vertex-mask.png"),("Resources/aistudio-mask.png","Resources/aistudio-mask.png"),("Resources/cerebras-mask.png","Resources/cerebras-mask.png"),("Resources/refuseless-mask.png","Resources/refuseless-mask.png")]:
    (app/"Contents"/dst).write_bytes((root/src).read_bytes())
(app/"Contents/MacOS/APIBar").chmod(0o755)
PYBUILD
codesign --force --sign - --identifier app.apibar.APIBar "$APP"
codesign --verify --strict "$APP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$PWD/APIBar-app.zip"
ditto --norsrc --noextattr "$APP" "$PWD/API Bar.app"
ditto --norsrc --noextattr "$APP" "/Applications/API Bar.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/API Bar.app" 2>/dev/null || true
touch "/Applications/API Bar.app"
echo "Built API Bar.app and installed to /Applications/API Bar.app"
