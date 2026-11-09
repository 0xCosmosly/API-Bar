import AppKit
import ServiceManagement
import SwiftUI

enum ProviderSortMode: String, CaseIterable, Codable {
    case manual = "manual"
    case balance = "balance"
    case recentlyUsed = "recent"

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .balance: return "Total Amount"
        case .recentlyUsed: return "Recently Used"
        }
    }
}

final class ClosableWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            self.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        self.performClose(nil)
    }
}

public enum MenuBarPresentationMode: Equatable, Sendable, CustomStringConvertible {
    case individual(activeProviderIDs: [String])
    case mergedOverview(activeCount: Int, aggregatePercent: Double?)
    case mergedProvider(providerID: String)
    case empty

    public var description: String {
        switch self {
        case .individual(let ids): return "individual(\(ids.joined(separator: ",")))"
        case .mergedOverview(let count, let pct): return "mergedOverview(count: \(count), percent: \(pct.map { String(format: "%.1f%%", $0) } ?? "nil"))"
        case .mergedProvider(let id): return "mergedProvider(\(id))"
        case .empty: return "empty"
        }
    }

    public var telemetryRepresentation: [String: Any] {
        switch self {
        case .individual(let ids):
            return ["mode": "individual", "providerIDs": ids]
        case .mergedOverview(let count, let pct):
            var dict: [String: Any] = ["mode": "mergedOverview", "activeCount": count]
            if let pct { dict["aggregatePercent"] = pct }
            return dict
        case .mergedProvider(let id):
            return ["mode": "mergedProvider", "providerID": id]
        case .empty:
            return ["mode": "empty"]
        }
    }
}

public enum BrowserAccessState: Equatable, Sendable {
    case notInstalled(browser: String)
    case blocked(browser: String, hint: String)
    case authorized(accessKind: String, profile: String, profilesCount: Int)

    public var telemetryRepresentation: [String: Any] {
        switch self {
        case .notInstalled(let browser):
            return ["state": "notInstalled", "browser": browser]
        case .blocked(let browser, let hint):
            return ["state": "blocked", "browser": browser, "hint": hint]
        case .authorized(let kind, let profile, let count):
            return [
                "state": "authorized",
                "kind": kind,
                "profile": profile,
                "profilesCount": count
            ]
        }
    }
}

