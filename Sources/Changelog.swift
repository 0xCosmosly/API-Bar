import Foundation
import AppKit
import SwiftUI

// MARK: - Changelog Entry Model

public struct ChangelogEntry: Identifiable, Equatable {
    public let id: String
    public let version: String
    public let releaseDate: String
    public let title: String
    public let summary: String
    public let highlights: [String]
    public let notes: String
    public let releaseURL: URL?

    public init(
        version: String,
        releaseDate: String,
        title: String,
        summary: String,
        highlights: [String],
        notes: String,
        releaseURL: URL? = nil
    ) {
        self.id = version
        self.version = version
        self.releaseDate = releaseDate
        self.title = title
        self.summary = summary
        self.highlights = highlights
        self.notes = notes
        self.releaseURL = releaseURL ?? URL(string: "https://github.com/0xCosmosly/API-Bar/releases/tag/v\(version)")
    }

    public func isCurrent(currentVersion: String) -> Bool {
        let clean1 = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let clean2 = currentVersion.hasPrefix("v") ? String(currentVersion.dropFirst()) : currentVersion
        return clean1 == clean2
    }

    public func isNewer(currentVersion: String) -> Bool {
        AppUpdater.isVersion(version, newerThan: currentVersion)
    }

    public func isPrevious(currentVersion: String) -> Bool {
        !isCurrent(currentVersion: currentVersion) && !isNewer(currentVersion: currentVersion)
    }
}

// MARK: - Changelog Manager

@MainActor
public final class ChangelogManager: ObservableObject {
    public static let shared = ChangelogManager()

    @Published public var entries: [ChangelogEntry] = []
    @Published public var selectedVersion: String = ""
    @Published public var isFetchingRemote: Bool = false
    @Published public var remoteError: String? = nil

    public var selectedEntry: ChangelogEntry? {
        entries.first(where: { $0.version == selectedVersion }) ?? entries.first
    }

    public init() {
        self.entries = Self.builtInEntries()
        let current = AppUpdater.shared.currentVersion
        // Default selection to current installed version, or first entry
        if entries.contains(where: { $0.isCurrent(currentVersion: current) }) {
            self.selectedVersion = current
        } else {
            self.selectedVersion = entries.first?.version ?? "0.5.0"
        }
    }

    public func select(version: String) {
        if entries.contains(where: { $0.version == version }) {
            self.selectedVersion = version
        }
    }

