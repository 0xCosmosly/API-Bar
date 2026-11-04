# 🤖 Agent Guide & Architecture Specification

> **For AI Coding Agents & Automated Planners** (Gemini, Claude Code, Cursor, Codex, Antigravity, Aider).  
> This file outlines architectural invariants, build/test protocols, security constraints, and extension patterns for **API Bar**.

---

## 🏛️ System Architecture Overview

API Bar is a native, lightweight macOS menu-bar companion written in **Swift 6** targeting **macOS 13.0+ (Ventura, Sonoma, Sequoia)**. It monitors prepaid credit balances, promotional grants, token burn velocity, and runway timelines across AI inference platforms.

### Core Data Flow

```
[Browser SQLite Cookies] ──> [BraveSessionImporter / Credentials.swift]
                                      │
                                      ▼ (AES Decryption via OS Keychain)
                            [SessionHTTP Client]
                                      │
                     ┌────────────────┴────────────────┐
                     ▼                                 ▼
         [Official Provider APIs]           [On-Device AFM Extractor]
         (Google, Fireworks, Cerebras,     (cURL / JSON heuristics)
          Refuseless, Lutheos, Venice)
                     │                                 │
                     └────────────────┬────────────────┘
                                      ▼
                             [Reading Validation]
                                      │
                                      ▼
                        [APIBarApp State & Balances]
                                      │
       ┌──────────────────────────────┼──────────────────────────────┐
       ▼                              ▼                              ▼
[NSStatusItem Gauges]        [Popover Detail Cards]        [iCloud Sync Engine]
(Percentage / Currency)     (Runway, burn pacing, tabs)   (Vault + opencode.json)
```

---

## 🔒 Crucial Invariants (Must Never Be Broken)

### 1. Zero Secrets in Version Control
- **Never** commit real API keys, bearer tokens, passwords, personal email addresses, or unredacted JSON diagnostic dumps.
- Unit and integration tests must strictly use anonymized fixtures (`user@example.com`, `user@refuseless.com`, `user@lutheos.com`).
- Personal machine paths (e.g. `/Users/<name>/...`) must never be hardcoded into source code. Always use `FileManager.default.homeDirectoryForCurrentUser`.

### 2. Non-Interactive Keychain Access
- Background refresh tasks must **never** trigger macOS interactive Keychain password dialogs.
- Always wrap Keychain loads in `KeychainVault.access(interactive: false)` and enforce `LAContext.interactionNotAllowed = true`.
- If a session cookie is expired, revoked, or requires re-authentication, mark `providerStatus[id] = "Connect in Settings"` rather than stalling on a system prompt.

### 3. Stable Status Item Handles (Thaw / Bartender / Ice Compatibility)
- Do **not** remove and recreate `NSStatusItem` instances on routine balance refreshes or sort order changes.
- In `configureStatusItems()`, check if `currentIdentities == identities && !items.isEmpty`. If identical, update button titles in-place.
- Recreating `NSStatusItem`s destroys accessibility window anchors (`AXUIElement`) and causes third-party menu bar managers (Thaw, Bartender, Ice) to enter infinite layout loops.

### 4. Baseline Ingestion Directionality (Never Downgrade)
- In `App.swift` (`apply(_ r: Reading)`), existing verified baselines (e.g. \$9.00 or \$10.33) must **never** be overwritten by smaller inferred references (e.g. \$5.00).
- Only increase or preserve `balances[i].baseline`:
  ```swift
  if balances[i].baseline <= 0 || ref >= balances[i].baseline {
      balances[i].baseline = max(ref, r.remaining)
  } else {
      balances[i].baseline = max(balances[i].baseline, r.remaining)
  }
  ```

### 5. Safe iCloud Push/Pull Sequence
- Always write safety backups (`.bak` and timestamped JSON) prior to applying remote iCloud changes.
- Pull logic must guard against decoding failures and preserve existing local keys.

---

## 🛠️ Build, Test & Release Protocols

