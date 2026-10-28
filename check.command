#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK="$DEVELOPER_DIR/SDKs/MacOSX26.5.sdk"
mkdir -p .cache/checks
swiftc -sdk "$SDK" -parse-as-library -module-cache-path "$PWD/.cache/modules" Sources/Balance.swift Sources/Provider.swift Sources/Credentials.swift Sources/SessionHTTP.swift Sources/GoogleProvider.swift Sources/CrowbotProvider.swift Tests/Checks.swift -o .cache/checks/APIBarChecks
.cache/checks/APIBarChecks
plutil -lint Resources/Info.plist
UI_SOURCES=()
for source in Sources/*.swift; do
    if [[ "$source" != "Sources/Main.swift" ]]; then UI_SOURCES+=("$source"); fi
done
swiftc -sdk "$SDK" -parse-as-library -module-cache-path "$PWD/.cache/modules" "${UI_SOURCES[@]}" Tests/UIInteractionChecks.swift -o .cache/checks/UIInteractionChecks
.cache/checks/UIInteractionChecks --diagnostics "$PWD/.cache/checks/interface.json"