@MainActor
final class APIBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    @Published public private(set) var providerConnectionStates: [String: ProviderConnectionState] = [:]

    public var menuBarPresentationMode: MenuBarPresentationMode {
        if activeBalances.isEmpty {
            return .empty
        }
        if mergeIcons {
            if mergedProvider == "overview" {
                let usdRemaining = activeBalances.reduce(0.0) { $0 + $1.remaining }
                let usdBaseline = activeBalances.reduce(0.0) { $0 + $1.baseline }
                let pct = usdBaseline > 0 ? max(0, usdRemaining / usdBaseline * 100) : nil
                return .mergedOverview(activeCount: activeBalances.count, aggregatePercent: pct)
            } else if let b = selectedMergedBalance {
                return .mergedProvider(providerID: b.id)
            } else {
                return .mergedOverview(activeCount: activeBalances.count, aggregatePercent: nil)
            }
        } else {
            return .individual(activeProviderIDs: activeBalances.map(\.id))
        }
    }

    public var browserAccessState: BrowserAccessState {
        if !isBraveInstalled {
            return .notInstalled(browser: browserName)
        }
        if isBraveAccessBlocked {
            return .blocked(browser: browserName, hint: "Grant Full Disk Access or choose your \(browserName) profile folder.")
        }
        let profile = selectedBraveProfileID
        return .authorized(accessKind: braveAccessKind.rawValue, profile: profile, profilesCount: availableBraveProfiles.count)
    }

    public func setConnectionState(for id: String, to state: ProviderConnectionState) {
        providerConnectionStates[id] = state
        providerStatus[id] = state.displayStatus
    }

    public func handleFetchError(id: String, error: Error, fallbackName: String) {
        let provName: String
        switch id {
        case "fireworks": provName = "app.fireworks.ai"
        case "vertex": provName = "Google Cloud"
        case "aistudio": provName = "Google AI Studio"
        case "cerebras": provName = "Cerebras Cloud"
        case "refuseless": provName = "Refuseless"
        case "lutheos": provName = "Lutheos"
        case "crowbot": provName = "Crowbot"
        case "unaligned": provName = "Unaligned"
        case "yeta": provName = "Yeta"
        case "heimdallm": provName = "Heimdallm"
        case "inferhub": provName = "InferHub"
        default: provName = fallbackName
        }
        let wasConnected = isConnected(id) || balances.first(where: { $0.id == id })?.live == true || hasStoredCredential(id) || (balances.first(where: { $0.id == id })?.dynamicAuthHeader?.isEmpty == false)
        if error.localizedDescription.contains("expired") || error.localizedDescription.contains("sign in") {
            if wasConnected {
                setConnectionState(for: id, to: .disconnected(reason: .sessionExpired, message: "Session expired · sign in to \(provName) in Brave"))
            } else {
                setConnectionState(for: id, to: .disconnected(reason: .unconfigured, message: "Connect in Settings to refresh"))
            }
        } else if wasConnected {
            setConnectionState(for: id, to: .degraded(error: error.localizedDescription, canRetry: true))
        } else {
            setConnectionState(for: id, to: .disconnected(reason: .unconfigured, message: "Connect in Settings to refresh"))
        }
    }
    // Providers are opt-in. A first launch starts with an empty list and the
    // onboarding provider step records only the choices the user makes.
    @Published var balances: [Balance] = []
    @Published var mergeIcons: Bool = {
        if UserDefaults.standard.object(forKey: "MergeProviderIcons") != nil {
            return UserDefaults.standard.bool(forKey: "MergeProviderIcons")
        }
        return true
    }()
    @Published var mergedProvider = UserDefaults.standard.string(forKey: "MergedProvider") ?? "overview"
    @Published var sortMode: ProviderSortMode = {
        if let saved = UserDefaults.standard.string(forKey: "ProviderSortMode"),
           let mode = ProviderSortMode(rawValue: saved) {
            return mode
        }
        return .balance
    }()

    var iCloudSyncEnabled: Bool {
        get { ICloudSync.shared.isEnabled }
        set { ICloudSync.shared.setEnabled(newValue) }
    }
    var isOpenCodeSyncEnabled: Bool {
        get { ICloudSync.shared.isOpenCodeSyncEnabled }
        set { ICloudSync.shared.setOpenCodeSyncEnabled(newValue) }
    }
    var isOpenCodeCredentialsSyncEnabled: Bool {
        get { ICloudSync.shared.isOpenCodeCredentialsSyncEnabled }
        set { ICloudSync.shared.setOpenCodeCredentialsSyncEnabled(newValue) }
    }
    var isPiSyncEnabled: Bool {
        get { ICloudSync.shared.isPiSyncEnabled }
        set { ICloudSync.shared.setPiSyncEnabled(newValue) }
    }
    var isPiCredentialsSyncEnabled: Bool {
        get { ICloudSync.shared.isPiCredentialsSyncEnabled }
        set { ICloudSync.shared.setPiCredentialsSyncEnabled(newValue) }
    }
    var isOmpSyncEnabled: Bool {
        get { ICloudSync.shared.isOmpSyncEnabled }
        set { ICloudSync.shared.setOmpSyncEnabled(newValue) }
    }
    var isOmpCredentialsSyncEnabled: Bool {
        get { ICloudSync.shared.isOmpCredentialsSyncEnabled }
        set { ICloudSync.shared.setOmpCredentialsSyncEnabled(newValue) }
    }
    var iCloudStatus: String {
        ICloudSync.shared.statusBadge
    }
    var iCloudStatusMessage: String {
        ICloudSync.shared.statusMessage
    }
    func setICloudSyncEnabled(_ enabled: Bool) {
        ICloudSync.shared.setEnabled(enabled)
    }
    func setOpenCodeSyncEnabled(_ enabled: Bool) {
        ICloudSync.shared.setOpenCodeSyncEnabled(enabled)
    }
    func setOpenCodeCredentialsSyncEnabled(_ enabled: Bool) {
        ICloudSync.shared.setOpenCodeCredentialsSyncEnabled(enabled)
    }
    func setPiSyncEnabled(_ enabled: Bool) {
        ICloudSync.shared.setPiSyncEnabled(enabled)
    }
    func setPiCredentialsSyncEnabled(_ enabled: Bool) {
        ICloudSync.shared.setPiCredentialsSyncEnabled(enabled)
    }
    func setOmpSyncEnabled(_ enabled: Bool) {
        ICloudSync.shared.setOmpSyncEnabled(enabled)
    }
    func setOmpCredentialsSyncEnabled(_ enabled: Bool) {
        ICloudSync.shared.setOmpCredentialsSyncEnabled(enabled)
    }
    func syncICloudNow() {
        Task { await ICloudSync.shared.syncNow() }
    }

    func setSortMode(_ mode: ProviderSortMode) {
        guard sortMode != mode else { return }
        sortMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "ProviderSortMode")
        UserDefaults.standard.set(Date(), forKey: "APIBarSettingsModified")
        applySorting()
        ICloudSync.shared.schedulePush()
    }

    @objc func setSortManual() { setSortMode(.manual) }
    @objc func setSortBalance() { setSortMode(.balance) }
    @objc func setSortRecent() { setSortMode(.recentlyUsed) }

    func applySorting() {
        switch sortMode {
        case .manual:
            break
        case .balance:
            balances.sort {
                if $0.remaining != $1.remaining { return $0.remaining > $1.remaining }
                return $0.name < $1.name
            }
        case .recentlyUsed:
            balances.sort {
                if $0.updated != $1.updated { return $0.updated > $1.updated }
                return $0.name < $1.name
            }
        }
        save()
        reapplyOrder()
    }

    func moveProvider(from sourceIndex: Int, to destinationIndex: Int) {
        guard balances.indices.contains(sourceIndex), balances.indices.contains(destinationIndex), sourceIndex != destinationIndex else { return }
        sortMode = .manual
        UserDefaults.standard.set(ProviderSortMode.manual.rawValue, forKey: "ProviderSortMode")
        let item = balances.remove(at: sourceIndex)
        balances.insert(item, at: destinationIndex)
        save()
        reapplyOrder()
    }

    func moveProviderUp(index: Int) {
        guard index > 0 else { return }
        moveProvider(from: index, to: index - 1)
    }

    func moveProviderDown(index: Int) {
        guard index < balances.count - 1 else { return }
        moveProvider(from: index, to: index + 1)
    }

    func reapplyOrder() {
        // Always reconcile; configureStatusItems() keeps existing items untouched
        // when the set of providers is unchanged, so a reorder never disturbs the
        // handles a menu bar manager is tracking.
        configureStatusItems()
        mergedMenuView?.updateProviders(activeBalances)
        updateTitles()
        writeDiagnostics()
    }
    /// Providers the user has not disabled. Disabled providers keep their saved
    /// configuration and credentials but are skipped everywhere a balance is
    /// shown, summed, or refreshed.
    var activeBalances: [Balance] { balances.filter(\.isEnabled) }
    var selectedMergedBalance: Balance? {
        activeBalances.first(where: { $0.id == mergedProvider })
            ?? activeBalances.first
            ?? balances.first(where: { $0.id == mergedProvider })
            ?? balances.first
    }

    func removeProvider(id: String) {
        guard let index = balances.firstIndex(where: { $0.id == id }) else { return }
        balances.remove(at: index)
        clients.removeValue(forKey: id)
        KeychainVault.clear(id)
        providerConnectionStates.removeValue(forKey: id)
        providerStatus.removeValue(forKey: id)
        inFlight.remove(id)
        var removed = UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? []
        if !removed.contains(id) {
            removed.append(id)
            UserDefaults.standard.set(removed, forKey: "RemovedProviders")
        }

        if mergedProvider == id {
            mergedProvider = "overview"
            UserDefaults.standard.set("overview", forKey: "MergedProvider")
        }
        save()
        reapplyOrder()
    }

    func addProvider(_ provider: Balance) {
        guard !balances.contains(where: { $0.id == provider.id }) else { return }
        var p = provider
        p.disabled = false
        balances.append(p)
        var removed = UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? []
        removed.removeAll(where: { $0 == provider.id })
        UserDefaults.standard.set(removed, forKey: "RemovedProviders")

        let connected = isConnected(provider.id)
        setConnectionState(for: provider.id, to: connected ? .connected(detail: "Connected · refreshes every 5 min", lastChecked: nil) : .disconnected(reason: .unconfigured, message: "Connect in Settings"))
        save()
        reapplyOrder()
    }

    func addCustomProvider(_ draft: AFMDetectedDraft) {
        var safeID = draft.id.lowercased().filter { $0.isLetter || $0.isNumber }
        if safeID.isEmpty { safeID = "custom" }
        var finalID = safeID
        var counter = 2
        while balances.contains(where: { $0.id == finalID }) {
            finalID = "\(safeID)\(counter)"
            counter += 1
        }
        var removed = UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? []
        removed.removeAll(where: { $0 == finalID })
        UserDefaults.standard.set(removed, forKey: "RemovedProviders")

        let hasAuth = draft.authHeader != nil && !draft.authHeader!.isEmpty
        let finalBaseline = draft.detectedBalance > 0 ? draft.baseline : 0.0
        let newBalance = Balance(
            id: finalID,
            name: draft.name,
            baseline: finalBaseline,
            remaining: draft.detectedBalance,
            updated: Date(),
            account: draft.cookieDomain,
            expires: nil,
            live: hasAuth,
            dynamicEndpoint: draft.endpoint,
            dynamicJsonPath: draft.jsonPath,
            dynamicCookieDomain: draft.cookieDomain,
            dynamicAuthHeader: draft.authHeader
        )
        balances.append(newBalance)
        setConnectionState(for: finalID, to: hasAuth ? .connected(detail: "Connected · refreshes every 5 min", lastChecked: nil) : .disconnected(reason: .unconfigured, message: "Connect in Settings"))
        save()
        reapplyOrder()
        if hasAuth {
            Task { await refreshProvider(finalID) }
        }
    }
    func setAuthHeader(_ token: String, for providerID: String) {
        guard let idx = balances.firstIndex(where: { $0.id == providerID }) else { return }
        let header = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
        balances[idx].dynamicAuthHeader = header
        balances[idx].live = true
        setConnectionState(for: providerID, to: .connecting(isInitial: false))
        save()
        ICloudSync.shared.schedulePush()
        Task { await refreshProvider(providerID) }
    }

    /// Pauses or resumes a provider without deleting its configuration, saved
    /// credentials, or position in the list.
    func setProviderEnabled(_ enabled: Bool, id: String) {
        guard let index = balances.firstIndex(where: { $0.id == id }), balances[index].isEnabled != enabled else { return }
        balances[index].isEnabled = enabled
        UserDefaults.standard.set(Date(), forKey: "APIBarSettingsModified")
        if enabled {
            let connected = isConnected(id)
            setConnectionState(for: id, to: connected ? .connected(detail: "Connected · refreshes every 5 min", lastChecked: nil) : .disconnected(reason: .unconfigured, message: "Connect in Settings"))
        } else {
            // Drop any in-flight work so a paused provider cannot write a balance
            // after the user stopped tracking it.
            inFlight.remove(id)
            clients.removeValue(forKey: id)
            setConnectionState(for: id, to: .paused)
            if mergedProvider == id {
                mergedProvider = "overview"
                UserDefaults.standard.set("overview", forKey: "MergedProvider")
            }
        }
        save()
        configureStatusItems()
        reapplyOrder()
        if enabled {
            Task { await refreshProvider(id) }
        }
    }

    func toggleProviderEnabled(id: String) {
        guard let balance = balances.first(where: { $0.id == id }) else { return }
        setProviderEnabled(!balance.isEnabled, id: id)
    }

    /// True when a secret for this provider is already stored, without ever
    /// prompting the Keychain.
    func hasStoredCredential(_ provider: String) -> Bool {
        (try? KeychainVault.load(provider)) != nil
    }
    func setMergeIcons(_ enabled: Bool) {
        guard mergeIcons != enabled else { return }
        mergeIcons = enabled
        UserDefaults.standard.set(enabled, forKey: "MergeProviderIcons")
        UserDefaults.standard.set(Date(), forKey: "APIBarSettingsModified")
        configureStatusItems()
        writeDiagnostics()
        ICloudSync.shared.schedulePush()
    }
    func selectMergedProvider(_ provider: String) {
        guard provider == "overview" || activeBalances.contains(where: { $0.id == provider }) else { return }
        mergedProvider = provider
        UserDefaults.standard.set(provider, forKey: "MergedProvider")
        UserDefaults.standard.set(Date(), forKey: "APIBarSettingsModified")
        updateTitles()
        writeDiagnostics()
        ICloudSync.shared.schedulePush()
    }
    var browserName: String { BraveSessionImporter.currentBrowser.name }
    @Published var providerStatus: [String:String] = [:]
    @Published var isBraveInstalled: Bool = BraveSessionImporter.isBraveInstalled()
    @Published var braveAccessKind: BraveSessionImporter.BraveAccessKind = BraveSessionImporter.accessKind()
    @Published var isBraveAccessBlocked: Bool = (BraveSessionImporter.accessKind() == .blocked)
    @Published var availableBraveProfiles: [BraveProfile] = BraveSessionImporter.availableProfiles()
    @Published var selectedBraveProfileID: String = {
        let profiles = BraveSessionImporter.availableProfiles()
        if let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let last = URL(fileURLWithPath: path).lastPathComponent
            if profiles.contains(where: { $0.id == last }) {
                return last
            }
        }
        return profiles.first?.id ?? "Default"
    }()
    @Published var braveProfileStatus: String = {
        let browser = BraveSessionImporter.currentBrowser.name
        if !BraveSessionImporter.isBraveInstalled() {
            return "\(browser) was not found in Applications."
        }
        let kind = BraveSessionImporter.accessKind()
        if kind == .blocked {
            return "macOS blocked access to \(browser). Grant Full Disk Access or choose your \(browser) profile folder."
        }
        let profiles = BraveSessionImporter.availableProfiles()
        let profileName: String
        if let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let last = URL(fileURLWithPath: path).lastPathComponent
            profileName = profiles.first(where: { $0.id == last })?.displayName ?? last
        } else {
            profileName = profiles.first?.displayName ?? "Default"
        }
        let accessDesc = (kind == .fullDisk) ? "Full Disk Access active" : "Folder access active"
        return "\(accessDesc) · Selected profile: \(profileName)"
    }()
    var clients: [String:SessionHTTP] = [:]
    @Published var inFlight = Set<String>()
    var lastRefresh: Date?
    var items: [NSStatusItem] = []
    var timer: Timer?
    var fdaPollTimer: Timer?
    var appError: String?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var changelogWindow: NSWindow?
    var mergedMenuView: MergedMenuView?
    /// Test/CLI harnesses set `APIBAR_DATA_DIR` so they never overwrite the
    /// user's real balance file.
    let dataURL: URL = {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true).appendingPathComponent("balances.json")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("APIBar/balances.json")
    }()
    /// The bundle identifier moved from the legacy local ID to `app.apibar.APIBar`.
    /// macOS keys preferences by bundle id, so carry the old domain's keys over
    /// once; otherwise an update would silently reset onboarding and the browser
    /// profile choice.
    static func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        let marker = "MigratedFromLegacyBundleID"
        guard !defaults.bool(forKey: marker) else { return }
        defer { defaults.set(true, forKey: marker) }

        for legacyDomain in ["local.apibar.APIBar", "app.apibar.legacy"] {
            if let legacy = UserDefaults.standard.persistentDomain(forName: legacyDomain), !legacy.isEmpty {
                for (key, value) in legacy where key != marker && defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") {
            showOnboarding()
            return true
        }
        settings()
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.migrateLegacyDefaults()
        ICloudSync.shared.attach(app: self)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBraveProfiles()
            }
        }
        NSApp.applicationIconImage = BrandMark.appIconImage(size: 256)
        // This callback runs after the application run loop has started.
        // Command-line diagnostic launches need the same agent policy as Launch Services.
        if NSApp.activationPolicy() == .regular { NSApp.setActivationPolicy(.accessory) }
        if let index = CommandLine.arguments.firstIndex(of: "--probe-provider"), CommandLine.arguments.indices.contains(index + 2) {
            let provider = CommandLine.arguments[index + 1], output = CommandLine.arguments[index + 2]
            Task {
                await ProviderProbe.run(provider: provider, output: URL(fileURLWithPath: output))
                NSApp.terminate(nil)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--connect-provider") ?? CommandLine.arguments.firstIndex(of: "--check-saved-provider"), CommandLine.arguments.indices.contains(index + 2) {
            let provider = CommandLine.arguments[index + 1], output = CommandLine.arguments[index + 2]
            let useSaved = CommandLine.arguments.contains("--check-saved-provider")
            // The provider list normally loads later; the diagnostic path needs
            // it up front so `fetch` can resolve the balance record.
            if let data = try? Data(contentsOf: dataURL),
               let saved = try? JSONDecoder().decode([Balance].self, from: data) {
                balances = saved
            }
            Task {
                var result: [String:Any] = ["provider":provider]
                do {
                    let client = try await Task.detached { try useSaved ? SessionHTTP.load(provider:provider) : SessionHTTP.connect(provider:provider) }.value
                    let reading = try await fetch(provider,client:client)
                    result["remainingUSD"] = reading.remaining; result["account"] = reading.account; result["source"] = reading.url
                    result["credentialStorage"] = "macOS Keychain"
                } catch { result["error"] = error.localizedDescription }
                if let bytes = try? JSONSerialization.data(withJSONObject:result,options:.prettyPrinted) { try? bytes.write(to:URL(fileURLWithPath:output),options:.atomic) }
                NSApp.terminate(nil)
            }
            return
        }
        if let data = try? Data(contentsOf: dataURL), let saved = try? JSONDecoder().decode([Balance].self, from: data), Set(saved.map(\.id)).count == saved.count {
            let initialMap = Dictionary(uniqueKeysWithValues: Balance.initial.map { ($0.id, $0) })
            var ordered: [Balance] = []
            for s in saved {
                if initialMap[s.id] != nil || s.dynamicEndpoint != nil {
                    var b = s
                    if b.id == "aistudio" || b.name == "AI Studio" || b.name.isEmpty {
                        b.name = "Google AI Studio"
                    }
                    ordered.append(b)
                }
            }
            var changed = ordered.map(\.id) != saved.map(\.id)
            balances = ordered
            for i in balances.indices {
                if balances[i].id == "aistudio" && balances[i].name != "Google AI Studio" {
                    balances[i].name = "Google AI Studio"
                    changed = true
                }
                // An early build read Unaligned's micro-dollar balance as dollars and
                // stored a reference in the millions. A baseline that dwarfs the
                // balance of a prepaid account is corrupt, so let it re-derive from
                // the top-up ledger on the next refresh.
                if balances[i].id == "unaligned", balances[i].baseline > 1_000, balances[i].remaining < 1_000 {
                    balances[i].baseline = 0
                    changed = true
                }
                // An early build spuriously inflated Heimdallm's baseline from $5.00 to $10.00
                // on credit hold releases. If stored state has an inflated baseline while balance is <= $5.00,
                // repair it immediately to the actual tier.
                if balances[i].id == "heimdallm", balances[i].baseline > 5.0, balances[i].remaining <= 5.0 {
                    balances[i].baseline = max(PaymentReference.inferTier(for: balances[i].remaining), balances[i].remaining)
                    changed = true
                }
                // Heimdallm ships paused; if an earlier update added it enabled without credentials, pause it.
                if balances[i].id == "heimdallm", !hasStoredCredential("heimdallm"), balances[i].account.isEmpty, balances[i].baseline == 0, balances[i].disabled == nil {
                    balances[i].disabled = true
                    changed = true
                }
            }
            if changed { save() }
        }
        applySorting()
        if CommandLine.arguments.contains("--preview") {
            preview(); NSApp.terminate(nil); return
        }
        // Earlier builds created anonymous items before assigning their stable
        // names. macOS 27 can retain hidden flags for those old identities.
        // Migrate once; never overwrite Thaw's ongoing section choices.
        let preferences = UserDefaults.standard
        if !preferences.bool(forKey: "MigratedAnonymousStatusItemVisibility") {
            for name in ["Item-0", "Item-1"] {
                preferences.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
                preferences.removeObject(forKey: "NSStatusItem Visible \(name)")
            }
            preferences.set(true, forKey: "MigratedAnonymousStatusItemVisibility")
        }
        setupMainMenuIfNeeded()
        for b in balances {
            if !b.isEnabled {
                setConnectionState(for: b.id, to: .paused)
            } else if b.live || hasStoredCredential(b.id) || (b.dynamicAuthHeader != nil && !b.dynamicAuthHeader!.isEmpty) {
                setConnectionState(for: b.id, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: b.updated))
            } else {
                setConnectionState(for: b.id, to: .disconnected(reason: .unconfigured, message: "Connect in Settings"))
            }
        }
        configureStatusItems()
        updateTitles()
        writeDiagnostics()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.updateTitles()
            if self.lastRefresh.map({ Date().timeIntervalSince($0) >= 300 }) != false {
                await self.refreshAll()
                await AppUpdater.shared.checkForUpdates(manual: false)
            }
        } }
        Task {
            await refreshAll()
            await AppUpdater.shared.checkForUpdates(manual: false)
        }
        if !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboarding()
            }
        }
    }
    func configureStatusItems() {
        let identities = mergeIcons ? ["merged"] : (activeBalances.isEmpty ? ["merged"] : activeBalances.map(\.id))
        let wanted = Set(identities)
        // Status items are stable handles. Menu bar managers (Thaw, Bartender, Ice)
        // anchor their own layout to each item's accessibility window, so removing
        // and recreating them on a reorder makes those managers loop and throws away
        // the placement the user arranged by hand. Reconcile by identity instead:
        // keep every wanted item exactly as it is, add only the missing ones, and
        // remove only items whose provider was deleted or paused.
        for item in items where !wanted.contains(item.autosaveName ?? "") {
            NSStatusBar.system.removeStatusItem(item)
        }
        let removedAny = items.contains { !wanted.contains($0.autosaveName ?? "") }
        items.removeAll { !wanted.contains($0.autosaveName ?? "") }
        if removedAny || items.isEmpty { mergedMenuView = nil }
        let present = Set(items.compactMap { $0.autosaveName })
        if present == wanted, !items.isEmpty {
            updateTitles()
            return
        }
        for identity in identities where !present.contains(identity) {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = identity
            item.button?.setAccessibilityIdentifier(identity)
            let name = identity == "merged" ? "All providers" : (balances.first(where: { $0.id == identity })?.name ?? "API Bar")
            item.button?.setAccessibilityLabel("API Bar — \(name)")
            let menu = NSMenu(); menu.delegate = self
            menu.identifier = NSUserInterfaceItemIdentifier(identity)
            item.menu = menu
            item.button?.font = .systemFont(ofSize: NSFont.systemFontSize)
            item.button?.imageScaling = .scaleNone
            item.button?.imagePosition = .imageLeading
            items.append(item)
            // AppKit may decline to open an entirely empty status menu before
            // asking its delegate to update it. Seed its first presentation.
            menuWillOpen(menu)
            // Visibility is deliberately not forced. A menu bar manager that keeps
            // this item concealed would re-hide it, and re-asserting it here turns
            // the two apps into a fight; a new item is visible by default anyway.
        }
        updateTitles()
    }
    func writeDiagnostics() {
        let output: URL
        if let arg = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.indices.contains(arg + 1) {
            output = URL(fileURLWithPath: CommandLine.arguments[arg + 1])
        } else {
            output = dataURL.deletingLastPathComponent().appendingPathComponent("runtime.json")
        }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let diagnostics: [String: Any] = [
                "appName": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "",
                "bundleID": Bundle.main.bundleIdentifier ?? "",
                "braveAccessKind": braveAccessKind.rawValue,
                "hasFullDiskAccess": BraveSessionImporter.hasFullDiskAccess(),
                "fdaDebugLog": BraveSessionImporter.fdaDebugLog,
                "isBraveAccessBlocked": isBraveAccessBlocked,
                "selectedBraveProfileID": selectedBraveProfileID,
                "braveProfileStatus": braveProfileStatus,
                "availableProfilesCount": availableBraveProfiles.count,
                "activationPolicy": NSApp.activationPolicy().rawValue,
                "buttonFrames": items.map { NSStringFromRect($0.button?.frame ?? .zero) },
                "windowFrames": items.map { NSStringFromRect($0.button?.window?.frame ?? .zero) },
                "statusItemCount": items.count,
                "mergeIcons": mergeIcons,
                "mergedProvider": mergedProvider,
                "autosaveNames": items.map { $0.autosaveName ?? "" },
                "accessibilityIdentifiers": items.map { $0.button?.accessibilityIdentifier() ?? "" },
                "accessibilityLabels": items.map { $0.button?.accessibilityLabel() ?? "" },
                "accessibilityValues": items.map { $0.button?.accessibilityValue() as? String ?? "" },
                "imageSizes": items.map { [Double($0.button?.image?.size.width ?? 0), Double($0.button?.image?.size.height ?? 0)] },
                "imageTemplates": items.map { $0.button?.image?.isTemplate ?? false },
                "titles": items.compactMap { $0.button?.title },
                "fontNames": items.compactMap { $0.button?.font?.fontName },
                "fontSizes": items.compactMap { $0.button?.font?.pointSize },
                "visible": items.map(\.isVisible),
                "loginStatus": String(describing: SMAppService.mainApp.status),
                "providerStatus": providerStatus,
                "stateMachines": [
                    "presentation": menuBarPresentationMode.telemetryRepresentation,
                    "updater": AppUpdater.shared.telemetryRepresentation,
                    "cloudSync": ICloudSync.shared.telemetryRepresentation,
                    "browserAccess": browserAccessState.telemetryRepresentation,
                    "providers": providerConnectionStates.mapValues { $0.telemetryRepresentation }
                ],
                "backgroundRefreshFinished": lastRefresh != nil,
                "credentialPrompts": "explicit-connect-only",
                "menuTitles": items.compactMap { $0.menu?.items.map(\.title) }
            ]
            if let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: .prettyPrinted) { try? data.write(to: output, options: .atomic) }
        } catch { }
    }
    func fetch(_ provider: String, client: SessionHTTP) async throws -> Reading {
        guard let balance = balances.first(where:{$0.id == provider}) else { throw ConnectorError.message("Unknown provider.") }
        if provider == "crowbot" { return try await CrowbotProvider(http: client, expectedAccount: balance.account).fetchBalance() }
        if provider == "fireworks" { return try await FireworksProvider(http:client,account:balance.account).fetchBalance() }
        if provider == "aistudio" { return try await AIStudioProvider(http: client, account: balance.account).fetchBalance() }
        if provider == "cerebras" { return try await CerebrasProvider(http: client, account: balance.account).fetchBalance() }
        if provider == "refuseless" { return try await RefuselessProvider(http: client, account: balance.account).fetchBalance() }
        if provider == "lutheos" { return try await LutheosProvider(http: client, account: balance.account).fetchBalance() }
        if provider == "unaligned" { return try await UnalignedProvider(http: client, account: balance.account).fetchBalance() }
        if provider == "yeta" { return try await YetaProvider(http: client, account: balance.account).fetchBalance() }
        if provider == "heimdallm" { return try await HeimdallmProvider(http: client, account: balance.account).fetchBalance() }
        if provider == "inferhub" { return try await InferHubProvider(http: client, balance: balance).fetchBalance() }
        if provider == "vertex" { return try await GoogleProvider(http:client,account:balance.account).fetchBalance() }
        if balance.dynamicEndpoint != nil {
            return try await DynamicProvider(http: client, balance: balance).fetchBalance()
        }
        return try await GoogleProvider(http:client,account:balance.account).fetchBalance()
    }
    func refreshAll() async {
        lastRefresh = Date()
        for balance in balances where balance.isEnabled {
            guard !inFlight.contains(balance.id) else { continue }
            inFlight.insert(balance.id)
            do {
                let client: SessionHTTP
                if let existing = clients[balance.id] {
                    if await existing.cookies.isEmpty || providerStatus[balance.id]?.contains("expired") == true {
                        _ = try? await existing.reloadCookiesFromBrave(interactive: false)
                    }
                    client = existing
                } else if let auth = balance.dynamicAuthHeader, !auth.isEmpty {
                    let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                    client = SessionHTTP(provider: balance.id, cookies: [], dynamicHost: host)
                    clients[balance.id] = client
                } else {
                    let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                    client = try SessionHTTP.load(provider: balance.id, dynamicHost: host, cookieDomain: balance.dynamicCookieDomain)
                    clients[balance.id] = client
                }
                let reading: Reading
                do {
                    reading = try await fetch(balance.id, client: client)
                } catch {
                    if let fresh = try? SessionHTTP.connect(provider: balance.id, cookieDomain: balance.dynamicCookieDomain) {
                        reading = try await fetch(balance.id, client: fresh)
                        clients[balance.id] = fresh
                    } else {
                        throw error
                    }
                }
                apply(reading)
            } catch {
                handleFetchError(id: balance.id, error: error, fallbackName: balance.name)
            }
            inFlight.remove(balance.id)
        }
        updateTitles()
        writeDiagnostics()
        if ICloudSync.shared.isEnabled {
            Task { await ICloudSync.shared.syncNow() }
        }
    }
    func refreshBraveProfiles() {
        isBraveInstalled = BraveSessionImporter.isBraveInstalled()
        braveAccessKind = BraveSessionImporter.accessKind()
        isBraveAccessBlocked = (braveAccessKind == .blocked)
        availableBraveProfiles = BraveSessionImporter.availableProfiles()
        if !isBraveInstalled {
            braveProfileStatus = "\(browserName) was not found in Applications."
            return
        }
        if isBraveAccessBlocked {
            braveProfileStatus = "macOS blocked access to \(browserName). Grant Full Disk Access or choose your \(browserName) profile folder."
            return
        }
        let profileName: String
        if let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let last = URL(fileURLWithPath: path).lastPathComponent
            if availableBraveProfiles.contains(where: { $0.id == last }) {
                selectedBraveProfileID = last
                profileName = availableBraveProfiles.first(where: { $0.id == last })?.displayName ?? last
            } else {
                profileName = availableBraveProfiles.first(where: { $0.id == selectedBraveProfileID })?.displayName ?? selectedBraveProfileID
            }
        } else {
            if !availableBraveProfiles.contains(where: { $0.id == selectedBraveProfileID }), let first = availableBraveProfiles.first {
                selectedBraveProfileID = first.id
            }
            profileName = availableBraveProfiles.first(where: { $0.id == selectedBraveProfileID })?.displayName ?? selectedBraveProfileID
        }
        let accessDesc = (braveAccessKind == .fullDisk) ? "Full Disk Access active" : "Folder access active"
        braveProfileStatus = "\(accessDesc) · Selected profile: \(profileName)"
    }

    func selectBraveProfile(id: String) {
        refreshBraveProfiles()
        guard let profile = availableBraveProfiles.first(where: { $0.id == id }) else { return }
        selectedBraveProfileID = id
        do {
            try BraveSessionImporter.rememberProfile(profile.url)
            refreshBraveProfiles()
            if !isBraveAccessBlocked {
                braveProfileStatus = "Selected \(profile.displayName). Connect each provider below."
            }
        } catch { alert("Could not select profile", error.localizedDescription) }
    }

    func chooseBraveProfile() {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to \(browserName) Browser"
        panel.message = "Select your '\(browserName)' folder (or a profile folder like 'Default') to allow API Bar to import your sessions."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        let (root, _) = BraveSessionImporter.resolvedBrowserRoot()
        if FileManager.default.fileExists(atPath: root.path) {
            panel.directoryURL = root
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
                .appendingPathComponent(BraveSessionImporter.currentBrowser.appSupportRelativePath)
                .deletingLastPathComponent()
        }

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try BraveSessionImporter.rememberProfile(url)
                refreshBraveProfiles()
                braveProfileStatus = "Access granted to \(browserName). Connect each provider below."
            } catch {
                alert("Could not select \(browserName) folder", error.localizedDescription)
            }
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        fdaPollTimer?.invalidate()
        var remaining = 30
        fdaPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.refreshBraveProfiles()
                remaining -= 1
                if !self.isBraveAccessBlocked || remaining <= 0 {
                    timer.invalidate()
                    self.fdaPollTimer = nil
                }
            }
        }
    }

    func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let escapedPath = bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        while /bin/kill -0 \(pid) 2>/dev/null; do
            /bin/sleep 0.05
        done
        /bin/sleep 0.1
        /usr/bin/open '\(escapedPath)'
        """
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", script]
        relaunch.standardInput = FileHandle.nullDevice
        relaunch.standardOutput = FileHandle.nullDevice
        relaunch.standardError = FileHandle.nullDevice
        try? relaunch.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.terminate(nil)
        }
    }

    func connect(_ provider: String) {
        guard !inFlight.contains(provider) else { return }
        inFlight.insert(provider)
        setConnectionState(for: provider, to: .connecting(isInitial: false))
        Task {
            defer {
                inFlight.remove(provider)
                updateTitles()
            }
            do {
                // Only this explicit Settings action is allowed to display credential UI.
                let b = balances.first(where: { $0.id == provider })
                let host = b?.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                let client: SessionHTTP
                if let auth = b?.dynamicAuthHeader, !auth.isEmpty {
                    client = SessionHTTP(provider: provider, cookies: [], dynamicHost: host)
                } else {
                    let cookieDomain = b?.dynamicCookieDomain
                    client = try await Task.detached {
                        try SessionHTTP.connect(provider: provider, cookieDomain: cookieDomain, dynamicHost: host, interactive: true)
                    }.value
                }
                let reading = try await withThrowingTaskGroup(of: Reading.self) { group in
                    group.addTask { try await self.fetch(provider, client: client) }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 15_000_000_000)
                        throw ConnectorError.message("Connection timed out after 15 seconds.")
                    }
                    let res = try await group.next()!
                    group.cancelAll()
                    return res
                }
                clients[provider] = client
                apply(reading)
                setConnectionState(for: provider, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
            } catch {
                setConnectionState(for: provider, to: .degraded(error: error.localizedDescription, canRetry: true))
                refreshBraveProfiles()
                if let b = balances.first(where: { $0.id == provider }) {
                    openDashboard(b)
                }
                if isBraveAccessBlocked || error.localizedDescription.contains("blocked access to") {
                    let alert = NSAlert()
                    alert.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
                    alert.messageText = "\(browserName) Access Blocked by macOS"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "Grant Full Disk Access")
                    alert.addButton(withTitle: "Folder Access Only")
                    alert.addButton(withTitle: "Cancel")
                    NSApp.activate(ignoringOtherApps: true)
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        openFullDiskAccessSettings()
                    } else if response == .alertSecondButtonReturn {
                        chooseBraveProfile()
                    }
                } else {
                    alert("Could not connect", error.localizedDescription)
                }
            }
        }
    }
    func connectAll() {
        Task {
            defer {
                inFlight.removeAll()
                updateTitles()
            }
            let targets = balances.filter { $0.isEnabled && !isConnected($0.id) }
            guard !targets.isEmpty else {
                updateTitles()
                return
            }

            for balance in targets {
                inFlight.insert(balance.id)
                setConnectionState(for: balance.id, to: .connecting(isInitial: false))
            }
            updateTitles()

            // Pre-authenticate safe storage once interactively so the user is prompted
            // at most once for Keychain authorization, rather than failing with -25293
            // or prompting concurrently for multiple providers.
            _ = try? await Task.detached {
                try BraveSessionImporter.prepareSafeStorage(interactive: true)
            }.value

            var errors: [String] = []
            await withTaskGroup(of: (String, Result<Reading, Error>).self) { group in
                for balance in targets {
                    group.addTask { [balance] in
                        do {
                            let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                            let client: SessionHTTP
                            if let auth = balance.dynamicAuthHeader, !auth.isEmpty {
                                client = SessionHTTP(provider: balance.id, cookies: [], dynamicHost: host)
                            } else {
                                let cookieDomain = balance.dynamicCookieDomain
                                client = try SessionHTTP.connect(provider: balance.id, cookieDomain: cookieDomain, dynamicHost: host, interactive: true)
                            }
                            let reading = try await withThrowingTaskGroup(of: Reading.self) { fetchGroup in
                                fetchGroup.addTask {
                                    try await self.fetch(balance.id, client: client)
                                }
                                fetchGroup.addTask {
                                    try await Task.sleep(nanoseconds: 15_000_000_000)
                                    throw ConnectorError.message("Connection timed out after 15 seconds.")
                                }
                                let res = try await fetchGroup.next()!
                                fetchGroup.cancelAll()
                                return res
                            }
                            await MainActor.run {
                                self.clients[balance.id] = client
                            }
                            return (balance.id, .success(reading))
                        } catch {
                            return (balance.id, .failure(error))
                        }
                    }
                }

                for await (id, result) in group {
                    inFlight.remove(id)
                    switch result {
                    case .success(let reading):
                        apply(reading)
                        setConnectionState(for: id, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
                    case .failure(let error):
                        setConnectionState(for: id, to: .degraded(error: error.localizedDescription, canRetry: true))
                        if let name = balances.first(where: { $0.id == id })?.name {
                            errors.append("\(name): \(error.localizedDescription)")
                        }
                    }
                    updateTitles()
                }
            }

            refreshBraveProfiles()
            writeDiagnostics()
            if ICloudSync.shared.isEnabled {
                Task { await ICloudSync.shared.syncNow() }
            }
        }
    }
    func isConnected(_ provider: String) -> Bool {
        guard let b = balances.first(where: { $0.id == provider }) else { return false }
        if let state = providerConnectionStates[provider] {
            return state.isOnline
        }
        if let status = providerStatus[provider] {
            if status.contains("Connect in Settings") || status.contains("Disconnected") || status.contains("expired") || status.hasPrefix("Not connected") || status == "Paused" {
                return false
            }
            if status.hasPrefix("Connected") { return true }
        }
        if b.live && providerStatus[provider]?.hasPrefix("Connected") != false { return true }
        if let auth = b.dynamicAuthHeader, !auth.isEmpty { return true }
        if hasStoredCredential(provider) && providerStatus[provider]?.contains("Connect in Settings") != true { return true }
        return false
    }
    func disconnect(_ provider: String) {
        guard !inFlight.contains(provider) else { return }
        clients.removeValue(forKey: provider); KeychainVault.clear(provider)
        setConnectionState(for: provider, to: .disconnected(reason: .manual, message: "Disconnected"))
        if let i = balances.firstIndex(where: { $0.id == provider }) { balances[i].live = false }
        save(); updateTitles()
    }
    func apply(_ r: Reading) {
        guard ReadingValidation.valid(r, balances: balances), let i = balances.firstIndex(where: { $0.id == r.provider }) else {
            setConnectionState(for: r.provider, to: .rejected(reason: "A balance from a different account or source was rejected."))
            return
        }
        if balances[i].account.isEmpty || balances[i].account.hasSuffix(" Account") { balances[i].account = r.account }
        let oldRemaining = balances[i].remaining
        balances[i].remaining = r.remaining; balances[i].updated = Date(); balances[i].live = true; balances[i].expires = r.expires
        if let tpd = r.tokensPerDay { balances[i].tokensPerDay = tpd }
        if let rd = r.runwayDays { balances[i].runwayDays = rd }
        if r.provider == "refuseless" {
            if let ref = r.reference, ref > 0 {
                balances[i].baseline = max(ref, r.remaining)
            } else if balances[i].baseline <= 0 {
                balances[i].baseline = PaymentReference.inferTier(for: r.remaining)
            } else if r.remaining > oldRemaining && oldRemaining > 0 {
                let delta = r.remaining - oldRemaining
                let paidAmount = PaymentReference.inferTier(for: delta)
                balances[i].baseline = max(balances[i].baseline + paidAmount, r.remaining)
            } else {
                balances[i].baseline = max(balances[i].baseline, r.remaining)
            }
            setConnectionState(for: r.provider, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
            if sortMode != .manual {
                applySorting()
            } else {
                save(); updateTitles()
            }
            return
        }
        if r.provider == "lutheos" {
            if let ref = r.reference, ref > 0 {
                if balances[i].baseline <= 0 || ref >= balances[i].baseline {
                    balances[i].baseline = max(ref, r.remaining)
                } else {
                    balances[i].baseline = max(balances[i].baseline, r.remaining)
                }
            } else if balances[i].baseline <= 0 {
                balances[i].baseline = PaymentReference.inferTier(for: r.remaining)
            } else if r.remaining > oldRemaining && oldRemaining > 0 {
                let delta = r.remaining - oldRemaining
                let paidAmount = PaymentReference.inferTier(for: delta)
                balances[i].baseline = max(balances[i].baseline + paidAmount, r.remaining)
            } else {
                balances[i].baseline = max(balances[i].baseline, r.remaining)
            }
            setConnectionState(for: r.provider, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
            if sortMode != .manual {
                applySorting()
            } else {
                save(); updateTitles()
            }
            return
        }
        if r.provider == "heimdallm" {
            if let ref = r.reference, ref > 0 {
                balances[i].baseline = max(ref, r.remaining)
            } else if balances[i].baseline <= 0 || (balances[i].baseline > 5.0 && balances[i].remaining <= 5.0) {
                balances[i].baseline = PaymentReference.inferTier(for: r.remaining)
            } else {
                balances[i].baseline = max(balances[i].baseline, r.remaining)
            }
            setConnectionState(for: r.provider, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
            if sortMode != .manual {
                applySorting()
            } else {
                save(); updateTitles()
            }
            return
        }
        if r.provider == "unaligned" {
            if let ref = r.reference, ref > 0 {
                balances[i].baseline = max(ref, r.remaining)
            } else if balances[i].baseline <= 0 {
                balances[i].baseline = PaymentReference.inferTier(for: r.remaining)
            } else {
                balances[i].baseline = max(balances[i].baseline, r.remaining)
            }
            setConnectionState(for: r.provider, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
            if sortMode != .manual {
                applySorting()
            } else {
                save(); updateTitles()
            }
            return
        }
        if r.provider == "inferhub" {
            if let ref = r.reference, ref > 0 {
                balances[i].baseline = max(ref, r.remaining)
            } else if balances[i].baseline <= 0 {
                balances[i].baseline = PaymentReference.inferTier(for: r.remaining)
            } else if r.remaining > oldRemaining && oldRemaining > 0 {
                let delta = r.remaining - oldRemaining
                let paidAmount = PaymentReference.inferTier(for: delta)
                balances[i].baseline = max(balances[i].baseline + paidAmount, r.remaining)
            } else {
                balances[i].baseline = max(balances[i].baseline, r.remaining)
            }
            setConnectionState(for: r.provider, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
            if sortMode != .manual {
                applySorting()
            } else {
                save(); updateTitles()
            }
            return
        }
        // Automatic 100% reference & top-up calculation for generic providers:
        if r.remaining > oldRemaining && oldRemaining > 0 {
            let delta = r.remaining - oldRemaining
            let paidAmount = PaymentReference.inferTier(for: delta)
            balances[i].baseline = max(balances[i].baseline + paidAmount, r.remaining)
        } else if balances[i].baseline <= 0 {
            let ref = r.reference ?? PaymentReference.inferTier(for: r.remaining)
            balances[i].baseline = max(ref, r.remaining)
        } else if let ref = r.reference, ref > balances[i].baseline {
            balances[i].baseline = ref
        } else {
            balances[i].baseline = max(balances[i].baseline, r.remaining)
        }
        setConnectionState(for: r.provider, to: .connected(detail: "Connected · refreshes every 5 min", lastChecked: Date()))
        if sortMode != .manual {
            applySorting()
        } else {
            save(); updateTitles()
        }
    }
    func accept(_ data: Data) {
        guard let r = try? JSONDecoder().decode(Reading.self,from:data) else { return }; apply(r)
    }
    func save() {
        let removed = UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? []
        let activeIDs = Set(balances.map(\.id))
        let filtered = removed.filter { !activeIDs.contains($0) }
        if filtered != removed {
            UserDefaults.standard.set(filtered, forKey: "RemovedProviders")
        }
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(balances)
            try bytes.write(to: dataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
        } catch { appError = "Could not save balances: \(error.localizedDescription)" }
        ICloudSync.shared.schedulePush()
    }
    func updateTitles() {
        for (i, item) in items.enumerated() {
            // Resolve by the item's stable identity rather than by array index. A
            // menu bar manager may place the items in any order, and a stale index
            // would write one provider's percentage into another provider's button.
            let identity = item.autosaveName ?? ""
            let isMergedItem = mergeIcons || identity == "merged"
            if isMergedItem {
                if mergedProvider == "overview" {
                    if activeBalances.isEmpty {
                        if items[i].button?.title != "" { items[i].button?.title = "" }
                        items[i].button?.image = BrandMark.appIconImage(size: 18)
                        items[i].button?.toolTip = nil
                        items[i].button?.setAccessibilityValue("No providers configured")
                    } else {
                        let usdRemaining = activeBalances.reduce(0.0) { $0 + $1.remaining }
                        let usdBaseline = activeBalances.reduce(0.0) { $0 + $1.baseline }
                        let totalPercent = usdBaseline > 0 ? max(0, usdRemaining / usdBaseline * 100) : 0
                        let percentText: String = {
                            if usdBaseline <= 0 { return "—" }
                            if totalPercent > 0 && totalPercent < 1 { return "<1%" }
                            return "\(Int(floor(totalPercent)))%"
                        }()
                        if items[i].button?.title != percentText {
                            items[i].button?.title = percentText
                        }
                        items[i].button?.image = ProviderIcon.menuBarImage("overview")
                        items[i].button?.toolTip = nil
                        items[i].button?.setAccessibilityValue("\(percentText) remaining across all providers")
                    }
                } else if let b = selectedMergedBalance {
                    if items[i].button?.title != b.percentageLabel {
                        items[i].button?.title = b.percentageLabel
                    }
                    items[i].button?.image = ProviderIcon.menuBarImage(b.id)
                    items[i].button?.toolTip = nil
                    items[i].button?.setAccessibilityValue("\(b.percentageLabel) remaining\(b.stale ? ", stale" : "")")
                } else {
                    if items[i].button?.title != "—" {
                        items[i].button?.title = "—"
                    }
                    items[i].button?.image = ProviderIcon.menuBarImage("overview")
                    items[i].button?.toolTip = nil
                    items[i].button?.setAccessibilityValue("API Bar — No active providers")
                }
            } else {
                guard let b = activeBalances.first(where: { $0.id == identity }) else { continue }
                if items[i].button?.title != b.percentageLabel {
                    items[i].button?.title = b.percentageLabel
                }
                items[i].button?.image = ProviderIcon.menuBarImage(b.id)
                items[i].button?.toolTip = nil
                items[i].button?.setAccessibilityValue("\(b.percentageLabel) remaining\(b.stale ? ", stale" : "")")
            }
        }
        mergedMenuView?.refresh()
    }
    func menuWillOpen(_ menu: NSMenu) {
        if menu.identifier?.rawValue == "merged" {
            menu.removeAllItems()
            menu.minimumWidth = 365
            let card = NSMenuItem()
            let content = MergedMenuView(app: self)
            mergedMenuView = content
            card.view = content
            menu.addItem(card)
            menu.addItem(.separator())
            if AppUpdater.shared.updateAvailable, let ver = AppUpdater.shared.latestVersion {
                let updateTitle = AppUpdater.shared.isSemverNewerAvailable ? "Update to v\(ver) Available…" : "Refreshed Build of v\(ver) Available…"
                action(menu, updateTitle, #selector(openSoftwareUpdate), 0, "arrow.down.circle.fill")
                menu.addItem(.separator())
            }
            action(menu, "Dashboard…", #selector(openMergedBilling), 0, "arrow.up.right.square")
            let refreshItem = action(menu, "Refresh", #selector(refreshMergedProvider), 0, "arrow.clockwise")
            refreshItem.keyEquivalent = "r"
            let refreshAllItem = action(menu, "Refresh All", #selector(refresh), 0, "arrow.clockwise")
            refreshAllItem.keyEquivalent = "r"
            refreshAllItem.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(.separator())
            let login = action(menu, "Start at Login", #selector(toggleLogin), 0, "power.circle")
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            if SMAppService.mainApp.status == .requiresApproval { disabled(menu, "Login item needs approval in System Settings") }
            action(menu, "Settings…", #selector(settings), 0, "gearshape").keyEquivalent = ","
            action(menu, "Check for Updates…", #selector(checkForUpdates), 0, "arrow.triangle.2.circlepath")
            action(menu, "Changelog…", #selector(showChangelog), 0, "clock.arrow.circlepath")
            action(menu, "About API Bar…", #selector(about), 0, "info.circle")
            menu.addItem(.separator())
            action(menu, "Quit API Bar", #selector(quit), 0, "power").keyEquivalent = "q"
            return
        }
        guard let index = balances.firstIndex(where: { $0.id == menu.identifier?.rawValue }) else { return }
        let b = balances[index]
        menu.removeAllItems()
        menu.minimumWidth = 365
        let card = NSMenuItem(); card.view = BalanceCard(b,status:providerStatus[b.id]); menu.addItem(card)
        menu.addItem(.separator())
        if AppUpdater.shared.updateAvailable, let ver = AppUpdater.shared.latestVersion {
            let updateTitle = AppUpdater.shared.isSemverNewerAvailable ? "Update to v\(ver) Available…" : "Refreshed Build of v\(ver) Available…"
            action(menu, updateTitle, #selector(openSoftwareUpdate), index, "arrow.down.circle.fill")
            menu.addItem(.separator())
        }
        if let error = appError { disabled(menu, "Save error: \(error)") }
        action(menu, "Dashboard…", #selector(openBilling(_:)), index, "arrow.up.right.square")
        let refreshItem = action(menu, "Refresh", #selector(refreshSingleProvider(_:)), index, "arrow.clockwise")
        refreshItem.keyEquivalent = "r"
        let refreshAllItem = action(menu, "Refresh All", #selector(refresh), index, "arrow.clockwise")
        refreshAllItem.keyEquivalent = "r"
        refreshAllItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        let login = action(menu, "Start at Login", #selector(toggleLogin), index, "power.circle")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { disabled(menu, "Login item needs approval in System Settings") }
        action(menu, "Settings…", #selector(settings), index, "gearshape").keyEquivalent = ","
        action(menu, "Check for Updates…", #selector(checkForUpdates), index, "arrow.triangle.2.circlepath")
        action(menu, "Changelog…", #selector(showChangelog), index, "clock.arrow.circlepath")
        action(menu, "About API Bar…", #selector(about), index, "info.circle")
        menu.addItem(.separator())
        action(menu, "Quit API Bar", #selector(quit), index, "power").keyEquivalent = "q"
    }
    func disabled(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item)
    }
    @discardableResult func action(_ menu: NSMenu, _ title: String, _ selector: Selector, _ index: Int, _ symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; item.tag = index
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item); return item
    }
    func refreshProvider(_ providerID: String) async {
        guard let balance = balances.first(where: { $0.id == providerID }) else { return }
        guard !inFlight.contains(balance.id) else { return }
        inFlight.insert(balance.id)
        defer {
            inFlight.remove(balance.id)
            updateTitles()
            writeDiagnostics()
        }
        lastRefresh = Date()
        do {
            let client: SessionHTTP
            if let existing = clients[balance.id] {
                if await existing.cookies.isEmpty || providerStatus[balance.id]?.contains("expired") == true {
                    _ = try? await existing.reloadCookiesFromBrave(interactive: false)
                }
                client = existing
            } else if let auth = balance.dynamicAuthHeader, !auth.isEmpty {
                let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                client = SessionHTTP(provider: balance.id, cookies: [], dynamicHost: host)
                clients[balance.id] = client
            } else {
                let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                client = try SessionHTTP.load(provider: balance.id, dynamicHost: host, cookieDomain: balance.dynamicCookieDomain)
                clients[balance.id] = client
            }
            let reading: Reading
            do {
                reading = try await fetch(balance.id, client: client)
            } catch {
                if let fresh = try? SessionHTTP.connect(provider: balance.id, cookieDomain: balance.dynamicCookieDomain) {
                    reading = try await fetch(balance.id, client: fresh)
                    clients[balance.id] = fresh
                } else {
                    throw error
                }
            }
            apply(reading)
        } catch {
            handleFetchError(id: balance.id, error: error, fallbackName: balance.name)
        }
    }
    @objc func refreshMergedProvider() {
        if mergedProvider == "overview" {
            Task { await refreshAll() }
        } else if let b = selectedMergedBalance {
            Task { await refreshProvider(b.id) }
        } else {
            Task { await refreshAll() }
        }
    }
    @objc func refreshSingleProvider(_ sender: NSMenuItem) {
        guard balances.indices.contains(sender.tag) else { return }
        let id = balances[sender.tag].id
        Task { await refreshProvider(id) }
    }
    @objc func refresh() { Task { await refreshAll() } }
    func setupMainMenuIfNeeded() {
        if let menu = NSApp.mainMenu, menu.items.count > 1 { return }
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let openSettings = NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ",")
        openSettings.target = self
        appMenu.addItem(openSettings)
        let openChangelog = NSMenuItem(title: "Changelog…", action: #selector(showChangelog), keyEquivalent: "")
        openChangelog.target = self
        appMenu.addItem(openChangelog)
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(title: "Hide API Bar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit API Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
    @objc func settings() {
        if !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") {
            showOnboarding()
            return
        }
        setupMainMenuIfNeeded()
        refreshBraveProfiles()
        NSApp.setActivationPolicy(.regular)
        if let settingsWindow {
            settingsWindow.deminiaturize(nil)
            settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            writeDiagnostics(); return
        }
        let window = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 620, height: 600)
        window.title = "API Bar Settings"; window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsPane(app: self))
        window.center(); window.makeKeyAndOrderFront(nil); settingsWindow = window; NSApp.activate(ignoringOtherApps: true)
        writeDiagnostics()
    }
    @objc func showOnboarding() {
        setupMainMenuIfNeeded()
        if let settingsWindow {
            settingsWindow.close()
            self.settingsWindow = nil
        }
        NSApp.setActivationPolicy(.regular)
        if let onboardingWindow {
            onboardingWindow.deminiaturize(nil)
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Welcome to API Bar"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(app: self, onFinish: { [weak self, weak window] in
            UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
            window?.close()
            self?.onboardingWindow = nil
            if self?.settingsWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }))
        window.center()
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            refreshBraveProfiles()
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === onboardingWindow { onboardingWindow = nil }
        if window === changelogWindow { changelogWindow = nil }
        if settingsWindow == nil && onboardingWindow == nil && changelogWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
        writeDiagnostics()
    }
    @objc func showChangelog() {
        setupMainMenuIfNeeded()
        NSApp.setActivationPolicy(.regular)
        if let changelogWindow {
            changelogWindow.deminiaturize(nil)
            changelogWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 600, height: 440)
        window.title = "API Bar Changelog"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ChangelogView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        changelogWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { alert("Start at Login", "macOS could not change the login item: \(error.localizedDescription)") }
    }
    @objc func openMergedBilling() {
        if mergedProvider == "overview" {
            if let first = activeBalances.first {
                openDashboard(first)
            } else {
                settings()
            }
        } else if let b = selectedMergedBalance {
            openDashboard(b)
        } else {
            settings()
        }
    }
    @objc func openBilling(_ sender: NSMenuItem) { openDashboard(balances[sender.tag]) }
    func openDashboard(_ b: Balance) {
        openDefaultBrowser(billingURL(b))
    }
    func billingURL(_ b: Balance) -> URL {
        if b.id.contains("venice") || b.dynamicEndpoint?.contains("venice.ai") == true {
            return URL(string: "https://venice.ai/settings/api")!
        }
        let meta = AFMProviderExtractor.resolveProvider(named: b.name)
        if (meta.id == b.id || meta.name == b.name), let url = URL(string: meta.dashboardURL) {
            return url
        }
        if let endpoint = b.dynamicEndpoint, let url = URL(string: endpoint) {
            if let domain = b.dynamicCookieDomain, !domain.isEmpty {
                return URL(string: "https://\(domain)") ?? url
            }
            return url
        }
        switch b.id {
        case "crowbot": return URL(string: "https://chat.crowbot.sh/#account/billing")!
        case "fireworks": return URL(string: "https://app.fireworks.ai/account/home")!
        case "aistudio": return URL(string: "https://aistudio.google.com/app/plan_and_billing")!
        case "cerebras": return URL(string: "https://cloud.cerebras.ai/platform/")!
        case "refuseless": return URL(string: "https://refuseless.com/console")!
        case "lutheos": return URL(string: "https://lutheos.com/billing")!
        case "unaligned": return URL(string: "https://unaligned.pw/dashboard")!
        case "yeta": return URL(string: YetaProvider.dashboardURL)!
        case "heimdallm": return URL(string: HeimdallmProvider.dashboardURL)!
        case "inferhub": return URL(string: InferHubProvider.dashboardURL)!
        default: return URL(string: "https://console.cloud.google.com/billing/\(b.account)/credits/all")!
        }
    }
    func openDefaultBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
    func openInBrave(_ url: URL) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: BraveSessionImporter.currentBrowser.bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
            return
        }
        openDefaultBrowser(url)
    }
    func setBaseline(for index: Int) {
        guard balances.indices.contains(index) else { return }
        let a = NSAlert()
        a.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
        a.messageText = "\(balances[index].name): set 100%"
        a.informativeText = "Enter the amount that represents 100%, including available credits. This changes the percentage calculation only. Connected providers refresh their account balance every five minutes. A balance above this reference automatically raises the reference to the new amount."
        let field = NSTextField(string: String(format: "%.2f", balances[index].baseline)); field.frame = NSRect(x: 0, y: 0, width: 250, height: 24)
        a.accessoryView = field; a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            guard let amount = Double(field.stringValue), amount.isFinite, amount > 0, amount < 1_000_000_000 else { alert("Invalid amount", "Enter a positive dollar amount."); return }
            balances[index].baseline = amount; save(); updateTitles()
        }
    }
    @objc func setBaseline(_ sender: NSMenuItem) {
        setBaseline(for: sender.tag)
    }
    @objc func setup() {
        let a = NSAlert()
        a.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
        a.messageText = "Automatic credit detection"
        a.informativeText = "Connect each provider from Settings after signing in to its billing page in \(browserName). Imported sessions are kept in macOS Keychain; background refresh does not need \(browserName) or an open tab.\n\nFireworks balance detection has been verified. Google Cloud credit detection has been verified against its billing dashboard. Failed requests keep the last successful balance.\n\nOnly Connect can ask for Keychain approval. Rebuilding this locally signed app may require reconnecting."
        a.addButton(withTitle: "Open Billing Pages"); a.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        let result = a.runModal()
        if result == .alertFirstButtonReturn { balances.forEach { openInBrave(billingURL($0)) } }
    }
    @objc func checkForUpdates() {
        Task { await AppUpdater.shared.checkForUpdates(manual: true) }
    }
    @objc func openSoftwareUpdate() {
        AppUpdater.shared.showUpdateWindow()
    }
    @objc func about() {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        alert("API Bar \(short) (\(build))", "A small companion for account-wide Vertex AI, Fireworks, Crowbot, Google AI Studio, Cerebras, and Refuseless balances. Menu bar percentages, balance details, baseline settings, and Start at Login.\n\nConnect in Settings to refresh account balances using sessions stored in macOS Keychain. Failed requests keep the last successful balance. Background refresh never requests Keychain approval.\n\nMenu styling and provider symbols follow CodexBar. Independent app; not affiliated with CodexBar, Google, Fireworks, or Cerebras.")
    }
    func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
        a.messageText = title
        a.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }
    func preview() {
        let width = CGFloat(balances.count) * 340
        let image = NSImage(size: NSSize(width: width, height: 245))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill(); NSRect(x: 0, y: 0, width: width, height: 245).fill()
        for (i, b) in balances.enumerated() {
            let x = CGFloat(i) * 340
            ProviderIcon.image(b.id).draw(in: NSRect(x: x + 20, y: 205, width: 18, height: 18))
            ("\u{2009}\(b.percentageLabel)" as NSString).draw(at: NSPoint(x: x + 39, y: 205), withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.labelColor])
            let card = BalanceCard(b)
            card.layoutSubtreeIfNeeded()
            if let bitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds) {
                card.cacheDisplay(in: card.bounds, to: bitmap)
                NSImage(cgImage: bitmap.cgImage!, size: card.bounds.size).draw(in: NSRect(x: x + 8, y: 20, width: card.frame.width, height: card.frame.height))
            }
        }
        image.unlockFocus()
        if let bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)), let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: CommandLine.arguments.last!)) }
    }
}

@MainActor
enum MenuBarReading {
    static func image(provider: String, percentage: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.black
        ]
        let text = NSAttributedString(string: percentage, attributes: attributes)
        let textSize = text.size()
        let referenceWidth = NSAttributedString(string: "100%", attributes: attributes).size().width
        let size = NSSize(width: 21 + ceil(max(textSize.width, referenceWidth)), height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            ProviderIcon.image(provider).draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            NSGraphicsContext.restoreGraphicsState()
            text.draw(at: NSPoint(x: 21, y: floor((size.height - textSize.height) / 2)))
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
enum ProviderIcon {
    private static var cache: [String: NSImage] = [:]
    private static var maskCache: [String: CGImage] = [:]

    private static func mask(for provider: String) -> CGImage? {
        if let cached = maskCache[provider] { return cached }
        if let url = Bundle.main.url(forResource: "\(provider)-mask", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep(data: data),
           let cg = rep.cgImage {
            maskCache[provider] = cg
            return cg
        }
        for path in ["Resources/\(provider)-mask.png", "../Resources/\(provider)-mask.png"] {
            let url = URL(fileURLWithPath: path)
            if let data = try? Data(contentsOf: url),
               let rep = NSBitmapImageRep(data: data),
               let cg = rep.cgImage {
                maskCache[provider] = cg
                return cg
            }
        }
        // A provider whose mask is not in the bundle (an older build, or a provider
        // list that arrived over iCloud before the matching binary) still gets its
        // real mark drawn from vector geometry instead of a letter monogram.
        if let vector = ProviderMarkGeometry.image(for: provider, pixels: 54) {
            maskCache[provider] = vector
            return vector
        }
        return nil
    }

    private static func drawOverviewIcon(in context: CGContext) {
        BrandMark.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
    }

    private static func monogramImage(_ provider: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        let initial = String(provider.prefix(1).uppercased())
        for scale in [1, 2, 3] {
            let px = 18 * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: px, pixelsHigh: px,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: 18, height: 18))

            let box = CGRect(x: 1.5, y: 1.5, width: 15, height: 15)
            let path = CGPath(roundedRect: box, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            context.cgContext.addPath(path)
            context.cgContext.setFillColor(NSColor.black.cgColor)
            context.cgContext.fillPath()

            let font = NSFont.systemFont(ofSize: 10, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: initial, attributes: attrs)
            let strSize = str.size()
            let origin = NSPoint(x: round((18 - strSize.width) / 2), y: round((18 - strSize.height) / 2))
            str.draw(at: origin)

            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        cache[provider] = image
        return image
    }

    static func hasMask(for provider: String) -> Bool {
        mask(for: provider) != nil
    }

    static func image(_ provider: String) -> NSImage {
        if let cached = cache[provider] { return cached }
        if provider == "overview" {
            let img = BrandMark.image()
            cache[provider] = img
            return img
        }
        guard let mask = mask(for: provider) else { return monogramImage(provider) }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        let (targetW, targetH): (CGFloat, CGFloat)
        switch provider {
        case "fireworks": (targetW, targetH) = (16.2, 7.6)
        case "refuseless": (targetW, targetH) = (16.0, 7.5)
        case "cerebras": (targetW, targetH) = (14.5, 16.6)
        case "vertex": (targetW, targetH) = (15.6, 14.8)
        case "aistudio": (targetW, targetH) = (16.0, 16.0)
        case "venice": (targetW, targetH) = (15.0, 15.0)
        case "lutheos": (targetW, targetH) = (16.0, 12.4)
        case "unaligned": (targetW, targetH) = (15.2, 15.2)
        case "yeta": (targetW, targetH) = (14.6, 14.6)
        case "heimdallm": (targetW, targetH) = (15.0, 15.0)
        case "inferhub": (targetW, targetH) = (15.0, 15.0)
        default: (targetW, targetH) = (15.0, 13.8) // crowbot
        }
        let targetRect = CGRect(x: (18.0 - targetW) / 2.0, y: (18.0 - targetH) / 2.0, width: targetW, height: targetH)

        for scale in [1, 2, 3] {
            let px = 18 * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: px, pixelsHigh: px,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: px, height: px))
            context.cgContext.draw(mask, in: targetRect)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        cache[provider] = image
        return image
    }

    private static var whiteCache: [String: NSImage] = [:]

    static func menuBarImage(_ provider: String) -> NSImage {
        if let cached = whiteCache[provider] { return cached }
        let base = image(provider)
        let size = NSSize(width: 18, height: 18)
        let result = NSImage(size: size)
        for scale in [1, 2, 3] {
            let px = 18 * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: px, pixelsHigh: px,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: 18, height: 18))
            base.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(NSColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 18, height: 18))
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            result.addRepresentation(bitmap)
        }
        result.isTemplate = false
        whiteCache[provider] = result
        return result
    }
}

