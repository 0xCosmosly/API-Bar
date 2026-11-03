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
                version: "0.5.0",
                releaseDate: "November 3, 2026",
                title: "API Bar 0.5.0 — Token Burn Rate Pacing, OpenCode Sync & Lutheos",
                summary: "Token burn rate & runway pacing for Refuseless & Lutheos, multi-Mac OpenCode iCloud configuration syncing, and 4-tier traffic-light percentage styling.",
                highlights: [
                    "Token burn rate pacing & runway calculations (e.g. 1.9M tokens/day - Runs out in 3 days)",
                    "Bi-directional OpenCode iCloud configuration sync with automatic rollback backups",
                    "Native Lutheos.com balance tracking via SvelteKit devalue tree traversal",
                    "4-tier traffic-light percentage color scale with matching provider brand accent bars",
                    "Hardened self-updating with detached PID exit monitoring and quarantine clearing"
                ],
                notes: """
## API Bar 0.5.0

A major feature, design, and resilience update introducing native Lutheos.com & Refuseless token burn rate pacing, OpenCode iCloud sync, a 4-tier traffic-light percentage color scale, matching brand accent progress bars, unified percentage calculations, rich in-app release notes, and hardened self-updating with seamless auto-relaunch.

---

### ✨ What's New in 0.5.0

#### 1. ⚡️ Token Burn Rate & Runway Pacing (Refuseless & Lutheos)
• **Real-Time Pacing Calculations**: Calculates actual consumption velocity and runway directly in the balance card (e.g. `1.9M tokens per day - Runs out in 3 days` or `500K tokens per day - Runs out in 1 day`).
• **Refuseless Token Pacing**: Analyzes output tokens, spend telemetry, and deposits to provide automatic runway estimation.
• **Lutheos Inference Runway**: Analyzes usage ledger nodes, token buckets, and credit runway to show clear depletion timelines.

#### 2. ☁️ OpenCode iCloud Sync
• **Cross-Mac Syncing**: Synchronizes your OpenCode configuration (`~/.config/opencode/opencode.json`) securely across all your Macs via iCloud Drive.
• **Automatic Rollback Backups**: Generates `.bak` snapshots prior to merging remote updates, ensuring workspace settings are always protected.
• **Manifest Versioning & Watcher**: Uses low-overhead dispatch event watchers to detect local config updates in real time.

#### 3. ⚡️ Lutheos.com Native Support
• **Full Native Integration**: Automatically connect and track prepaid balances for Lutheos.com (https://lutheos.com), the private and uncensored AI inference platform.
• **SvelteKit Devalue Data Traversal**: Implemented an advanced data parser that navigates SvelteKit devalue pointer index trees, accurately decoding microdollar/cents balance, live workspace balances, credited top-up totals, and account email.
• **Automatic 100% Reference Baseline**: Detects fulfilled top-up transactions (e.g. $9.00, $10.00, $25.00 crypto top-ups) to calculate remaining balance percentages without manual configuration.
• **Packaged Vector Brand Icon**: Bundled official vector icon silhouette (`lutheos-mask.png`) in app resources with Lutheos terracotta accent (`#AD4F2C`).

#### 4. 🚦 Four-Tier Traffic-Light Percentage Scale
Replaced binary percentage coloring with an intuitive, accessible 4-tier traffic-light system:
• 100% – 80% (Green): Abundant remaining balance (`Color.green`).
• 80% – 20% (Neutral Slate / Grey): Standard running consumption (`NSColor.secondaryLabelColor`).
• 20% – 10% (Amber Warning Yellow): Low balance warning (`#D97706` in light mode / `#FBBF24` in dark mode) engineered to pass WCAG AA contrast on white backgrounds.
• 10% – 0% (Alert Red): Critical balance alert (`Color.red`) signaling immediate top-up needed.

#### 5. 🎨 Provider Brand Accent Bars
• Progress bars and tab selection gauges consistently reflect each provider's distinct brand accent color:
  • Lutheos: Terracotta `#AD4F2C`
  • Refuseless: Crimson `#C8102E`
  • Fireworks AI: Amber Orange `#D46400`
  • Google Cloud / Vertex AI: Google Blue `#1A73E8`
  • Cerebras: Flame Red `#DC321E`
  • Crowbot: Forest Green `#0D733C`
  • Venice AI: Royal Purple `#7B1FA2`

#### 6. 📖 Rich In-App Release Notes Viewer
• Completely overhauled the software update window with native rich text rendering. Markdown headers (`#`, `##`, `###`), dividers (`---`), bullet lists (`•`, `-`), numbered steps (`1.`, `2.`), bold highlights (`**text**`), inline code (` `code` `), and clickable web links (`[text](url)`) are formatted with native typography instead of showing raw markdown syntax.

#### 7. 🛡️ Hardened Self-Updating & Seamless Auto-Relaunch
• **Detached Process-Exit Waiter**: Updated the in-place updater to spawn a detached background helper that monitors the dying app's PID (`kill -0 $pid`). Once the old process has fully exited, it flushes LaunchServices bundle registration (`lsregister -f`) and launches the new app.
• **Startup Grace Period**: Enhanced `Main.swift` single-instance check with an adaptive polling loop. When launched during an update, if a previous instance is still terminating, the new instance waits for it to exit rather than immediately aborting.
• **Atomic Rollback & Safe Backup**: In-place bundle replacement creates an isolated backup before moving the existing app bundle, and retains it until after process exit so dyld paging is not disrupted while shutting down.
• **Quarantine Stripping**: Automatically invokes `/usr/bin/xattr -dr com.apple.quarantine` on newly extracted bundles to ensure smooth, unblocked relaunch without macOS Gatekeeper permission prompts.

#### 8. 🔒 Security & Privacy Sanitization
• Complete audit and sanitization of test suites to use anonymous placeholders (`user@example.com`, `user@refuseless.com`, `user@lutheos.com`).
• Zero telemetry and 100% local macOS Keychain credential storage.
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
