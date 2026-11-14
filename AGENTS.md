# 🤖 Agent Guide & Architecture Specification

> **For AI Coding Agents & Automated Planners** (Gemini, Claude Code, Cursor, Codex, Antigravity, Aider, OpenCode, Pi).  
> This file outlines architectural invariants, build/test protocols, security constraints, and extension patterns for **Harness Sync** (repository: `0xCosmosly/Harness-Sync`).

---

## 🏛️ System Architecture Overview

**Harness Sync** is a native, high-performance macOS menu bar companion written in **Swift 6** targeting native **Apple Silicon (arm64)** on **macOS 13.0+ (Ventura, Sonoma, Sequoia)**.

The system serves two tightly integrated functions:
1. **AI Balance & Runway Tracker**: Continuously monitors prepaid credit balances, promotional grants, token burn velocity, and runway timelines across AI inference platforms.
2. **Coding Agent Harness Synchronizer**: Safely synchronizes configurations, models, prompts, and credential vaults for AI coding agents (**OpenCode**, **Pi**, and **OMP** / Oh My OpenCode) across multiple Macs via private Apple iCloud Drive.

### Core Subsystems & Data Flow

```
[Browser SQLite Cookies] ──> [BrowserSessionImporter / Credentials.swift]
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
                         [HarnessSyncApp State & Balances]
                                      │
       ┌──────────────────────────────┼──────────────────────────────┐
       ▼                              ▼                              ▼
[NSStatusItem Gauges]        [Popover Detail Cards]        [iCloud Sync Engine]
(Percentage / Currency)     (Runway, burn pacing, tabs)   (OpenCode + Pi + OMP)
                                                                     │
                                                                     ▼
                                                          [SyncChangeLog & AFM]
                                                       (Diffs & Smart Summaries)
```

---

## 🔒 Crucial Invariants (Must Never Be Broken)

### 1. Zero Secrets in Version Control
- **Never** commit real API keys, bearer tokens, passwords, personal email addresses (`@proton.me`, `@gmail.com`, `@icloud.com`), or unredacted JSON diagnostic dumps.
- Unit and integration tests must strictly use anonymized fixtures (`user@example.com`, `user@refuseless.com`, `user@lutheos.com`).
- Personal machine paths (e.g. `/Users/<name>/...`) must never be hardcoded into source code. Always use `FileManager.default.homeDirectoryForCurrentUser`.
- Verified automatically by `secretAuditChecks()` in `check.command` across all source and test files.

### 2. Non-Interactive Keychain Access
- Background refresh tasks must **never** trigger macOS interactive Keychain password dialogs.
- Always wrap Keychain loads in `KeychainVault.access(interactive: false)` and enforce `LAContext.interactionNotAllowed = true`.
- If a session cookie is expired, revoked, or requires re-authentication, mark `providerStatus[id] = "Connect in Settings"` rather than stalling on a system prompt.

### 3. Stable Status Item Handles (Thaw / Bartender / Ice Compatibility)
- Do **not** remove and recreate `NSStatusItem` instances on routine balance refreshes or sort order changes.
- In `configureStatusItems()`, check if `currentIdentities == identities && !items.isEmpty`. If identical, update button titles in-place.
- Recreating `NSStatusItem`s destroys accessibility window anchors (`AXUIElement`) and causes third-party menu bar managers (Thaw, Bartender, Ice) to enter infinite layout loops.

### 4. Baseline Ingestion Directionality & Verified Cycle References
- In `App.swift` (`apply(_ r: Reading)`), verified references (`ref > 0`) from providers with full deposit ledgers (such as Refuseless) represent the true top-up cycle baseline (`latestDeposit + unspentCarryoverBeforeDeposit`) and directly set `balances[i].baseline = max(ref, r.remaining)`.
- When a new top-up occurs (e.g. topping up $10 after spending down a previous $25 cycle), the cycle baseline must correctly reset to the new cycle total (e.g. $10.33) rather than remaining locked to lifetime cumulative deposits ($35.00).
- For providers subject to tier inference fallbacks (such as Lutheos), guard against overwriting a verified baseline with a smaller inferred tier:
  ```swift
  if balances[i].baseline <= 0 || ref >= balances[i].baseline {
      balances[i].baseline = max(ref, r.remaining)
  } else {
      balances[i].baseline = max(balances[i].baseline, r.remaining)
  }
  ```
- Missing references (`ref == nil` or `ref <= 0`) must never downgrade or reset the baseline; they simply preserve `balances[i].baseline`.

### 5. Safe iCloud Push/Pull Sequence & Safety Rollbacks
- Always write safety backups (`.bak` and timestamped JSON) prior to applying remote iCloud changes to coding agent directories.
- Pull logic must guard against decoding failures and preserve existing local keys.
- Volatile view state (active tab selection, current timestamp, device name) must not alter the configuration fingerprint `configFingerprint`.

### 6. Intelligent Sync Change Categorization (Major vs. Routine)
- In `SyncChangeLog.swift`, changes are strictly classified as **Major** or **Routine**:
  - **Major Changes**: Provider additions/removals, model additions/updates in OMP `models.yml` or Pi `models.json` (e.g. `Mistral added with 3 models`), baseline changes > $0.50, and harness toggle changes.
  - **Routine Changes**: Minor fractional balance shifts (< $0.50), session token refreshes (`.dat` vault files), and timestamp heartbeats.
- Routine changes are classified as minor (`isMajor == false`) and silenced from the headline sync summary so the user always sees the last meaningful configuration change.

