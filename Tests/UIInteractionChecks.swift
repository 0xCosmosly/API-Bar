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
        for (provider, rep) in [("mark", reps[0])] + ["overview", "vertex", "fireworks", "crowbot", "aistudio", "cerebras", "refuseless"].flatMap({ id in ProviderIcon.image(id).representations.compactMap { rep in (id, rep as! NSBitmapImageRep) } }) {
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                if rep.colorAt(x: x, y: y)!.alphaComponent > 0.4 { xs.append(x); ys.append(y) }
            }}
            precondition(!xs.isEmpty && xs.max()! - xs.min()! > rep.pixelsWide * 7 / 10)
            let minH = (provider == "fireworks" || provider == "refuseless") ? rep.pixelsHigh * 35 / 100 : rep.pixelsHigh * 6 / 10
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

        print("Passed: 900 tab clicks across icons/text/padding, canceled drags, accessibility actions, persistent selector, and Retina brand representations.")
        print("Passed: removeProvider, addProvider, menu order Dashboard -> Refresh -> Refresh All -> Start at Login -> Settings, relative checked time, and harnesses line removed.")
        print("Passed: AFM on-device extraction from cURL/JSON, dynamic provider registration, monogram rendering, and cleanup.")
        print("Passed: Venice AI consumptionCurrency-aware single-digit balance extraction (USD & DIEM), Bearer auth, custom registration, and monogram verification.")
        print("Passed: AFM auto-add by provider name with automated usage dashboard URL resolution and credential probe.")
    }
}