### Test Suite (`./check.command`)
Run the sandboxed test suite:
```sh
./check.command
```
- Sets `APIBAR_DATA_DIR` to a scratch directory so production `balances.json` is never touched.
- Executes all 18 check suites: SQLite decryption, Keychain policy restoration, SvelteKit devalue parsing, token burn rate calculations, semver comparisons, AFM extraction, and UI event loops.
- **Rule**: All 18 check suites must pass with exit code `0` before any commit.

### Compilation & Local Installation (`./build.command`)
Compile a Universal (arm64 + x86_64) release binary and install to `/Applications/API Bar.app`:
```sh
./build.command
```
- Compiles with Swift 6 in release mode (`-O -whole-module-optimization`).
- Packages `APIBar-app.zip`.
- Applies ad-hoc code signature (`codesign -f -s -`).

### Git Commit Guidelines
- Always commit as author:  
  `0xCosmosly <254995568+0xCosmosly@users.noreply.github.com>`
- Format commit titles using Conventional Commits (`fix:`, `feat:`, `docs:`, `refactor:`).
- For release asset updates within the same release cycle, use `--clobber`:
  ```sh
  gh release upload v0.5.0 /tmp/APIBar-app.zip --clobber
  ```

---

## 🧩 Adding a New Provider (4-Step Recipe)

To introduce a new native provider to API Bar:

1. **Model Definition (`Sources/Balance.swift`)**:
   Add the provider's default entry to `Balance.initial` with its unique ID, display name, default endpoint, and brand accent color:
   ```swift
   Balance(id: "newprovider", name: "New Provider", baseline: 0, remaining: 0, updated: .distantPast, account: "")
   ```

2. **Client Implementation (`Sources/SessionHTTP.swift`)**:
   Create a struct conforming to `BalanceProvider`:
   ```swift
   struct NewProvider: BalanceProvider {
       let providerID = "newprovider"
       let http: SessionHTTP
       let account: String
       func fetchBalance() async throws -> Reading { ... }
   }
   ```

3. **Brand Artwork (`Resources/`)**:
   Add a 1x/2x/3x template mask `Resources/newprovider-mask.png` for menu bar and tile rendering. Register the color in `BrandMark.brandAccent(for:)` in `Sources/BrandMark.swift`.

4. **Unit Tests (`Tests/Checks.swift`)**:
   Add a fixture test asserting valid balance parsing, baseline calculation, and error recovery.

---

## 📂 Source Code Map

| File | Purpose |
| :--- | :--- |
| `Sources/Main.swift` | Single-instance coordinator and application bootstrap. |
| `Sources/App.swift` | `APIBarApp` coordinator: status items, menu bar popovers, sorting, and balance stores. |
| `Sources/Credentials.swift` | Browser discovery (Brave, Chrome, Arc, Edge), Keychain master key extraction, and SQLite cookie decryption. |
| `Sources/SessionHTTP.swift` | Authenticated HTTP client with cookie isolation and specialized provider fetchers (Lutheos, Refuseless, etc.). |
| `Sources/GoogleProvider.swift` | Google Cloud & Vertex AI GraphQL billing service connector. |
| `Sources/CrowbotProvider.swift` | Crowbot microdollar balance client. |
| `Sources/AFMProviderExtractor.swift` | On-device heuristic balance extractor for custom user-added cURL/JSON endpoints. |
| `Sources/Provider.swift` | `BalanceProvider` protocol and consumption models. |
| `Sources/ProviderTabsView.swift` | SwiftUI drop-down popover view, provider switcher tabs, and runway gauges. |
| `Sources/MenuUI.swift` | Settings pane, onboarding view, Paper Design System buttons, and icon tiles. |
| `Sources/BrandMark.swift` | Custom vector icon rendering, brand accent palettes, and app icons. |
| `Sources/ICloudSync.swift` | Cross-device iCloud Drive synchronization for settings, providers, and OpenCode configurations. |
| `Sources/Changelog.swift` | Offline-first multi-version changelog viewer with Markdown formatting. |
| `Sources/AppUpdater.swift` | In-app self-updater with semver parsing, release notes, and detached-process relaunch helper. |