### 7. On-Device Foundation Model (AFM) Contract
- `AFMSummarizer.swift` wraps Apple Foundation Models on macOS 26+.
- **Hard Timeout Ceiling**: 2,500 milliseconds (`Duration.milliseconds(2500)`).
- **Deterministic Baseline**: The deterministic text produced by `SyncChangeLog` is the ultimate source of truth. AFM only re-phrases it. Any timeout, unavailability, or empty model response must immediately fall back to the deterministic string without throwing or crashing.

### 8. Strict Layout Geometry in Status Popover
- In `Sources/MenuUI.swift`, the sync info row in `lastSyncSection` adheres to a strict two-line layout:
  - Top line: `"Last synced from [Device]"`
  - Bottom line: `"[Change description]"`
  - Timestamp: Formatted as `"[HH:mm a] ([x hours ago])"` and appended to the absolute time display.
- Enforced with `.frame(height: 32, alignment: .topLeading)` to prevent jumping or menu popover resizing during background sync cycles.

### 9. Apple Silicon Only
- Native **Apple Silicon (arm64)** execution only. Target: `arm64-apple-macosx13.0`.
- Universal / x86_64 binaries are deprecated and not generated.

---

## 🛠️ Build, Test & Release Protocols

### Sandboxed Test Suite (`./check.command`)
Run the verification suite:
```sh
./check.command
```
- Sets `APIBAR_DATA_DIR` and `APIBAR_ICLOUD_DIR` to isolated temporary directories so real user configs and Keychain items are never touched.
- Executes all 18 check suites:
  1. SQLite decryption & Keychain policy restoration.
  2. SvelteKit devalue traversal & credit parsing.
  3. Token burn velocity & runway calculations (`CodexBarPacing`).
  4. Precise YAML and JSON config diffing (`SyncChangeLog`).
  5. AFM summarizer contract, fallback safety, and timeout bounds.
  6. Secret audit over 40+ files (zero secrets, zero personal emails/paths).
  7. GitHub Releases self-updater and semver parsing.
  8. Headless AppKit/SwiftUI component interaction checks.
- **Rule**: All 18 check suites must pass with exit code `0` before any commit.

### Apple Silicon Build & Packaging (`./build.command`)
Compile the native release binary and assemble the application bundle:
```sh
./build.command
```
- Compiles with Swift 6 in release mode (`-O -whole-module-optimization`).
- Generates `APIBar-app.zip` and installs to `/Applications/API Bar.app`.
- Applies ad-hoc code signature (`codesign -f -s -`).

### Git Commit Guidelines
- Commit author: `0xCosmosly <254995568+0xCosmosly@users.noreply.github.com>`.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- Repository URL: `https://github.com/0xCosmosly/Harness-Sync.git`.

---

## 🧩 Adding a New Provider (4-Step Recipe)

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

| File | Subsystem & Purpose |
| :--- | :--- |
| `Sources/Main.swift` | Single-instance coordinator and NSApplication bootstrap. |
| `Sources/App.swift` | `APIBarApp` coordinator: status items, popovers, sorting, and balance store. |
| `Sources/Credentials.swift` | Browser discovery (Brave, Chrome, Arc, Edge, Vivaldi), Keychain master key extraction, SQLite cookie decryption. |
| `Sources/SessionHTTP.swift` | Authenticated HTTP client with cookie isolation and specialized provider fetchers. |
| `Sources/GoogleProvider.swift` | Google Cloud & Vertex AI GraphQL billing service connector. |
| `Sources/CrowbotProvider.swift` | Crowbot microdollar balance client. |
| `Sources/AFMProviderExtractor.swift` | On-device heuristic balance extractor for custom user-added cURL/JSON endpoints. |
| `Sources/AFMSummarizer.swift` | On-device Apple Foundation Model sync summarizer with 2500ms timeout ceiling and fallback. |
| `Sources/Provider.swift` | `BalanceProvider` protocol and reading models. |
| `Sources/ProviderTabsView.swift` | SwiftUI drop-down popover view, provider switcher tabs, and runway gauges. |
| `Sources/MenuUI.swift` | Settings pane, onboarding view, sync status row, Paper Design System buttons. |
| `Sources/BrandMark.swift` | Custom vector icon rendering, brand accent palettes, and app icons. |
| `Sources/ICloudSync.swift` | Cross-device iCloud Drive synchronization for coding harnesses (OpenCode, Pi, OMP) and settings. |
| `Sources/SyncChangeLog.swift` | Precise YAML/JSON diffing, provider change summaries, and relative time formatting. |
| `Sources/CodexBarPacing.swift` | Spend-based runway calculations and token burn velocity derivation for CodexBar. |
| `Sources/Changelog.swift` | Offline-first multi-version changelog viewer with Markdown formatting. |
| `Sources/AppUpdater.swift` | In-app self-updater targeting `0xCosmosly/Harness-Sync` GitHub Releases. |

---

## 🔍 Search & Keyword Optimization

Key concepts and integrations for indexers and AI agents searching this codebase:
- **macOS Menu Bar App**: Native AppKit + SwiftUI status items with non-interactive Keychain security.
- **AI Inference Balances**: Google Vertex AI, Google AI Studio, Fireworks AI, Cerebras, Venice AI, Refuseless, Lutheos, Unaligned, Crowbot, Yeta, Heimdallm, InferHub, OpenRouter, Groq, Together, DeepSeek, Ollama, vLLM.
- **Token Burn Velocity & Runway**: Time-to-exhaustion pacing calculations (`tokens/day`, `days remaining`).
- **Coding Agent Harnesses**: Configuration sync for OpenCode (`opencode.json`), Pi coding agent (`models.json`), OMP / Oh My OpenCode (`models.yml`, `config.yml`).
- **Zero API Key Extraction**: Local SQLite cookie extraction with AES-128-CBC macOS Keychain master key decryption.
- **Scriptable iOS Widget**: JavaScript widget template syncing desktop gauges to iPhone Home Screen.
