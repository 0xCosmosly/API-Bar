import AppKit

@main struct UIInteractionChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let app = APIBarApp()
        app.setSortMode(.manual)
        app.balances = Balance.initial
        let view = MergedMenuView(app: app)
        app.mergedMenuView = view
        view.updateProviders(app.balances)
        let tabs = view.tabs
        precondition(tabs.acceptsFirstMouse(for: nil))
        for _ in 0..<100 {
            for (index, button) in tabs.buttons.enumerated() {
                // Text, icon, and empty tab padding all belong to the same hit target.
                for point in [NSPoint(x: button.frame.midX, y: button.frame.midY), NSPoint(x: button.frame.minX + 1, y: button.frame.minY + 1), NSPoint(x: button.frame.maxX - 1, y: button.frame.maxY - 1)] {
                    tabs.press(at: point); tabs.release(at: point)
                    precondition(app.mergedProvider == tabs.items[index].id)
                    precondition(tabs.buttons[index].state == .on)
                }
                let selected = app.mergedProvider
                // A drag released elsewhere must not activate a different provider.
                tabs.press(at: NSPoint(x: button.frame.midX, y: button.frame.midY))
                tabs.release(at: NSPoint(x: -10, y: -10))
                precondition(app.mergedProvider == selected)
                tabs.release(at: NSPoint(x: button.frame.midX, y: button.frame.midY))
                precondition(app.mergedProvider == selected)
            }
        }
        tabs.buttons[0].performClick(nil)
        precondition(app.mergedProvider == "overview")
        tabs.buttons[1].performClick(nil)
        precondition(app.mergedProvider == "vertex")
        tabs.buttons[2].performClick(nil)
        precondition(app.mergedProvider == "fireworks")
        precondition(view.tabs === tabs, "Provider switch replaced the live click target")
        let reps = BrandMark.image().representations.compactMap { $0 as? NSBitmapImageRep }
        precondition(reps.map(\.pixelsWide) == [18, 36, 54] && BrandMark.image().isTemplate)
        for (provider, rep) in [("mark", reps[0])] + ["overview", "vertex", "fireworks", "crowbot", "aistudio", "cerebras", "refuseless", "lutheos"].flatMap({ id in ProviderIcon.image(id).representations.compactMap { rep in (id, rep as! NSBitmapImageRep) } }) {
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                if rep.colorAt(x: x, y: y)!.alphaComponent > 0.4 { xs.append(x); ys.append(y) }
            }}
            precondition(!xs.isEmpty && xs.max()! - xs.min()! > rep.pixelsWide * 7 / 10)
            let minH = (provider == "fireworks" || provider == "refuseless" || provider == "lutheos") ? rep.pixelsHigh * 35 / 100 : rep.pixelsHigh * 6 / 10
            precondition(!ys.isEmpty && ys.max()! - ys.min()! > minH, "Retina brand clipped by a mixed AppKit/CoreGraphics transform")
        }
        precondition(view.frame.height <= tabs.frame.height + 200, "Merged menu retained the empty credits footer")

        // Test removeProvider and addProvider
        let initialCount = app.balances.count
        app.selectMergedProvider("refuseless")
        precondition(app.mergedProvider == "refuseless")
        app.removeProvider(id: "refuseless")
        precondition(app.balances.count == initialCount - 1)
        precondition(!app.balances.contains(where: { $0.id == "refuseless" }))
        precondition(app.mergedProvider == "overview", "Removed active provider did not reset to overview")
        precondition(UserDefaults.standard.stringArray(forKey: "RemovedProviders")?.contains("refuseless") == true)

        let refuselessInitial = Balance.initial.first(where: { $0.id == "refuseless" })!
        app.addProvider(refuselessInitial)
        precondition(app.balances.count == initialCount)
        precondition(app.balances.contains(where: { $0.id == "refuseless" }))
        precondition(UserDefaults.standard.stringArray(forKey: "RemovedProviders")?.contains("refuseless") == false)

        // Test provider tab gauge tracking and shrinking with less tokens
        let fwIndex = tabs.items.firstIndex(where: { $0.id == "fireworks" })!
        if let fwIdxInBalances = app.balances.firstIndex(where: { $0.id == "fireworks" }) {
            app.balances[fwIdxInBalances].baseline = 100
            app.balances[fwIdxInBalances].remaining = 42.0
            view.updateProviders(app.balances)
            let updatedFwPercent = tabs.items[fwIndex].percent
            precondition(updatedFwPercent == 42.0, "Provider tab bar percent did not update with remaining tokens")
            let fwButton = tabs.buttons[fwIndex] as! ProviderTabButton
            precondition(fwButton.tabItem.percent == 42.0, "Provider tab button did not receive updated percent")

            // Lower tokens even further
            app.balances[fwIdxInBalances].remaining = 5.0
            view.updateProviders(app.balances)
            precondition(tabs.items[fwIndex].percent == 5.0, "Provider tab percent did not shrink with less tokens")
            precondition(fwButton.tabItem.percent == 5.0)
        }

        // Test OverviewCardContent totalUsdRemaining calculation includes Refuseless as dollars
        if let rIdx = app.balances.firstIndex(where: { $0.id == "refuseless" }) {
            app.balances[rIdx].baseline = 100
            app.balances[rIdx].remaining = 50.0
            let overviewContent = OverviewCardContent(app: app)
            precondition(!overviewContent.totalSummaryText.contains("credits"), "Overview total must not count credits")
            precondition(overviewContent.totalUsdRemaining >= 50.0, "Overview total USD must include Refuseless dollar amount")

            // Test 1-account overview percentage matching provider percentageLabel
            let savedBalances = app.balances
            let singleBal = Balance(id: "refuseless", name: "Refuseless", baseline: 25.0, remaining: 0.73313, updated: Date(), account: "user@example.com", live: true)
            app.balances = [singleBal]
            let singleOverview = OverviewCardContent(app: app)
            precondition(singleOverview.aggregatePercentText == singleBal.percentageLabel, "Single account aggregate percent (\(singleOverview.aggregatePercentText)) must match provider percentageLabel (\(singleBal.percentageLabel))")
            precondition(singleOverview.aggregatePercentText == "2%", "Expected 2% for 0.73/25, got \(singleOverview.aggregatePercentText)")
            app.balances = savedBalances
        }

        // Test menu item ordering and titles in merged menu
        let mergedMenu = NSMenu()
        mergedMenu.identifier = NSUserInterfaceItemIdentifier("merged")
        app.menuWillOpen(mergedMenu)
        let mergedTitles = mergedMenu.items.map(\.title)
        guard let mDashIdx = mergedTitles.firstIndex(of: "Dashboard…"),
              let mRefIdx = mergedTitles.firstIndex(of: "Refresh"),
              let mRefAllIdx = mergedTitles.firstIndex(of: "Refresh All"),
              let mLoginIdx = mergedTitles.firstIndex(of: "Start at Login"),
              let mSettingsIdx = mergedTitles.firstIndex(of: "Settings…") else {
            preconditionFailure("Merged menu missing expected items: \(mergedTitles)")
        }
        precondition(mDashIdx < mRefIdx, "Dashboard must be above Refresh in merged menu")
        precondition(mRefIdx < mRefAllIdx, "Refresh must be above Refresh All in merged menu")
        precondition(mRefAllIdx < mLoginIdx, "Refresh All must be above Start at Login in merged menu")
        precondition(mLoginIdx < mSettingsIdx, "Start at Login must be above Settings in merged menu")

        // Test menu item ordering and details in separated menu
        let sepMenu = NSMenu()
        sepMenu.identifier = NSUserInterfaceItemIdentifier("vertex")
        app.menuWillOpen(sepMenu)
        let sepTitles = sepMenu.items.map(\.title)
        guard let sDashIdx = sepTitles.firstIndex(of: "Dashboard…"),
              let sRefIdx = sepTitles.firstIndex(of: "Refresh"),
              let sRefAllIdx = sepTitles.firstIndex(of: "Refresh All"),
              let sLoginIdx = sepTitles.firstIndex(of: "Start at Login"),
              let sSettingsIdx = sepTitles.firstIndex(of: "Settings…") else {
            preconditionFailure("Separated menu missing expected items: \(sepTitles)")
        }
        precondition(sDashIdx < sRefIdx, "Dashboard must be above Refresh in separated menu")
        precondition(sRefIdx < sRefAllIdx, "Refresh must be above Refresh All in separated menu")
        precondition(sRefAllIdx < sLoginIdx, "Refresh All must be above Start at Login in separated menu")
        precondition(sLoginIdx < sSettingsIdx, "Start at Login must be above Settings in separated menu")

        let usageDetails = sepMenu.items.first(where: { $0.title == "Usage Details" })
        let subTitles = usageDetails?.submenu?.items.map(\.title) ?? []
        precondition(!subTitles.contains(where: { $0.contains("all harnesses") }), "Usage Details must not contain 'all harnesses'")
        precondition(subTitles.contains(where: { $0.hasPrefix("Checked ") }), "Usage Details must contain relative time Checked line")

        // Test AFM on-device provider extraction
        let curlSample = "curl 'https://api.groq.com/openai/v1/models' -H 'Authorization: Bearer gsk_test'"
        let draftFromCurl = try AFMProviderExtractor.extract(from: curlSample)
        precondition(draftFromCurl.name == "Groq", "AFM did not extract Groq name from cURL")
        precondition(draftFromCurl.cookieDomain == "groq.com", "AFM did not extract groq.com domain")
        precondition(draftFromCurl.authHeader == "Bearer gsk_test", "AFM did not extract Bearer token")

        let jsonSample = """
        {
            "object": "billing_info",
            "data": {
                "remaining_credits": 14.50
            },
            "currency": "USD"
        }
        """
        let draftFromJson = try AFMProviderExtractor.extract(from: jsonSample)
        precondition(draftFromJson.jsonPath == "data.remaining_credits", "AFM did not locate data.remaining_credits")
        precondition(draftFromJson.detectedBalance == 14.50, "AFM did not extract 14.50 balance")
        precondition(draftFromJson.baseline == 15.0, "AFM did not infer $15 tier for $14.50")

        // Test dynamic custom provider registration
        let customCountBefore = app.balances.count
        app.addCustomProvider(draftFromCurl)
        precondition(app.balances.count == customCountBefore + 1)
        guard let addedCustom = app.balances.first(where: { $0.id == "groq" }) else {
            preconditionFailure("Custom provider 'groq' was not added")
        }
        precondition(addedCustom.name == "Groq")
        precondition(addedCustom.dynamicEndpoint == draftFromCurl.endpoint)
        precondition(addedCustom.dynamicAuthHeader == "Bearer gsk_test")
        precondition(app.isConnected("groq") == true)

        // Test monogram icon generation for custom provider
        let customIcon = ProviderIcon.image("groq")
        precondition(customIcon.representations.count >= 1, "Custom provider monogram icon has no representations")
        let customMenuBarIcon = ProviderIcon.menuBarImage("groq")
        precondition(customMenuBarIcon.isTemplate == false, "Custom provider menu bar icon must be white non-template")

        // Clean up custom provider
        app.removeProvider(id: "groq")
        precondition(app.balances.count == customCountBefore)

        // Test Venice AI extraction and registration
        let veniceURLSample = "https://venice.ai/settings/api"
        let draftVenice = try AFMProviderExtractor.extract(from: veniceURLSample)
        precondition(draftVenice.name == "Venice AI", "Venice AI name not detected")
        precondition(draftVenice.endpoint == "https://api.venice.ai/api/v1/billing/balance", "Venice endpoint not detected")
        precondition(draftVenice.jsonPath == "balances.usd", "Venice balances.usd path not detected")
        precondition(draftVenice.cookieDomain == "venice.ai", "Venice cookie domain not detected")
        precondition(draftVenice.detectedBalance == 0.0, "Venice draft balance from URL should default to 0.0, got \(draftVenice.detectedBalance)")

        let veniceJSONSample = """
        {
            "canConsume": true,
            "consumptionCurrency": "USD",
            "balances": {
                "usd": 3.50,
                "diem": 100.0,
                "bundledCredits": 0.0,
                "earnedCredits": 0.0
            },
            "diemEpochAllocation": 100.0
        }
        """
        let draftVeniceJSON = try AFMProviderExtractor.extract(from: "curl 'https://api.venice.ai/api/v1/billing/balance' -H 'Authorization: Bearer venice_admin_key_123'\n" + veniceJSONSample)
        precondition(draftVeniceJSON.name == "Venice AI")
        precondition(draftVeniceJSON.detectedBalance == 3.50, "Venice USD balance 3.50 not extracted, got \(draftVeniceJSON.detectedBalance)")
        precondition(draftVeniceJSON.jsonPath == "balances.usd", "Venice JSON path not balances.usd")
        precondition(draftVeniceJSON.baseline == 5.0, "Venice baseline 5.0 not inferred, got \(draftVeniceJSON.baseline)")
        precondition(draftVeniceJSON.authHeader == "Bearer venice_admin_key_123", "Venice Bearer token not extracted")

        // Test Venice AI with DIEM consumption
        let veniceDiemJSONSample = """
        {
            "canConsume": true,
            "consumptionCurrency": "DIEM",
            "balances": {
                "usd": 0.0,
                "diem": 75.0,
                "bundledCredits": 0.0,
                "earnedCredits": 0.0
            },
            "diemEpochAllocation": 100.0
        }
        """
        let draftVeniceDiem = try AFMProviderExtractor.extract(from: veniceDiemJSONSample)
        precondition(draftVeniceDiem.name == "Venice AI")
        precondition(draftVeniceDiem.detectedBalance == 75.0, "Venice DIEM balance 75.0 not extracted, got \(draftVeniceDiem.detectedBalance)")
        precondition(draftVeniceDiem.jsonPath == "balances.diem", "Venice JSON path not balances.diem")
        precondition(draftVeniceDiem.baseline == 100.0, "Venice epoch baseline 100.0 not extracted, got \(draftVeniceDiem.baseline)")

        // Test Venice AI with $0 USD balance
        let veniceZeroJSONSample = """
        {
            "canConsume": true,
            "consumptionCurrency": "USD",
            "balances": {
                "usd": 0.0,
                "diem": 100.0,
                "bundledCredits": 0.0,
                "earnedCredits": 0.0
            },
            "diemEpochAllocation": 100.0
        }
        """
        let draftVeniceZero = try AFMProviderExtractor.extract(from: veniceZeroJSONSample)
        precondition(draftVeniceZero.name == "Venice AI")
        precondition(draftVeniceZero.detectedBalance == 0.0, "Venice $0 balance should be 0.0, got \(draftVeniceZero.detectedBalance)")
        precondition(draftVeniceZero.jsonPath == "balances.usd", "Venice $0 balance path should be balances.usd")
        precondition(draftVeniceZero.baseline == 0.0, "Venice baseline for $0 balance should be 0.0, got \(draftVeniceZero.baseline)")

        app.addCustomProvider(draftVeniceZero)
        guard let veniceZeroBal = app.balances.first(where: { $0.id == "venice" }) else {
            preconditionFailure("Venice AI $0 balance was not added")
        }
        precondition(veniceZeroBal.remaining == 0.0)
        precondition(veniceZeroBal.baseline == 0.0)
        app.removeProvider(id: "venice")

        app.addCustomProvider(draftVeniceJSON)
        guard let veniceBalance = app.balances.first(where: { $0.id == "venice" }) else {
            preconditionFailure("Venice AI was not added to balances")
        }
        precondition(veniceBalance.name == "Venice AI")
        precondition(veniceBalance.remaining == 3.50)
        precondition(veniceBalance.baseline == 5.0)
        precondition(veniceBalance.dynamicAuthHeader == "Bearer venice_admin_key_123")
        precondition(veniceBalance.live == true)
        precondition(app.isConnected("venice") == true)
        let veniceIcon = ProviderIcon.image("venice")
        precondition(veniceIcon.representations.count >= 1)
        let veniceMenuBar = ProviderIcon.menuBarImage("venice")
        precondition(!veniceMenuBar.isTemplate)
        app.removeProvider(id: "venice")

        // Test autoAddProvider by provider name
        let (autoVeniceDraft, autoVeniceURL, _) = await AFMProviderExtractor.autoAddProvider(named: "Venice", openBrowser: false)
        precondition(autoVeniceDraft.name == "Venice AI", "autoAddProvider failed to resolve Venice AI")
        precondition(autoVeniceDraft.endpoint == "https://api.venice.ai/api/v1/billing/balance")
        precondition(autoVeniceDraft.jsonPath == "balances.usd")
        precondition(autoVeniceDraft.detectedBalance == 0.0, "autoVeniceDraft balance should be 0.0")
        precondition(autoVeniceDraft.baseline == 0.0, "autoVeniceDraft baseline should be 0.0")
        precondition(autoVeniceURL == "https://venice.ai/settings/api")

        let (autoGroqDraft, autoGroqURL, _) = await AFMProviderExtractor.autoAddProvider(named: "Groq", openBrowser: false)
        precondition(autoGroqDraft.name == "Groq")
        precondition(autoGroqURL == "https://console.groq.com/keys")

        let (autoOpenRouterDraft, autoOpenRouterURL, _) = await AFMProviderExtractor.autoAddProvider(named: "openrouter", openBrowser: false)
        precondition(autoOpenRouterDraft.name == "OpenRouter")
        precondition(autoOpenRouterURL == "https://openrouter.ai/credits")

        // Test iCloud Sync: availability, push, pull & merge, session vault sync, status badges
        var cleanedRemoved = UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? []
        cleanedRemoved.removeAll(where: { $0 == "togetherai" })
        UserDefaults.standard.set(cleanedRemoved, forKey: "RemovedProviders")
        ICloudSync.shared.attach(app: app)
        precondition(ICloudSync.shared.isAvailable == true, "iCloud should be available in test environment with APIBAR_ICLOUD_DIR")
        app.setICloudSyncEnabled(true)
        precondition(ICloudSync.shared.isEnabled == true)
        precondition(app.iCloudSyncEnabled == true)

        // Test OpenCode local config push to iCloud
        let localOpenCodeFile = ICloudSync.shared.localOpenCodeURL
        let initialOpenCodeConfig = "{\"providers\":{\"refuseless\":{\"apiKey\":\"test_refuseless_key\"}}}"
        try initialOpenCodeConfig.write(to: localOpenCodeFile, atomically: true, encoding: .utf8)
        precondition(ICloudSync.shared.isOpenCodeSyncEnabled == true)

        let pushedSuccess = await ICloudSync.shared.pushLocalState()
        precondition(pushedSuccess == true, "pushLocalState failed")
        guard let balancesFile = ICloudSync.shared.balancesURL,
              let settingsFile = ICloudSync.shared.settingsURL,
              let manifestFile = ICloudSync.shared.manifestURL,
              let cloudOpenCodeFile = ICloudSync.shared.cloudOpenCodeURL else {
            preconditionFailure("iCloud URLs not resolved")
        }
        precondition(FileManager.default.fileExists(atPath: balancesFile.path), "balances.json missing in iCloud")
        precondition(FileManager.default.fileExists(atPath: settingsFile.path), "settings.json missing in iCloud")
        precondition(FileManager.default.fileExists(atPath: manifestFile.path), "manifest.json missing in iCloud")
        precondition(FileManager.default.fileExists(atPath: cloudOpenCodeFile.path), "opencode.json missing in iCloud")
        precondition((try? String(contentsOf: cloudOpenCodeFile, encoding: .utf8)) == initialOpenCodeConfig)

        let balancesData = try Data(contentsOf: balancesFile)
        let pushedBalances = try JSONDecoder().decode([Balance].self, from: balancesData)
        precondition(pushedBalances.count == app.balances.count, "Pushed balances count mismatch")
        let settingsData = try Data(contentsOf: settingsFile)
        let pushedSettings = try JSONDecoder().decode(ICloudSettings.self, from: settingsData)
        precondition(pushedSettings.sortMode == app.sortMode.rawValue)
        precondition(pushedSettings.mergeIcons == app.mergeIcons)

        // Simulate remote changes from Device B
        var remoteBalances = pushedBalances
        if let fwIdx = remoteBalances.firstIndex(where: { $0.id == "fireworks" }) {
            remoteBalances[fwIdx].baseline = 150.0
            remoteBalances[fwIdx].updated = Date()
        }
        let remoteCustom = Balance(
            id: "togetherai",
            name: "Together AI",
            baseline: 25.0,
            remaining: 24.50,
            updated: Date(),
            account: "together.xyz",
            live: true,
            dynamicEndpoint: "https://api.together.xyz/v1/balance",
            dynamicAuthHeader: "Bearer test_together_key"
        )
        remoteBalances.append(remoteCustom)
        let newBalancesData = try JSONEncoder().encode(remoteBalances)
        try newBalancesData.write(to: balancesFile, options: .atomic)

        let remoteManifest = ICloudManifest(
            version: 1,
            lastModified: Date(),
            deviceId: "mac-b-device-id",
            deviceName: "MacBook Pro",
            providerCount: remoteBalances.count
        )
        try JSONEncoder().encode(remoteManifest).write(to: manifestFile, options: .atomic)

        let remoteVaultDir = ICloudSync.shared.vaultDirectoryURL!
        try FileManager.default.createDirectory(at: remoteVaultDir, withIntermediateDirectories: true)
        let mockSession = [StoredCookie(name: "session_token", value: "tok_12345", domain: ".together.xyz", expires: nil)]
        let mockSessionData = try JSONEncoder().encode(mockSession)
        try mockSessionData.write(to: remoteVaultDir.appendingPathComponent("togetherai.dat"), options: .atomic)

        // Device B updates opencode.json in iCloud
        let updatedOpenCodeConfig = "{\"providers\":{\"refuseless\":{\"apiKey\":\"test_refuseless_key\"},\"crowbot\":{\"apiKey\":\"test_crowbot_key\"}}}"
        try updatedOpenCodeConfig.write(to: cloudOpenCodeFile, atomically: true, encoding: .utf8)
        let futureDate = Date().addingTimeInterval(10)
        try FileManager.default.setAttributes([.modificationDate: futureDate], ofItemAtPath: cloudOpenCodeFile.path)

        let didMerge = await ICloudSync.shared.pullAndMerge()
        precondition(didMerge == true, "pullAndMerge did not report merge changes")
        guard let mergedFw = app.balances.first(where: { $0.id == "fireworks" }) else {
            preconditionFailure("Fireworks not found after merge")
        }
        precondition(mergedFw.baseline == 150.0, "Fireworks baseline did not update from iCloud: got \(mergedFw.baseline)")
        guard let mergedTogether = app.balances.first(where: { $0.id == "togetherai" }) else {
            preconditionFailure("Together AI was not merged from iCloud")
        }
        precondition(mergedTogether.dynamicEndpoint == "https://api.together.xyz/v1/balance")
        precondition(mergedTogether.dynamicAuthHeader == "Bearer test_together_key")
        precondition(FileManager.default.fileExists(atPath: KeychainVault.vaultDir.appendingPathComponent("togetherai.dat").path), "togetherai session file was not transferred from iCloud to local vault")

        precondition((try? String(contentsOf: localOpenCodeFile, encoding: .utf8)) == updatedOpenCodeConfig, "Local opencode.json did not update with Device B changes")
        let backupFile = localOpenCodeFile.deletingLastPathComponent().appendingPathComponent("opencode.json.bak")
        precondition(FileManager.default.fileExists(atPath: backupFile.path), "opencode.json.bak backup missing")
        precondition((try? String(contentsOf: backupFile, encoding: .utf8)) == initialOpenCodeConfig, "opencode.json.bak content mismatch")

        ICloudSync.shared.setOpenCodeSyncEnabled(false)
        precondition(ICloudSync.shared.isOpenCodeSyncEnabled == false)
        ICloudSync.shared.setOpenCodeSyncEnabled(true)
        precondition(ICloudSync.shared.isOpenCodeSyncEnabled == true)

        precondition(ICloudSync.shared.statusBadge == "Active" || ICloudSync.shared.statusBadge == "Synced")
        precondition(app.iCloudStatusMessage.contains("Synced") || app.iCloudStatusMessage.contains("ago") || app.iCloudStatusMessage.contains("just now"))

        app.setICloudSyncEnabled(false)
        precondition(ICloudSync.shared.isEnabled == false)
        precondition(app.iCloudSyncEnabled == false)
        precondition(ICloudSync.shared.statusBadge == "Off")
        app.removeProvider(id: "togetherai")

        print("Passed: 900 tab clicks across icons/text/padding, canceled drags, accessibility actions, persistent selector, and Retina brand representations.")
        print("Passed: removeProvider, addProvider, menu order Dashboard -> Refresh -> Refresh All -> Start at Login -> Settings, relative checked time, and harnesses line removed.")
        print("Passed: AFM on-device extraction from cURL/JSON, dynamic provider registration, monogram rendering, and cleanup.")
        print("Passed: Venice AI consumptionCurrency-aware single-digit balance extraction (USD & DIEM), Bearer auth, custom registration, and monogram verification.")
        print("Passed: AFM auto-add by provider name with automated usage dashboard URL resolution and credential probe.")
        print("Passed: iCloud sync availability, atomic push, multi-device pull & merge, session vault transfer, and status badges.")
    }
}
