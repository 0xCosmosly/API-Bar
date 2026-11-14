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
mkdir -p .cache/checks
# Tests must never touch the real credential vault, balance file, or Keychain.
TEST_STATE="$(mktemp -d /tmp/apibar-check.XXXXXX)"
export APIBAR_VAULT_DIR="$TEST_STATE/vault"
export APIBAR_DATA_DIR="$TEST_STATE/data"
export APIBAR_ICLOUD_DIR="$TEST_STATE/icloud"
export APIBAR_OPENCODE_FILE="$TEST_STATE/opencode.json"
export APIBAR_PI_DIR="$TEST_STATE/pi_agent"
export APIBAR_OMP_DIR="$TEST_STATE/omp_agent"
mkdir -p "$APIBAR_VAULT_DIR" "$APIBAR_DATA_DIR" "$APIBAR_ICLOUD_DIR" "$APIBAR_PI_DIR" "$APIBAR_OMP_DIR"
swiftc -sdk "$SDK" -target "arm64-apple-macosx13.0" -parse-as-library -module-cache-path "$PWD/.cache/modules" Sources/BrandMark.swift Sources/Balance.swift Sources/Provider.swift Sources/Credentials.swift Sources/GoogleWebClientKeys.swift Sources/SessionHTTP.swift Sources/UnalignedProvider.swift Sources/YetaProvider.swift Sources/HeimdallmProvider.swift Sources/InferHubProvider.swift Sources/GoogleProvider.swift Sources/CrowbotProvider.swift Sources/AppUpdater.swift Sources/Changelog.swift Sources/CodexBarPacing.swift Sources/SyncChangeLog.swift Sources/AFMSummarizer.swift Tests/Checks.swift -o .cache/checks/APIBarChecks
.cache/checks/APIBarChecks
plutil -lint Resources/Info.plist
UI_SOURCES=()
for source in Sources/*.swift; do
    if [[ "$source" != "Sources/Main.swift" ]]; then UI_SOURCES+=("$source"); fi
done
swiftc -sdk "$SDK" -target "arm64-apple-macosx13.0" -parse-as-library -module-cache-path "$PWD/.cache/modules" "${UI_SOURCES[@]}" Tests/UIInteractionChecks.swift -o .cache/checks/UIInteractionChecks
.cache/checks/UIInteractionChecks --diagnostics "$PWD/.cache/checks/interface.json"
rm -rf "$TEST_STATE"