    public func refreshFromRemote() async {
        guard !isFetchingRemote else { return }
        isFetchingRemote = true
        remoteError = nil
        defer { isFetchingRemote = false }

        guard let apiURL = URL(string: "https://api.github.com/repos/0xCosmosly/API-Bar/releases?per_page=20") else { return }
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("APIBar-Changelog/\(AppUpdater.shared.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

            var remoteEntries: [ChangelogEntry] = []
            let dateFormatter = ISO8601DateFormatter()
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .none

            for item in jsonArray {
                guard let tagName = item["tag_name"] as? String else { continue }
                let ver = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                let title = item["name"] as? String ?? "API Bar \(tagName)"
                let rawBody = item["body"] as? String ?? ""
                let htmlUrl = (item["html_url"] as? String).flatMap { URL(string: $0) }

                var dateStr = "Recent"
                if let publishedAt = item["published_at"] as? String, let d = dateFormatter.date(from: publishedAt) {
                    dateStr = displayFormatter.string(from: d)
                }

                // Extract summary
                let lines = rawBody.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let summary = lines.first(where: { !$0.hasPrefix("#") && !$0.hasPrefix("-") && !$0.hasPrefix("•") }) ?? "Release updates and improvements."

                // Extract highlights
                var highlights: [String] = []
                for line in lines {
                    if line.hasPrefix("• ") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                        let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty && highlights.count < 4 {
                            highlights.append(text)
                        }
                    }
                }

                remoteEntries.append(ChangelogEntry(
                    version: ver,
                    releaseDate: dateStr,
                    title: title,
                    summary: summary,
                    highlights: highlights,
                    notes: rawBody,
                    releaseURL: htmlUrl
                ))
            }

            if !remoteEntries.isEmpty {
                // Merge remote entries with built-in entries to keep rich summaries and offline safety
                var merged = remoteEntries
                for builtIn in Self.builtInEntries() {
                    if !merged.contains(where: { $0.version == builtIn.version }) {
                        merged.append(builtIn)
                    }
                }
                merged.sort { AppUpdater.isVersion($0.version, newerThan: $1.version) }
                self.entries = merged
            }
        } catch {
            self.remoteError = error.localizedDescription
        }
    }

    // MARK: - Built-in Offline Changelog Data

    public static func builtInEntries() -> [ChangelogEntry] {
        return [
            ChangelogEntry(
                version: "0.5.4",
                releaseDate: "November 9, 2026",
                title: "API Bar 0.5.4 — InferHub Support, Static Top-Up Baselines & Sync Stability",
                summary: "Adds native support for InferHub with browser session auth and 24h burn-rate pacing, keeps Heimdallm top-up baselines static across spend-downs, and hardens iCloud sync state transitions.",
                highlights: [
                    "InferHub (inferhub.dev) AI aggregation platform balance and burn-rate pacing",
                    "Dashboard session cookie extraction for InferHub with 24-hour token usage logs",
                    "Official InferHub spokes-and-hub menu bar mark and Retina icon mask",
                    "Heimdallm reload baseline stability: keeps cycle totals static during spend-downs and hold releases",
                    "Automatic repair of corrupted or transient top-up baselines on startup",
                    "iCloud sync state machine unsticking and multi-device push/pull hardening",
                    "Formalized explicit state machines for providers, updater, iCloud sync, and menu bar presentation"
                ],
                notes: """
## API Bar 0.5.4

This release adds native support for InferHub (inferhub.dev), keeps Heimdallm top-up baselines strictly static across spend-down cycles and credit hold releases, and hardens iCloud multi-device sync state transitions.

---

### ✨ What's New in 0.5.4

#### 1. ⚡️ InferHub (inferhub.dev) Support
• Connects to InferHub using browser session cookies or API keys.
• Extracts exact 24-hour token metrics and spend directly from the dashboard usage logs.
• Computes real-time token burn-rate pacing and remaining runway days.
• Features official InferHub vector geometry and Retina menu bar brand mark.

#### 2. 🛡️ Heimdallm Reload Baseline Stability
• Preserves your reload cycle total (`amount reloaded + previous balance`) across spend-downs below $5.00.
• Disregards small balance adjustments and hold releases (under $3.00) from falsely triggering phantom reload events.
• Automatically repairs legacy corrupted baseline totals on startup.

#### 3. ☁️ iCloud Sync & State Machine Hardening
• Resolved state machine latch preventing sync from returning to idle with active status.
• Multi-device pull and merge protects local configurations from premature overwrite.
"""
            ),
            ChangelogEntry(
                version: "0.5.3",
                releaseDate: "November 8, 2026",
                title: "API Bar 0.5.3 — OMP Sync, Heimdallm Refinements & Pacing Fixes",
                summary: "Adds bi-directional OMP iCloud sync, pauses Heimdallm by default, prevents credit hold baseline inflation, fixes Refuseless runway pacing calculations, and improves legibility.",
                highlights: [
                    "OMP (Oh-My-Prompt) iCloud Drive configuration and credential vault synchronization",
                    "Heimdallm paused by default on initial launch with Norse brand marks preserved",
                    "Authoritative Heimdallm credit totals preventing temporary hold baseline inflation",
                    "Refuseless active-day pacing calculation eliminating false multi-week runway estimates",
                    "High-contrast emerald green percentage badge legibility across macOS light mode",
                    "Smooth merged provider menu bar icon switching on rotation",
                    "App updater same-version rebuild detection allowing updates to refreshed release builds"
                ],
                notes: """
## API Bar 0.5.3

This release introduces bi-directional OMP (Oh-My-Prompt) iCloud sync, refines Heimdallm onboarding and balance accounting, fixes Refuseless pacing calculations, enhances percentage badge readability, and allows the in-app updater to install refreshed builds seamlessly.

---

### ✨ What's New in 0.5.3

#### 1. ☁️ OMP (Oh-My-Prompt) iCloud Sync
• Synchronizes model configurations and prompt settings configured in OMP (`~/.omp/agent`) across all your Macs via iCloud Drive.
• Securely synchronizes OMP credentials via your private iCloud vault with automatic rollback backup protection.

#### 2. 🛡️ Heimdallm Onboarding & Accounting Refinements
• Heimdallm is now paused by default on initial install so new users can choose when to enable it.
• Authoritative credit totals from the server take precedence over transaction ledger lines, preventing temporary credit hold releases from inflating baseline totals.
• Startup baseline repair and multi-device iCloud sync filtering prevent legacy or remote devices from corrupting your credit baseline.

#### 3. ⏱️ Refuseless Runway & Pacing Accuracy
• Fixed daily burn rate calculation to use the true active-day average rather than partial single-day spend, eliminating inaccurate multi-week runway estimates on depleted balances.

#### 4. 🎨 Legibility & Icon Rotation
• Refined green percentage badges in macOS light mode to use a high-contrast emerald green (`#108038`) exceeding WCAG AA standards.
• Fixed merged provider menu bar icon rotation to ensure brand icons toggle smoothly during manual or timed cycling.

#### 5. 🔄 App Updater Rebuild Detection
• Added support for installing updated release builds within the same version tier, ensuring users can update cleanly without waiting for a version bump.
"""
            ),
            ChangelogEntry(
                version: "0.5.2",
                releaseDate: "November 6, 2026",
                title: "API Bar 0.5.2 — Heimdallm, Scrollable Onboarding & Browser Connect-All",
                summary: "Adds native Heimdallm platform support, real-time search and scrolling in onboarding, and fixes Keychain safe-storage authorization for browser connect-all.",
                highlights: [
                    "Heimdallm (heimdallm.com) AI platform credits read directly from browser session",
                    "Native Norse H-gate vector mark and Retina brand icon template mask",
                    "Search bar and scrollable lists in onboarding so bottom providers are never cut off",
                    "Interactive Safe Storage authorization for Connect All from Brave during first-run setup",
                    "Refuseless balance display refinement prioritizing pure dollar balance"
                ],
                notes: """
## API Bar 0.5.2

This release adds Heimdallm platform credit tracking, introduces searchable and scrollable provider selection in onboarding, and ensures browser session importing connects reliably.

---

### ✨ What's New in 0.5.2

#### 1. 🆕 Heimdallm (heimdallm.com)
• Tracks AI platform credits from your signed-in browser session across heimdallm.com and staging.
• Includes native Norse H-gate vector mark and crisp Retina template mask.
• Endpoint host and path restrictions ensure read-only credit fetching.

#### 2. 🔍 Searchable & Scrollable Onboarding
• Onboarding provider selection and browser connection views now scroll smoothly, ensuring all providers are accessible regardless of screen size.
• Real-time search filter with instant clearing (×) to quickly locate any provider.

#### 3. 🔐 Reliable Browser Session Connect-All
• Connect All from Brave now pre-authenticates Keychain Safe Storage interactively once up front, preventing authorization errors during onboarding.

#### 4. 💵 Refuseless USD Prioritization
• Refuseless balances display dollar amounts cleanly and ensure matched gauge scaling.
"""
            ),
            ChangelogEntry(
                version: "0.5.1",
                releaseDate: "November 5, 2026",
                title: "API Bar 0.5.1 — Unaligned, Yeta, Pause Providers & Menu Bar Stability",
                summary: "Adds Unaligned and Yeta provider support, lets you pause providers instead of deleting them, and stops menu bar icons from being recreated so Thaw, Bartender and Ice keep your layout.",
                highlights: [
                    "Unaligned (unaligned.pw) prepaid balance from your signed-in dashboard session",
                    "Yeta (platform.yeta.ai) gateway credit, read from the console with server-reported quota conversion",
                    "Pause any provider instead of deleting it: keeps its settings, key and list position",
                    "Menu bar icons are now stable handles, so Thaw/Bartender/Ice keep their placement",
                    "Provider rows gained drag-anywhere reordering plus explicit up/down buttons",
                    "Consolidated the OpenCode and Pi iCloud sync controls into one shared component",
                    "Micro-dollar balance scaling fixed, with top-up ledgers driving the 100% baseline",
                    "Release gate now audits the tree for credentials, personal paths and personal emails"
                ],
                notes: """
## API Bar 0.5.1

This release adds two providers, introduces pausing instead of deleting, and makes API Bar behave properly with menu bar managers.

---

### ✨ What's New in 0.5.1

#### 1. 🆕 Unaligned (unaligned.pw)
• Reads your prepaid balance from the signed-in dashboard using your browser session, like the other providers.
• Balance is shown in dollars and cents; the 100% reference comes from your actual crypto top-ups in the billing ledger, so the gauge reflects what you paid in.
• No API key is stored.

#### 2. 🆕 Yeta (platform.yeta.ai)
• Tracks prepaid gateway credit from the Yeta console session.
• The quota conversion is read from the server (`quota_per_unit`) instead of being hardcoded, so it stays correct if the deployment changes.
• Ships paused: turn it on in Settings when you want to track it.

#### 3. ⏸️ Pause Providers Instead of Deleting
• Each provider has an enable switch. Pausing hides it from gauges, tabs, totals and the menu bar and stops refreshes, while keeping its settings, saved session and position in the list.
• Deleting is still available when you really want a provider gone.

#### 4. 🧭 Menu Bar Stability
• API Bar no longer removes and recreates its status items when the order changes; it reconciles them by identity.
• This keeps Thaw, Bartender and Ice anchored to the same items, so the layout you arrange sticks instead of being reset.
• Icon placement itself remains the job of your menu bar manager.

#### 5. 🧹 Consolidation
• The OpenCode and Pi iCloud sync controls now share one definition used by both onboarding and Settings.

---

### 🔧 Fixes
• Balances reported in micro-dollars are now scaled correctly, so a $4.59 balance no longer reads as millions.
• The 100% baseline is derived from top-up ledgers rather than a guessed tier, and a corrupted stored baseline is repaired automatically.
• Provider tabs no longer rebuild when a paused provider is present.

---

### 🔒 Release Hygiene
• Added an automated audit that fails the test suite if a credential, personal home path or personal email address appears in the tree.
• Google's public web-client keys are centralised in one documented file, since they identify the browser client rather than an account.
""",
            ),
            ChangelogEntry(
                version: "0.5.0",
                releaseDate: "November 3, 2026",
                title: "API Bar 0.5.0 — Token Burn Rate Pacing, OpenCode Sync & Lutheos",
                summary: "Token burn rate & runway pacing for Refuseless & Lutheos, dynamic top-up detection, OpenCode iCloud sync, and 4-tier percentage styling.",
                highlights: [
                    "Token burn rate pacing & runway calculations (e.g. 1.9M tokens/day - Runs out in 3 days)",
                    "Dynamic Refuseless top-up detection combining billing deposits with active spend telemetry",
                    "Bi-directional OpenCode & Pi iCloud configuration sync with automatic rollback backups",
                    "Native Lutheos.com balance tracking via SvelteKit devalue tree traversal",
                    "Full Settings header action buttons with zero truncation on any display scaling",
                    "Hardened self-updating with same-version refresh detection and in-app redownloads"
                ],
                notes: """
## API Bar 0.5.0

A major feature, design, and resilience update introducing native Lutheos.com & Refuseless token burn rate pacing, dynamic top-up recognition, OpenCode iCloud sync, a 4-tier traffic-light percentage color scale, matching brand accent progress bars, unified percentage calculations, rich in-app release notes, and hardened self-updating with seamless auto-relaunch.

---

### ✨ What's New in 0.5.0

#### 1. ⚡️ Token Burn Rate & Runway Pacing (Refuseless & Lutheos)
• **Real-Time Pacing Calculations**: Calculates actual consumption velocity and runway directly in the balance card (e.g. `1.9M tokens per day - Runs out in 3 days` or `500K tokens per day - Runs out in 1 day`).
• **Refuseless Token Pacing**: Analyzes output tokens, spend telemetry, and deposits to provide automatic runway estimation.
• **Lutheos Inference Runway**: Analyzes usage ledger nodes, token buckets, and credit runway to show clear depletion timelines.

#### 2. 💳 Dynamic Refuseless Top-Up Detection
• **Billing Ledger & Spend Telemetry**: Inspects the Refuseless console billing ledger dynamically. When you top up your account, API Bar combines the new deposit with your unspent balance and active spend to establish an accurate 100% baseline (e.g. $10.00 top-up + $0.33 remaining = $10.33 at 100%).
• **No Hardcoded Values**: Fully general ledger parsing across deposit tiers and payment methods.

#### 3. ☁️ Optional OpenCode & Pi iCloud Sync
• **Cross-Mac Syncing (Optional)**: Synchronizes your OpenCode (`~/.config/opencode/opencode.json`) and Pi (`~/.pi/agent`) models, provider endpoints, and credentials securely across all your Macs via iCloud Drive (unchecked by default).
• **Automatic Rollback Backups**: Generates `.bak` snapshots prior to merging remote updates, ensuring workspace settings are always protected.
• **Manifest Versioning & Watcher**: Uses low-overhead dispatch event watchers to detect local config updates in real time.

#### 4. ⚡️ Lutheos.com Native Support
• **Full Native Integration**: Automatically connect and track prepaid balances for Lutheos.com (https://lutheos.com), the private and uncensored AI inference platform.
• **SvelteKit Devalue Data Traversal**: Implemented an advanced data parser that navigates SvelteKit devalue pointer index trees, accurately decoding microdollar/cents balance, live workspace balances, credited top-up totals, and account email.
• **Automatic 100% Reference Baseline**: Detects fulfilled top-up transactions (e.g. $9.00, $10.00, $25.00 crypto top-ups) to calculate remaining balance percentages without manual configuration.

#### 5. 🎨 Settings Rhythm & Full Button Labels
• **Zero Truncation**: Applied fixed-size horizontal constraints and widened the Settings window so that action buttons like **Check for Updates…**, **Changelog…**, and **Welcome Tour…** always render in full without ellipsis.

#### 6. 📦 Re-Download & Same-Version Updates
• **Direct Redownload**: Even when already running the latest version, clicking **Check for Updates…** gives you the option to **Redownload Latest Build** for a quick and clean in-place re-installation.
• **Same-Version Build Refresh**: When updates are pushed without changing the version number, API Bar automatically detects the refreshed asset build and presents the update.
"""
            ),
            ChangelogEntry(
                version: "0.4.9",
                releaseDate: "November 2, 2026",
                title: "API Bar 0.4.9 — Paper Design System, Venice AI & Dominant Browser Discovery",
                summary: "Full Paper design system rollout, high-contrast monochrome branding, dominant browser auto-detection, and Venice AI consumption tracking.",
                highlights: [
                    "Full Paper Design System tokens across menu bar popover, badges, and onboarding",
                    "Dominant browser discovery (Brave, Chrome, Arc, Edge, Vivaldi, Chromium)",
                    "Dual permission model: Full Disk Access vs. targeted Folder Access Only",
                    "Venice AI native balance tracking (USD & DIEM with Bearer auth)",
                    "Multi-tier resilient auto-updater with GitHub REST API, Atom feed, and web redirect fallbacks"
                ],
                notes: """
## API Bar 0.4.9

A major design, provider, and compatibility update bringing the Paper design system, dominant browser discovery, Venice AI, and multi-tier resilient auto-updating.

---

### ✨ What's New in 0.4.9

#### 1. 🎨 Paper Design System & High-Contrast Branding
• **Paper Tokens**: Full Paper design tokens across menubar cards, provider selector tabs, and onboarding.
• **Monochrome Silhouette Badges**: Native provider logos styled with high-contrast, WCAG-compliant brand accent colors on clean white tiles.
• **Consistent Badges**: Neutral secondary label percentage badges with dynamic warnings (< 20%) in high-visibility red.
• **Expanded Card Layout**: 330pt layout width and clean formatting for 5-minute refresh intervals without label truncation.

#### 2. 🌐 Dominant Browser Detection & Permission Alignment
• **Auto-Detection**: Automatically identifies your system's primary browser (Brave, Google Chrome, Arc, Microsoft Edge, Vivaldi, Chromium) and connects sessions accordingly.
• **Symmetrical Permissions**: Symmetrical permission buttons for Full Disk Access and Folder Access Only with clean non-clickable states when granted.

#### 3. 🔮 Venice AI Support
• **Dual Balances**: Native tracking for Venice AI consumption currencies (USD & DIEM) with Bearer token authentication.
• **Vector Assets**: Vector icon mask bundled directly in the app package.

#### 4. 🪟 Window Management
• **Standard Shortcuts**: Settings, Onboarding, and Software Update windows reliably close with standard ⌘W and Escape.
• **macOS Menus**: Restored full native macOS File, Edit, and Window menus.

#### 5. 🔄 Multi-Tier Auto-Updating
• **Rate-Limit Resilience**: Added multi-tier fallback update checking (GitHub REST API, Atom Feed, and web redirects) to bypass unauthenticated GitHub 403 API rate limits.
• **In-Place Updates**: Seamless in-place download, extraction, replacement, and relaunch.
"""
            ),
            ChangelogEntry(
                version: "0.4.8",
                releaseDate: "November 1, 2026",
                title: "API Bar 0.4.8 — Version Identification & Refuseless Microdollar Units",
                summary: "Fixed Refuseless microdollar units parsing and ledger baseline calculation, bundle identifier cleanup, and robust build identification.",
                highlights: [
                    "Fixed Refuseless micro-dollar calculation ($23.47 / $25.00 instead of $24M)",
                    "Dynamic 100% baseline inferred from deposit ledger history",
                    "Clean bundle identifier: app.apibar.APIBar",
                    "Dynamic bundle version identification in About dialog"
                ],
                notes: """
## API Bar 0.4.8

This build fixes a versioning problem: every earlier build reported 0.4.7, so an older copy was indistinguishable from a newer one and the updater could never tell them apart.

---

### 🐛 Fixed & Improved

• **Refuseless Total**: The console reports its balance in micro-dollars (`24911322`), which was previously read as dollars and produced a `$24,947,613` total. Money is now parsed with explicit units, and the top-up ledger (amount + bonus) is used as the 100% reference. A `$25.00` account now correctly shows `$23.47 / $25.00` → 93%.
• **Version Identification**: Builds now report a real version and build number, so updates are unambiguous.
• **Bundle Identifier**: Bundle identifier is now `app.apibar.APIBar`. Existing preferences are migrated automatically on first launch; saved provider sessions are preserved.
• **About Dialog**: Reads its version dynamically from the bundle instead of a hardcoded string.
• **Built-in Updates**: Checks GitHub Releases, shows rich release notes, and installs in place.
• **Test Isolation**: The test suite runs against a throwaway directory, ensuring it never touches real credentials.
"""
            ),
            ChangelogEntry(
                version: "0.4.7",
                releaseDate: "October 31, 2026",
                title: "API Bar 0.4.7 — Initial Public Release",
                summary: "First public release of API Bar, the native macOS menu-bar companion for AI providers including Vertex AI, Fireworks, Cerebras, and Crowbot.",
                highlights: [
                    "Native tracking for Google Cloud / Vertex AI, Fireworks AI, Cerebras, and Crowbot",
                    "Refuseless & Google AI Studio live balance support",
                    "On-device Apple Foundation Model (AFM) extractor for custom APIs",
                    "Automatic 100% reference baseline calculation",
                    "100% on-device and private macOS Keychain storage"
                ],
                notes: """
## API Bar 0.4.7

First public release. A native macOS menu bar companion for tracking AI provider balances alongside CodexBar.

---

### 🚀 Supported Providers

• **Vertex AI / Google Cloud**: Active billing credits and trial grants from the Cloud Console billing GraphQL endpoint.
• **Google AI Studio**: Live Gemini credits from `GetGdpProfileAndBenefits`, with project spend-cap fallback.
• **Fireworks AI**: Prepaid inference balance, including automatic Cognito token refresh.
• **Cerebras**: Cloud session validation and fast inference platform balance.
• **Crowbot**: Chat/API credit balance with account pinning.
• **Refuseless**: Prepaid USD balance read from the console, with the top-up ledger as 100% reference.
• **Custom / Any AI API**: Add unsupported providers by name or cURL using the on-device Apple Foundation Model.

### ✨ Highlights

• **Built-in Updates**: Checks GitHub Releases, shows changelog, and installs in place.
• **Opt-In Onboarding**: A fresh install starts with no providers selected; nothing is tracked until you choose it.
• **Automatic 100% Reference**: Inferred from the latest payment, top-up, or grant, and editable per provider.
• **Accurate Units**: Explicit unit handling (cents, micro-dollars, and Google's units/nanos) prevents magnitude errors.
• **Merged or Separate Icons**: One compact gauge with a provider switcher, or separate status items.
• **100% Private**: Sessions imported locally from browser cookies and stored in the macOS Keychain. Zero telemetry.
"""
            )
        ]
    }
}

