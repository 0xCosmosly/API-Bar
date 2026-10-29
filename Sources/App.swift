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

@MainActor
final class APIBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    @Published var balances = Balance.initial
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

    func setSortMode(_ mode: ProviderSortMode) {
        guard sortMode != mode else { return }
        sortMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "ProviderSortMode")
        applySorting()
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
        if !mergeIcons {
            configureStatusItems()
        }
        mergedMenuView?.updateProviders(balances)
        updateTitles()
        writeDiagnostics()
    }
    var selectedMergedBalance: Balance { balances.first(where: { $0.id == mergedProvider }) ?? balances.first ?? Balance.initial[0] }

    func removeProvider(id: String) {
        guard let index = balances.firstIndex(where: { $0.id == id }) else { return }
        balances.remove(at: index)
        clients.removeValue(forKey: id)
        KeychainVault.clear(id)
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
        balances.append(provider)

        var removed = UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? []
        removed.removeAll(where: { $0 == provider.id })
        UserDefaults.standard.set(removed, forKey: "RemovedProviders")

        providerStatus[provider.id] = isConnected(provider.id) ? "Connected · refreshes every 5 minutes" : "Connect in Settings"
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
        providerStatus[finalID] = hasAuth ? "Connected · refreshes every 5 minutes" : "Connect in Settings"
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
        providerStatus[providerID] = "Connecting…"
        save()
        Task { await refreshProvider(providerID) }
    }
    func setMergeIcons(_ enabled: Bool) {
        guard mergeIcons != enabled else { return }
        mergeIcons = enabled
        UserDefaults.standard.set(enabled, forKey: "MergeProviderIcons")
        configureStatusItems()
        writeDiagnostics()
    }
    func selectMergedProvider(_ provider: String) {
        guard provider == "overview" || balances.contains(where: { $0.id == provider }) else { return }
        mergedProvider = provider
        UserDefaults.standard.set(provider, forKey: "MergedProvider")
        updateTitles()
        writeDiagnostics()
    }
    @Published var providerStatus: [String:String] = [:]
    @Published var isBraveInstalled: Bool = BraveSessionImporter.isBraveInstalled()
    @Published var isBraveAccessBlocked: Bool = BraveSessionImporter.isAccessBlocked()
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
        if !BraveSessionImporter.isBraveInstalled() {
            return "Brave Browser was not found in Applications."
        }
        if BraveSessionImporter.isAccessBlocked() {
            return "macOS blocked access to Brave. Click 'Choose Brave Profile…' to grant access."
        }
        let profiles = BraveSessionImporter.availableProfiles()
        if let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let last = URL(fileURLWithPath: path).lastPathComponent
            let name = profiles.first(where: { $0.id == last })?.displayName ?? last
            return "Selected \(name). Connect each provider below."
        }
        return "Select the profile you use to sign in."
    }()
    var clients: [String:SessionHTTP] = [:]
    @Published var inFlight = Set<String>()
    var lastRefresh: Date?
    var items: [NSStatusItem] = []
    var timer: Timer?
    var appError: String?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var mergedMenuView: MergedMenuView?
    let dataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("APIBar/balances.json")
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings()
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
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
                if initialMap[s.id] != nil {
                    var b = s
                    if b.id == "aistudio" || b.name == "AI Studio" || b.name.isEmpty {
                        b.name = "Google AI Studio"
                    }
                    ordered.append(b)
                }
            }
            let removed = Set(UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? [])
            for initial in Balance.initial {
                if !ordered.contains(where: { $0.id == initial.id }) && !removed.contains(initial.id) {
                    ordered.append(initial)
                }
            }
            var changed = ordered.map(\.id) != saved.map(\.id)
            balances = ordered
            for i in balances.indices {
                if balances[i].id == "aistudio" && balances[i].name != "Google AI Studio" {
                    balances[i].name = "Google AI Studio"
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
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let openSettings = NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ",")
        openSettings.target = self; appMenu.addItem(openSettings)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit API Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu; mainMenu.addItem(appMenuItem)
        for b in balances {
            if b.live || (try? KeychainVault.load(b.id)) != nil || (b.dynamicAuthHeader != nil && !b.dynamicAuthHeader!.isEmpty) {
                providerStatus[b.id] = "Connected · refreshes every 5 minutes"
            } else {
                providerStatus[b.id] = "Connect in Settings"
            }
        }
        NSApp.mainMenu = mainMenu
        configureStatusItems()
        updateTitles()
        writeDiagnostics()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.updateTitles()
            if self.lastRefresh.map({ Date().timeIntervalSince($0) >= 300 }) != false { await self.refreshAll() }
        } }
        Task { await refreshAll() }
        if !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboarding()
            }
        }
    }
    func configureStatusItems() {
        for item in items { NSStatusBar.system.removeStatusItem(item) }
        items.removeAll()
        mergedMenuView = nil
        let identities = mergeIcons ? ["merged"] : balances.map(\.id)
        for identity in identities {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = identity
            item.button?.setAccessibilityIdentifier(identity)
            let name = identity == "merged" ? "All providers" : balances.first(where: { $0.id == identity })!.name
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
            item.isVisible = true
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
            let diagnostics: [String: Any] = ["appName": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "", "bundleID": Bundle.main.bundleIdentifier ?? "", "activationPolicy": NSApp.activationPolicy().rawValue, "buttonFrames": items.map { NSStringFromRect($0.button?.frame ?? .zero) }, "windowFrames": items.map { NSStringFromRect($0.button?.window?.frame ?? .zero) }, "statusItemCount": items.count, "mergeIcons": mergeIcons, "mergedProvider": mergedProvider, "autosaveNames": items.map { $0.autosaveName ?? "" }, "accessibilityIdentifiers": items.map { $0.button?.accessibilityIdentifier() ?? "" }, "accessibilityLabels": items.map { $0.button?.accessibilityLabel() ?? "" }, "accessibilityValues": items.map { $0.button?.accessibilityValue() as? String ?? "" }, "imageSizes": items.map { [Double($0.button?.image?.size.width ?? 0), Double($0.button?.image?.size.height ?? 0)] }, "imageTemplates": items.map { $0.button?.image?.isTemplate ?? false }, "titles": items.compactMap { $0.button?.title }, "fontNames": items.compactMap { $0.button?.font?.fontName }, "fontSizes": items.compactMap { $0.button?.font?.pointSize }, "visible": items.map(\.isVisible), "loginStatus": String(describing: SMAppService.mainApp.status), "providerStatus": providerStatus, "backgroundRefreshFinished": lastRefresh != nil, "credentialPrompts": "explicit-connect-only", "menuTitles": items.compactMap { $0.menu?.items.map(\.title) }]
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
        if provider == "vertex" { return try await GoogleProvider(http:client,account:balance.account).fetchBalance() }
        if balance.dynamicEndpoint != nil {
            return try await DynamicProvider(http: client, balance: balance).fetchBalance()
        }
        return try await GoogleProvider(http:client,account:balance.account).fetchBalance()
    }
    func refreshAll() async {
        lastRefresh = Date()
        for balance in balances {
            guard !inFlight.contains(balance.id) else { continue }
            inFlight.insert(balance.id)
            do {
                let client: SessionHTTP
                if let existing = clients[balance.id] { client = existing }
                else if let auth = balance.dynamicAuthHeader, !auth.isEmpty {
                    let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                    client = SessionHTTP(provider: balance.id, cookies: [], dynamicHost: host)
                    clients[balance.id] = client
                } else {
                    let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                    client = try SessionHTTP.load(provider: balance.id, dynamicHost: host, cookieDomain: balance.dynamicCookieDomain)
                    clients[balance.id] = client
                }
                let reading = try await fetch(balance.id,client:client)
                apply(reading)
            } catch {
                let provName: String
                switch balance.id {
                case "fireworks": provName = "app.fireworks.ai"
                case "vertex": provName = "Google Cloud"
                case "aistudio": provName = "Google AI Studio"
                case "cerebras": provName = "Cerebras Cloud"
                case "refuseless": provName = "Refuseless"
                case "crowbot": provName = "Crowbot"
                default: provName = balance.name
                }
                let wasConnected = isConnected(balance.id) || balance.live || (try? KeychainVault.load(balance.id)) != nil || (balance.dynamicAuthHeader != nil && !balance.dynamicAuthHeader!.isEmpty)
                if error.localizedDescription.contains("expired") || error.localizedDescription.contains("sign in") {
                    if wasConnected {
                        providerStatus[balance.id] = "Session expired · sign in to \(provName) in Brave"
                    } else {
                        providerStatus[balance.id] = "Connect in Settings to refresh"
                    }
                } else if wasConnected {
                    providerStatus[balance.id] = "Connected · \(error.localizedDescription)"
                } else {
                    providerStatus[balance.id] = "Connect in Settings to refresh"
                }
            }
            inFlight.remove(balance.id)
        }
        updateTitles()
        writeDiagnostics()
    }
    func refreshBraveProfiles() {
        isBraveInstalled = BraveSessionImporter.isBraveInstalled()
        isBraveAccessBlocked = BraveSessionImporter.isAccessBlocked()
        availableBraveProfiles = BraveSessionImporter.availableProfiles()
        if !isBraveInstalled {
            braveProfileStatus = "Brave Browser was not found in Applications."
            return
        }
        if isBraveAccessBlocked {
            braveProfileStatus = "macOS blocked access to Brave. Click 'Choose Brave Profile…' to grant access."
            return
        }
        if let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let last = URL(fileURLWithPath: path).lastPathComponent
            if availableBraveProfiles.contains(where: { $0.id == last }) {
                selectedBraveProfileID = last
                let name = availableBraveProfiles.first(where: { $0.id == last })?.displayName ?? last
                braveProfileStatus = "Selected \(name). Connect each provider below."
                return
            }
        }
        if !availableBraveProfiles.contains(where: { $0.id == selectedBraveProfileID }), let first = availableBraveProfiles.first {
            selectedBraveProfileID = first.id
        }
        let currentName = availableBraveProfiles.first(where: { $0.id == selectedBraveProfileID })?.displayName ?? selectedBraveProfileID
        braveProfileStatus = "Selected \(currentName). Connect each provider below."
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
        panel.title = "Grant Access to Brave Browser"
        panel.message = "Select your 'Brave-Browser' folder (or a profile folder like 'Default') to allow API Bar to import your sessions."
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
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BraveSoftware")
        }

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try BraveSessionImporter.rememberProfile(url)
                refreshBraveProfiles()
                braveProfileStatus = "Access granted to Brave. Connect each provider below."
            } catch {
                alert("Could not select Brave folder", error.localizedDescription)
            }
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func connect(_ provider: String) {
        guard !inFlight.contains(provider) else { return }
        inFlight.insert(provider); providerStatus[provider] = "Connecting…"
        Task {
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
                let reading = try await fetch(provider,client:client)
                clients[provider] = client; apply(reading)
            } catch {
                providerStatus[provider] = error.localizedDescription
                refreshBraveProfiles()
                if let b = balances.first(where: { $0.id == provider }) {
                    openDashboard(b)
                }
                if isBraveAccessBlocked || error.localizedDescription.contains("blocked access to Brave") {
                    let alert = NSAlert()
                    alert.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
                    alert.messageText = "Brave Access Blocked by macOS"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "Grant Folder Access…")
                    alert.addButton(withTitle: "Full Disk Access Settings…")
                    alert.addButton(withTitle: "Cancel")
                    NSApp.activate(ignoringOtherApps: true)
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        chooseBraveProfile()
                    } else if response == .alertSecondButtonReturn {
                        openFullDiskAccessSettings()
                    }
                } else {
                    alert("Could not connect", error.localizedDescription)
                }
            }
            inFlight.remove(provider); updateTitles()
        }
    }
    func connectAll() {
        Task {
            var errors: [String] = []
            for balance in balances {
                guard !inFlight.contains(balance.id) else { continue }
                inFlight.insert(balance.id); providerStatus[balance.id] = "Connecting…"
                updateTitles()
                do {
                    let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                    let client: SessionHTTP
                    if let auth = balance.dynamicAuthHeader, !auth.isEmpty {
                        client = SessionHTTP(provider: balance.id, cookies: [], dynamicHost: host)
                    } else {
                        let cookieDomain = balance.dynamicCookieDomain
                        client = try await Task.detached {
                            try SessionHTTP.connect(provider: balance.id, cookieDomain: cookieDomain, dynamicHost: host, interactive: true)
                        }.value
                    }
                    let reading = try await fetch(balance.id, client: client)
                    clients[balance.id] = client; apply(reading)
                } catch {
                    providerStatus[balance.id] = error.localizedDescription
                    errors.append("\(balance.name): \(error.localizedDescription)")
                    openDashboard(balance)
                }
                inFlight.remove(balance.id); updateTitles()
            }
            if !errors.isEmpty {
                refreshBraveProfiles()
                if isBraveAccessBlocked || errors.contains(where: { $0.contains("blocked access to Brave") }) {
                    let alert = NSAlert()
                    alert.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
                    alert.messageText = "Brave Access Blocked by macOS"
                    alert.informativeText = errors.joined(separator: "\n\n")
                    alert.addButton(withTitle: "Grant Folder Access…")
                    alert.addButton(withTitle: "Full Disk Access Settings…")
                    alert.addButton(withTitle: "Cancel")
                    NSApp.activate(ignoringOtherApps: true)
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        chooseBraveProfile()
                    } else if response == .alertSecondButtonReturn {
                        openFullDiskAccessSettings()
                    }
                } else {
                    alert("Connect All", errors.joined(separator: "\n\n"))
                }
            }
        }
    }
    func isConnected(_ provider: String) -> Bool {
        guard let b = balances.first(where: { $0.id == provider }) else { return false }
        if let status = providerStatus[provider] {
            if status.contains("Connect in Settings") || status.contains("Disconnected") || status.contains("expired") || status.hasPrefix("Not connected") {
                return false
            }
            if status.hasPrefix("Connected") { return true }
        }
        if b.live && providerStatus[provider]?.hasPrefix("Connected") != false { return true }
        if let auth = b.dynamicAuthHeader, !auth.isEmpty { return true }
        if (try? KeychainVault.load(provider)) != nil && providerStatus[provider]?.contains("Connect in Settings") != true { return true }
        return false
    }
    func disconnect(_ provider: String) {
        guard !inFlight.contains(provider) else { return }
        clients.removeValue(forKey:provider); KeychainVault.clear(provider)
        providerStatus[provider] = "Disconnected"
        if let i = balances.firstIndex(where:{$0.id == provider}) { balances[i].live = false }
        save(); updateTitles()
    }
    func apply(_ r: Reading) {
        guard ReadingValidation.valid(r,balances:balances), let i = balances.firstIndex(where:{$0.id == r.provider}) else { providerStatus[r.provider] = "A balance from a different account or source was rejected."; return }
        if balances[i].account.isEmpty { balances[i].account = r.account }
        let oldRemaining = balances[i].remaining
        balances[i].remaining = r.remaining; balances[i].updated = Date(); balances[i].live = true; balances[i].expires = r.expires
        // Automatic 100% reference calculation:
        // When remaining balance increases while previous remaining > 0,
        // infer the paid tier from the delta and add it to the previous remaining.
        // e.g. remaining was $3.00, user paid $5.00 -> new recognized total is $8.00.
        if balances[i].baseline <= 0 {
            let ref = r.reference ?? PaymentReference.inferTier(for: r.remaining)
            balances[i].baseline = max(ref, r.remaining)
        } else if let ref = r.reference, ref > balances[i].baseline {
            balances[i].baseline = ref
        } else if r.remaining > oldRemaining && oldRemaining > 0 {
            let delta = r.remaining - oldRemaining
            let paidAmount = PaymentReference.inferTier(for: delta)
            balances[i].baseline = max(oldRemaining + paidAmount, r.remaining)
        }
        providerStatus[r.provider] = "Connected · refreshes every 5 minutes"
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
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(balances)
            try bytes.write(to: dataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
        } catch { appError = "Could not save balances: \(error.localizedDescription)" }
    }
    func updateTitles() {
        for (i, b) in (mergeIcons ? [selectedMergedBalance] : balances).enumerated() where i < items.count {
            if mergeIcons && mergedProvider == "overview" {
                let usdRemaining = balances.filter { $0.id != "refuseless" }.reduce(0.0) { $0 + $1.remaining }
                let usdBaseline = balances.filter { $0.id != "refuseless" }.reduce(0.0) { $0 + $1.baseline }
                let creditsRemaining = balances.filter { $0.id == "refuseless" }.reduce(0.0) { $0 + $1.remaining }
                let totalPercent = usdBaseline > 0 ? max(0, usdRemaining / usdBaseline * 100) : 0
                let percentText = "\(Int(floor(totalPercent)))%"
                items[i].button?.title = percentText
                items[i].button?.image = ProviderIcon.menuBarImage("overview")
                let summary = creditsRemaining > 0
                    ? "\(usdRemaining.formatted(.currency(code: "USD"))) + \(Int(creditsRemaining)) credits"
                    : usdRemaining.formatted(.currency(code: "USD"))
                items[i].button?.toolTip = "Overview: \(summary) · \(percentText) · \(balances.filter { isConnected($0.id) }.count) connected"
                items[i].button?.setAccessibilityValue("\(percentText) remaining across all providers")
            } else {
                items[i].button?.title = b.percentageLabel
                items[i].button?.image = ProviderIcon.menuBarImage(b.id)
                items[i].button?.toolTip = "\(b.name): \(b.money) · \(b.percentageLabel) · \(providerStatus[b.id] ?? "Waiting for first refresh")"
                items[i].button?.setAccessibilityValue("\(b.percentageLabel) remaining\(b.stale ? ", stale" : "")")
            }
        }
        mergedMenuView?.refresh()
    }
    func menuWillOpen(_ menu: NSMenu) {
        if menu.identifier?.rawValue == "merged" {
            menu.removeAllItems()
            menu.minimumWidth = 330
            let card = NSMenuItem()
            let content = MergedMenuView(app: self)
            mergedMenuView = content
            card.view = content
            menu.addItem(card)
            menu.addItem(.separator())
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
            menu.addItem(.separator())
            action(menu, "Quit API Bar", #selector(quit), 0, "power").keyEquivalent = "q"
            return
        }
        guard let index = balances.firstIndex(where: { $0.id == menu.identifier?.rawValue }) else { return }
        let b = balances[index]
        menu.removeAllItems()
        menu.minimumWidth = 330
        let card = NSMenuItem(); card.view = BalanceCard(b,status:providerStatus[b.id]); menu.addItem(card)
        menu.addItem(.separator())
        if let error = appError { disabled(menu, "Save error: \(error)") }
        let detail = NSMenuItem(title: "Usage Details", action: nil, keyEquivalent: "")
        detail.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil)
        let submenu = NSMenu()
        disabled(submenu, "Account: \(b.account)")
        disabled(submenu, "100% = \(b.id == "refuseless" ? "\(Int(b.baseline)) credits" : b.baseline.formatted(.currency(code: "USD")))")
        disabled(submenu, "Checked \(relativeTimeString(for: b.updated))")
        if let expires = b.expires { disabled(submenu, "Expires \(expires)") }
        disabled(submenu, "Calculated from last verified balance")
        detail.submenu = submenu; menu.addItem(detail)
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
        do {
            let client: SessionHTTP
            if let existing = clients[balance.id] { client = existing }
            else if let auth = balance.dynamicAuthHeader, !auth.isEmpty {
                let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                client = SessionHTTP(provider: balance.id, cookies: [], dynamicHost: host)
                clients[balance.id] = client
            } else {
                let host = balance.dynamicEndpoint.flatMap { URL(string: $0)?.host }
                client = try SessionHTTP.load(provider: balance.id, dynamicHost: host, cookieDomain: balance.dynamicCookieDomain)
                clients[balance.id] = client
            }
            let reading = try await fetch(balance.id, client: client)
            apply(reading)
        } catch {
            let provName: String
            switch balance.id {
            case "fireworks": provName = "app.fireworks.ai"
            case "vertex": provName = "Google Cloud"
            case "aistudio": provName = "Google AI Studio"
            case "cerebras": provName = "Cerebras Cloud"
            case "refuseless": provName = "Refuseless"
            case "crowbot": provName = "Crowbot"
            default: provName = balance.name
            }
            let wasConnected = isConnected(balance.id) || balance.live || (try? KeychainVault.load(balance.id)) != nil || (balance.dynamicAuthHeader != nil && !balance.dynamicAuthHeader!.isEmpty)
            if error.localizedDescription.contains("expired") || error.localizedDescription.contains("sign in") {
                if wasConnected {
                    providerStatus[balance.id] = "Session expired · sign in to \(provName) in Brave"
                } else {
                    providerStatus[balance.id] = "Connect in Settings to refresh"
                }
            } else if wasConnected {
                providerStatus[balance.id] = "Connected · \(error.localizedDescription)"
            } else {
                providerStatus[balance.id] = "Connect in Settings to refresh"
            }
        }
    }
    @objc func refreshMergedProvider() {
        if mergedProvider == "overview" {
            Task { await refreshAll() }
        } else {
            Task { await refreshProvider(selectedMergedBalance.id) }
        }
    }
    @objc func refreshSingleProvider(_ sender: NSMenuItem) {
        guard balances.indices.contains(sender.tag) else { return }
        let id = balances[sender.tag].id
        Task { await refreshProvider(id) }
    }
    @objc func refresh() { Task { await refreshAll() } }
    @objc func settings() {
        NSApp.setActivationPolicy(.regular)
        if let settingsWindow {
            settingsWindow.deminiaturize(nil)
            settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            writeDiagnostics(); return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 620), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "API Bar Settings"; window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsPane(app: self))
        window.center(); window.makeKeyAndOrderFront(nil); settingsWindow = window; NSApp.activate(ignoringOtherApps: true)
        writeDiagnostics()
    }
    @objc func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        if let onboardingWindow {
            onboardingWindow.deminiaturize(nil)
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
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
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === onboardingWindow { onboardingWindow = nil }
        if settingsWindow == nil && onboardingWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
        writeDiagnostics()
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
            if let first = balances.first {
                openDashboard(first)
            }
        } else {
            openDashboard(selectedMergedBalance)
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
        case "refuseless": return URL(string: "https://refuseless.com/dashboard")!
        default: return URL(string: "https://console.cloud.google.com/billing/\(b.account)/credits/all")!
        }
    }
    func openDefaultBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
    func openInBrave(_ url: URL) {
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
        a.informativeText = "Connect each provider from Settings after signing in to its billing page in Brave. Imported sessions are kept in macOS Keychain; background refresh does not need Brave or an open tab.\n\nFireworks balance detection has been verified. Google Cloud credit detection has been verified against its billing dashboard. Failed requests keep the last successful balance.\n\nOnly Connect can ask for Keychain approval. Rebuilding this locally signed app may require reconnecting."
        a.addButton(withTitle: "Open Billing Pages"); a.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        let result = a.runModal()
        if result == .alertFirstButtonReturn { balances.forEach { openInBrave(billingURL($0)) } }
    }
    @objc func about() { alert("API Bar 0.4.7", "A small companion for account-wide Vertex AI, Fireworks, Crowbot, Google AI Studio, Cerebras, and Refuseless credits. Menu bar percentages, balance details, baseline settings, and Start at Login.\n\nConnect in Settings to refresh account balances using sessions stored in macOS Keychain. Failed requests keep the last successful balance. Background refresh never requests Keychain approval.\n\nMenu styling and provider symbols follow CodexBar. Independent app; not affiliated with CodexBar, Google, Fireworks, or Cerebras.") }
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