// MARK: - Changelog Window View

@MainActor
public struct ChangelogView: View {
    @ObservedObject var changelog = ChangelogManager.shared
    @ObservedObject var updater = AppUpdater.shared
    @State private var filter: ChangelogFilter = .all

    public enum ChangelogFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case current = "Current"
        case previous = "Previous"
        public var id: String { rawValue }
    }

    public init() {}

    private var filteredEntries: [ChangelogEntry] {
        let currentVer = updater.currentVersion
        switch filter {
        case .all:
            return changelog.entries
        case .current:
            return changelog.entries.filter { $0.isCurrent(currentVersion: currentVer) }
        case .previous:
            return changelog.entries.filter { $0.isPrevious(currentVersion: currentVer) }
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar: Version List
            VStack(spacing: 0) {
                // App Header in Sidebar
                HStack(spacing: 10) {
                    Image(nsImage: BrandMark.appIconImage(size: 32))
                        .resizable()
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Bar")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)

                        HStack(spacing: 4) {
                            Text("Installed:")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                            Text("v\(updater.currentVersion)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.primary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Filter Segmented Control
                Picker("", selection: $filter) {
                    ForEach(ChangelogFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                Divider()

                // Versions List
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredEntries) { entry in
                            VersionRowView(
                                entry: entry,
                                isSelected: changelog.selectedVersion == entry.version,
                                currentVersion: updater.currentVersion
                            ) {
                                changelog.select(version: entry.version)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }

                Divider()

                // Sidebar Footer: Check for Updates
                HStack {
                    Button {
                        Task {
                            await updater.checkForUpdates(manual: true)
                            await changelog.refreshFromRemote()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if updater.isChecking || changelog.isFetchingRemote {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.subheadline)
                            }
                            Text(updater.isChecking ? "Checking…" : "Check for Updates")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .disabled(updater.isChecking)

                    Spacer()

                    if let err = changelog.remoteError {
                        Image(systemName: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.orange)
                            .help(err)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            }
            .frame(width: 275)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // MARK: - Right Detail: Selected Release Notes
            VStack(spacing: 0) {
                if let entry = changelog.selectedEntry {
                    // Release Detail Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("v\(entry.version)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.primary)

                                    // Version Status Badges
                                    if entry.isCurrent(currentVersion: updater.currentVersion) {
                                        Text("Current Version")
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 3.5)
                                            .background(Color.green.opacity(0.18))
                                            .foregroundStyle(Color.green)
                                            .clipShape(Capsule())
                                    } else if entry.isNewer(currentVersion: updater.currentVersion) {
                                        Text("Update Available")
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 3.5)
                                            .background(Color.orange.opacity(0.18))
                                            .foregroundStyle(Color.orange)
                                            .clipShape(Capsule())
                                    } else {
                                        Text("Previous Version")
                                            .font(.system(size: 12, weight: .medium))
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 3.5)
                                            .background(Color.secondary.opacity(0.15))
                                            .foregroundStyle(Color.secondary)
                                            .clipShape(Capsule())
                                    }
                                }

                                Text(entry.title)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.primary)

                                Text("Released \(entry.releaseDate)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer()

                            // Action buttons
                            HStack(spacing: 8) {
                                if let url = entry.releaseURL {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label("GitHub", systemImage: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if entry.isNewer(currentVersion: updater.currentVersion) {
                                    Button("Install Update…") {
                                        updater.showUpdateWindow()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }

                        // Highlights preview box if present
                        if !entry.highlights.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Key Highlights:")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.primary)

                                ForEach(entry.highlights, id: \.self) { highlight in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("✓")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                        Text(highlight)
                                            .font(.system(size: 13.5))
                                            .foregroundStyle(Color.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .padding(20)

                    Divider()

                    // Scrollable Rich Release Notes
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            RichReleaseNotesView(markdown: entry.notes)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .padding(20)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.secondary)
                        Text("No release selected")
                            .font(.headline)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 740, minHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            // Asynchronously check remote for any freshly published GitHub releases
            await changelog.refreshFromRemote()
        }
    }
}

// MARK: - Version Row View in Sidebar

private struct VersionRowView: View {
    let entry: ChangelogEntry
    let isSelected: Bool
    let currentVersion: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("v\(entry.version)")
                        .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.9))

                    Spacer()

                    if entry.isCurrent(currentVersion: currentVersion) {
                        Text("Current")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.green.opacity(0.20))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    } else if entry.isNewer(currentVersion: currentVersion) {
                        Text("Update")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.orange.opacity(0.20))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())
                    } else {
                        Text("Previous")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(Color.secondary)
                            .clipShape(Capsule())
                    }
                }

                Text(entry.releaseDate)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)

                Text(entry.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.secondary)
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
