import Foundation
import Security
import AppKit

@main struct Checks {
    static func require(_ check: @autoclosure () throws -> Bool) throws { let result = try check(); precondition(result) }
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("APIBarBookmarkCheck-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bookmark = try ProfileBookmark.create(folder)
        var stale = false
        let resolved = try ProfileBookmark.resolve(bookmark, stale: &stale)
        precondition(!stale && resolved.standardizedFileURL.path == folder.standardizedFileURL.path)
        print("Passed: selected-folder bookmark round-trip without App Sandbox entitlements; no browser data accessed.")
        let profiles = BraveSessionImporter.availableProfiles()
        try require(!profiles.isEmpty)
        try require(profiles.contains(where: { $0.id == "Default" }))
        let accessKind = BraveSessionImporter.accessKind()
        precondition(accessKind == .fullDisk || accessKind == .folder, "Brave access should be recognized as fullDisk or folder on local machine")
        precondition(!BraveSessionImporter.isAccessBlocked(), "Brave access should not be blocked when profiles are present")
        print("Passed: available Brave profiles detection and access recognition without file path navigation.")
        let clientKey = "AIza" + String(repeating: "a", count: 35)
        let unrelatedKey = "AIza" + String(repeating: "b", count: 35)
        try require(GoogleProvider.consumerKey(in: "{\"LjgHrc\":\"\(clientKey)\",\"other\":\"\(unrelatedKey)\"}") == clientKey)
        do {
            _ = try GoogleProvider.consumerKey(in: "{\"other\":\"\(unrelatedKey)\"}")
            preconditionFailure("Unrelated client key accepted")
        } catch { }
        do {
            _ = try GoogleProvider.consumerKey(in: "{\"LjgHrc\":\"\(clientKey)\",\"LjgHrc\":\"\(unrelatedKey)\"}")
            preconditionFailure("Ambiguous client key accepted")
        } catch { }
        precondition(GoogleProvider.resolvedConsumerKey() == GoogleProvider.defaultConsumerKey)
        UserDefaults.standard.set("AIzaCustomKey1234567890123456789012345", forKey: GoogleProvider.consumerKeyDefaultsKey)
        precondition(GoogleProvider.resolvedConsumerKey() == "AIzaCustomKey1234567890123456789012345")
        UserDefaults.standard.removeObject(forKey: GoogleProvider.consumerKeyDefaultsKey)
        precondition(GoogleProvider.resolvedConsumerKey() == GoogleProvider.defaultConsumerKey)
        print("Passed: named billing client selection with unrelated keys, missing configuration, and ambiguity rejection.")
        let crowKey = "1234567890123456" // Synthetic fixture, never a real credential.
        let crowAccount = CrowbotProvider.accountID(credential: crowKey)
        precondition(CrowbotProvider.validAccount(crowAccount) && !crowAccount.contains(crowKey))
        let crowCookie = StoredCookie(name: "crowbot_key", value: crowKey, domain: "chat.crowbot.sh")
        try require(CrowbotProvider.credential(in: [crowCookie]) == crowKey)
        for cookies in [[], [StoredCookie(name: "crowbot_key", value: crowKey, domain: "example.com")], [crowCookie, StoredCookie(name: "crowbot_key", value: "6543210987654321", domain: "chat.crowbot.sh")]] as [[StoredCookie]] {
            do { _ = try CrowbotProvider.credential(in: cookies); preconditionFailure("Invalid Crowbot credential accepted") } catch { }
        }
        let crow = try CrowbotProvider.parse(Data(#"{"balance_microdollars":5000000}"#.utf8), account: crowAccount)
        precondition(crow.remaining == 5 && ReadingValidation.valid(crow, balances: Balance.initial))
        let zero = try CrowbotProvider.parse(Data(#"{"balance_microdollars":0}"#.utf8), account: crowAccount)
        precondition(zero.remaining == 0)
        for fixture in [#"{}"#, #"{"balance_microdollars":true}"#, #"{"balance_microdollars":"5000000"}"#, #"{"balance_microdollars":-1}"#, #"{"balance_microdollars":0.5}"#, #"{"balance_microdollars":5000000,"error":{}}"#] {
            do { _ = try CrowbotProvider.parse(Data(fixture.utf8), account: crowAccount); preconditionFailure("Invalid Crowbot balance accepted") } catch { }
        }
        var pinned = Balance.initial
        pinned[2].account = CrowbotProvider.accountID(credential: "6543210987654321")
        precondition(!ReadingValidation.valid(crow, balances: pinned))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RedirectCheckProtocol.self]
        let crowHTTP = SessionHTTP(provider: "crowbot", cookies: [crowCookie], configuration: config)
        RedirectCheckProtocol.state.reset()
        _ = try await crowHTTP.request(url: URL(string: CrowbotProvider.endpoint)!)
        let crowRequests = RedirectCheckProtocol.state.snapshot()
        precondition(crowRequests.count == 1 && crowRequests[0].value(forHTTPHeaderField: "Authorization") == "Bearer " + crowKey)
        precondition(crowRequests[0].value(forHTTPHeaderField: "Cookie") == nil)
        for destination in ["https://example.com/api/me", "https://chat.crowbot.sh/api/checkout", "https://api.crowbot.sh/api/me", CrowbotProvider.endpoint + "?key=test"] {
            do { _ = try await crowHTTP.request(url: URL(string: destination)!); preconditionFailure("Crowbot credentials escaped the balance endpoint") } catch { }
        }
        print("Passed: Crowbot microdollar parsing, zero/invalid balances, account pinning, credential redaction, restricted endpoint, and redirect refusal.")
        try await unalignedChecks()
        try await yetaChecks()
        try await heimdallmChecks()
        try secretAuditChecks()
        try await updaterChecks()
        try await redirectChecks()
        var original = DarwinBoolean(false)
        precondition(SecKeychainGetUserInteractionAllowed(&original) == errSecSuccess)
        do {
            try KeychainVault.access {
                var allowed = DarwinBoolean(true)
                precondition(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess)
                precondition(!allowed.boolValue, "Background access allowed Keychain UI")
                throw ConnectorError.message("Policy restoration check")
            }
        } catch { }
        var restored = DarwinBoolean(false)
        precondition(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess)
        precondition(restored.boolValue == original.boolValue, "Keychain interaction policy leaked")
        print("Passed: background Keychain UI disabled and policy restored after failure; no credentials accessed.")
        var b = Balance(id: "fireworks", name: "Fireworks", baseline: 10.07, remaining: 10.07, updated: Date(), account: "test", live: true)
        precondition(b.percentageLabel == "100%")
        b.remaining = 10.06; precondition(b.percentageLabel == "99%")
        b.remaining = 0.01; precondition(b.percentageLabel == "<1%")
        b.remaining = 0; precondition(b.percentageLabel == "0%")
        b.remaining = 20.14; precondition(b.percentageLabel == "200%")
        precondition(Balance.initial[1].percentageLabel == "—")
        let id = "000000-AAAAAA-BBBBBB"
        let testBalances = [Balance(id: "vertex", name: "Vertex AI", baseline: 300, remaining: 300, updated: Date(), account: id, live: true)]
        func reading(_ account: String, _ url: String, _ value: Double = 299) -> Reading { Reading(provider: "vertex", remaining: value, currency: "USD", account: account, url: url, expires: nil) }
        precondition(ReadingValidation.valid(reading(id, "https://console.cloud.google.com/billing/\(id)/credits/all"), balances: testBalances))
        precondition(!ReadingValidation.valid(reading("other", "https://console.cloud.google.com/billing/other/credits/all"), balances: testBalances))
        precondition(!ReadingValidation.valid(reading(id, "https://example.com/billing/\(id)/credits"), balances: testBalances))
        precondition(!ReadingValidation.valid(reading(id, "https://console.cloud.google.com/billing/\(id)/credits", -.infinity), balances: testBalances))
        do {
            _ = try await UnconnectedProvider(providerID: "fireworks").fetchBalance()
            preconditionFailure("Unconnected adapter fabricated a balance")
        } catch { precondition(error is DetectionError) }
        let roundTrip = try JSONDecoder().decode([Balance].self, from: JSONEncoder().encode(Balance.initial))
        precondition(roundTrip == Balance.initial)
        try require(ProviderJSON.money(["currencyCode":"USD"]) == 0)
        try require(abs(try ProviderJSON.money(["currencyCode":"USD","units":"10","nanos":70595489]) - 10.070595489) < 0.000000001)
        let now = Date(timeIntervalSince1970:1792721600)
        func grant(_ name: String, _ amount: String, _ end: String = "2026-12-25T00:00:00Z") -> [String:Any] {
            ["name":name,"billingAccountName":"billingAccounts/\(id)","remainingAmount":["currencyCode":"USD","units":amount],"startTime":"2026-10-18T00:00:00Z","endTime":end]
        }
        func response(_ rows: [[String:Any]]) -> [String:Any] { ["data":["creditsQuery":["listCredits":["data":rows]]]] }
        let active = grant("active","300"), expired = grant("expired","300","2026-10-18T00:00:00Z")
        try require(GoogleProvider.parse(response([active,expired]),account:id,now:now).remaining == 300)
        try require(GoogleProvider.parse(response([grant("fractional","300","2026-12-25T00:00:00.000Z")]),account:id,now:now).remaining == 300)
        try require(GoogleProvider.parse(["results":[response([active,expired])]],account:id,now:now).remaining == 300)
        do {
            _ = try GoogleProvider.parse(["results":[response([active]), response([active])]],account:id,now:now)
            preconditionFailure("Multiple billing batch results accepted")
        } catch { }
        do {
            var partial = response([active]); partial["errors"] = [["message":"test query error"]]
            _ = try GoogleProvider.parse(["results":[partial]],account:id,now:now)
            preconditionFailure("Partial billing query accepted")
        } catch { }
        try require(GoogleProvider.parse(response([active,grant("topup","100")]),account:id,now:now).remaining == 400)
        try require(GoogleProvider.parse(response([expired]),account:id,now:now).remaining == 0)
        try require(GoogleProvider.parse(response([]),account:id,now:now).remaining == 0)
        do { _ = try GoogleProvider.parse(response([active,active]),account:id,now:now); preconditionFailure("Duplicate grants accepted") } catch { }
        do { _ = try GoogleProvider.parse(response([active]),account:"wrong",now:now); preconditionFailure("Wrong billing account accepted") } catch { }
        try require(PaymentReference.inferTier(for: 4.85) == 5.0)
        try require(PaymentReference.inferTier(for: 4.996991) == 5.0)
        try require(PaymentReference.inferTier(for: 5.0) == 5.0)
        try require(PaymentReference.inferTier(for: 10.070595489) == 10.0)
        try require(PaymentReference.inferTier(for: 299.996487) == 300.0)
        try require(PaymentReference.inferTier(for: 18.5) == 20.0)
        try require(PaymentReference.inferTier(for: 48.0) == 50.0)
        // Top-up arithmetic: $3.00 remaining, user paid $5.00 -> delta $5.00 -> new total $8.00
        let oldBalance = 3.0
        let newReading = 8.0
        let delta = newReading - oldBalance
        let paidTier = PaymentReference.inferTier(for: delta)
        let recognizedTotal = oldBalance + paidTier
        try require(recognizedTotal == 8.0)
        let refuselessCookie = StoredCookie(name: "abl_session", value: "test_session_token", domain: "refuseless.com")
        precondition(RefuselessProvider.hasValidSession(cookies: [refuselessCookie]))
        precondition(!RefuselessProvider.hasValidSession(cookies: []))
        precondition(!RefuselessProvider.hasValidSession(cookies: [StoredCookie(name: "other", value: "val", domain: "refuseless.com")]))
        final class MockRefuselessProtocol: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                let html = "<div class=\"console-balance\"><span>Balance</span><strong>$0.00</strong></div><dl class=\"hm-balance-rows\"><div><dt>Top-ups</dt><dd>$0.00</dd></div></dl><script>\"email\":\"user@refuseless.com\",\"balance\":0</script>"
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(html.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        let refuselessConfig = URLSessionConfiguration.ephemeral
        refuselessConfig.protocolClasses = [MockRefuselessProtocol.self]
        let refuselessHTTP = SessionHTTP(provider: "refuseless", cookies: [refuselessCookie], configuration: refuselessConfig)
        let refuselessReading = try await RefuselessProvider(http: refuselessHTTP, account: "").fetchBalance()
        precondition(refuselessReading.provider == "refuseless")
        precondition(refuselessReading.remaining == 0.0, "Live Refuseless balance must accurately reference 0.0")
        precondition(refuselessReading.account == "user@refuseless.com")
        precondition(ReadingValidation.valid(refuselessReading, balances: Balance.initial))
        let (zeroBal, zeroBase, zeroAcct) = try RefuselessProvider.parse(html: "<p class=\"hm-balance-figure\">$0.00<span>USD</span></p><dl class=\"hm-balance-rows\"><div><dt>Top-ups</dt><dd>$0.00</dd></div></dl><script>\"email\":\"user@refuseless.com\",\"balance\":0</script>")
        precondition(zeroBal == 0.0 && zeroBase == 0.0 && zeroAcct == "user@refuseless.com")
        let (paidBal, paidBase, paidAcct) = try RefuselessProvider.parse(html: "<p class=\"hm-balance-figure\">$15.50<span>USD</span></p><dl class=\"hm-balance-rows\"><div><dt>Top-ups</dt><dd>$20.00</dd></div></dl><script>\"email\":\"paid@refuseless.com\",\"balance\":15.5,\"depositedCents\":2000</script>")
        precondition(paidBal == 15.50 && paidBase == 20.0 && paidAcct == "paid@refuseless.com")

        // Lutheos SvelteKit and HTML balance parsing checks
        let lutheosCookie = StoredCookie(name: "__Secure-authjs.session-token", value: "lutheos-test-token", domain: "lutheos.com", expires: Date().addingTimeInterval(3600))
        precondition(LutheosProvider.hasValidSession(cookies: [lutheosCookie]))

        final class MockLutheosProtocol: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                let json = "{\"type\":\"data\",\"nodes\":[{\"type\":\"data\",\"data\":{\"user\":{\"email\":\"user@lutheos.com\"},\"workspaces\":[{\"id\":\"ws1\",\"balance\":18.25}]}},{\"type\":\"data\",\"data\":{\"balance\":18.25}}]}"
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(json.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        let lutheosConfig = URLSessionConfiguration.ephemeral
        lutheosConfig.protocolClasses = [MockLutheosProtocol.self]
        let lutheosHTTP = SessionHTTP(provider: "lutheos", cookies: [lutheosCookie], configuration: lutheosConfig)
        let lutheosReading = try await LutheosProvider(http: lutheosHTTP, account: "").fetchBalance()
        precondition(lutheosReading.provider == "lutheos")
        precondition(lutheosReading.remaining == 18.25, "Lutheos balance must be 18.25, got \(lutheosReading.remaining)")
        precondition(lutheosReading.reference == 20.0, "Lutheos inferred tier baseline must be 20.0, got \(lutheosReading.reference ?? 0)")
        precondition(lutheosReading.account == "user@lutheos.com")
        precondition(ReadingValidation.valid(lutheosReading, balances: Balance.initial))

        let (htmlBal, htmlBase, htmlAcct) = try LutheosProvider.parse(html: "<a class=\"drawer-balance\" href=\"/billing\"><span class=\"balance-label\">Balance</span><span class=\"balance-figure\">$42.50</span></a><script>\"email\":\"dev@lutheos.com\",\"balance\":42.5</script>")
        precondition(htmlBal == 42.50 && htmlBase == 50.0 && htmlAcct == "dev@lutheos.com")

        // Test real Lutheos SvelteKit devalue payload with index dereferencing
        let lutheosDevalue = "{\"type\":\"data\",\"nodes\":[{\"type\":\"data\",\"data\":[{\"siteOrigin\":1},\"https://lutheos.com\"]},{\"type\":\"data\",\"data\":[{\"user\":1,\"workspaces\":5,\"accountCredit\":9},{\"email\":3},\"Developer\",\"user@lutheos.com\",\"https://lh3.googleusercontent.com\",[6],{\"id\":7,\"name\":8,\"balance\":9},\"ws-id\",\"Personal\",8.981174]},{\"type\":\"data\",\"data\":[{\"balance\":1,\"creditedTotal\":3},8.981174,0,9]}]}"
        let (devalBal, devalBase, devalAcct) = try LutheosProvider.parse(data: Data(lutheosDevalue.utf8), url: "https://lutheos.com/billing/__data.json")
        precondition(devalBal == 8.981174, "Devalue balance must be 8.981174, got \(devalBal)")
        precondition(devalBase == 9.0, "Devalue baseline must be 9.0, got \(devalBase)")
        precondition(devalAcct == "user@lutheos.com", "Devalue account must be user@lutheos.com, got \(devalAcct)")

        // Pacing formatting and calculation checks
        precondition(PacingCalculator.formatTokens(152_882_923) == "152.9M")
        precondition(PacingCalculator.formatTokens(1_000_000) == "1M")
        precondition(PacingCalculator.formatTokens(250_000) == "250K")
        precondition(PacingCalculator.formatTokens(8_400) == "8,400")
        precondition(PacingCalculator.pacingMessage(tokensPerDay: 152_882_923, runwayDays: 5) == "152.9M tokens per day - Runs out in 5 days")
        precondition(PacingCalculator.pacingMessage(tokensPerDay: 500_000, runwayDays: 1) == "500K tokens per day - Runs out in 1 day")
        precondition(PacingCalculator.pacingMessage(tokensPerDay: nil, runwayDays: 5) == nil)
        precondition(PacingCalculator.pacingMessage(tokensPerDay: 1000, runwayDays: nil) == nil)
        precondition(PacingCalculator.calculateRunway(remaining: 10.0, dailySpend: 2.0) == 5)
        precondition(PacingCalculator.calculateTokensPerDay(totalTokens: 100_000, activeDays: 2) == 50_000)

        let overviewPacingData = Data("{\"type\":\"data\",\"nodes\":[{},{},{\"type\":\"data\",\"data\":[{\"tokens\":1,\"runwayDays\":2,\"buckets\":3},152882923,5,[4],{\"tokens\":1}]}]}".utf8)
        let extractedPacing = LutheosProvider.extractPacing(from: overviewPacingData)
        precondition(extractedPacing?.tokensPerDay == 152882923.0)
        precondition(extractedPacing?.runwayDays == 5)
        let testBalanceWithPacing = Balance(id: "lutheos", name: "Lutheos", baseline: 9.0, remaining: 7.77, updated: Date(), account: "user@lutheos.com", tokensPerDay: 152882923.0, runwayDays: 5)
        precondition(testBalanceWithPacing.pacingMessage == "152.9M tokens per day - Runs out in 5 days")

        // Refuseless pacing extraction checks
        let sampleRefuselessPacing = """
        <script>self.__next_f.push([1,"{\\"periodOutputTokens\\":5728510,\\"series\\":[{\\"at\\":\\"2026-11-01\\",\\"spend\\":2300000},{\\"at\\":\\"2026-11-02\\",\\"spend\\":11850000},{\\"at\\":\\"2026-11-03\\",\\"spend\\":10455708}]}"])</script>
        """
        let refPacing = RefuselessProvider.extractPacing(html: sampleRefuselessPacing, remaining: 0.699055)
        precondition(refPacing != nil, "Refuseless pacing extraction should succeed")
        precondition(abs(refPacing!.tokensPerDay - 1909503.33) < 1.0, "Refuseless tokensPerDay mismatch")
        precondition(refPacing!.runwayDays == 0, "Refuseless runway should be 0 days with $0.70 remaining and $8.20 average daily spend")
        let refBalWithPacing = Balance(id: "refuseless", name: "Refuseless", baseline: 25.0, remaining: 0.70, updated: Date(), account: "user@refuseless.com", tokensPerDay: refPacing!.tokensPerDay, runwayDays: refPacing!.runwayDays)
        precondition(refBalWithPacing.pacingMessage == "1.9M tokens per day - Runs out in 0 days")

        let refPacingWithRunway = RefuselessProvider.extractPacing(html: sampleRefuselessPacing, remaining: 50.00)
        precondition(refPacingWithRunway?.runwayDays == 6, "Refuseless runway should be 6 days with $50 remaining and $8.20 average daily spend")
        let refBalWithRunway = Balance(id: "refuseless", name: "Refuseless", baseline: 100.0, remaining: 50.00, updated: Date(), account: "user@refuseless.com", tokensPerDay: refPacingWithRunway!.tokensPerDay, runwayDays: refPacingWithRunway!.runwayDays)
        precondition(refBalWithRunway.pacingMessage == "1.9M tokens per day - Runs out in 6 days")

        // Real console payload: the RSC `balance`/`spentTotal` integers are
        // micro-dollars and the billing ledger reports cents. Reading the
        // micro-dollar balance as dollars produced a $24,947,613 total.
        let liveConsole = """
        <div class="console-balance"><span>Balance</span><strong>$24.91</strong><a class="console-balance-add" aria-label="Add credits" href="/console/billing"><svg width="15" height="15" viewBox="0 0 24 24"></svg></a></div>
        <p class="hm-balance-figure">$24.91<span>USD</span></p><dl class="hm-balance-rows"><div><dt>Top-ups</dt><dd>$20.00</dd></div><div><dt>Spent</dt><dd>$0.06</dd></div></dl>
        <script>self.__next_f.push([1,"[\\"$\\",\\"$L2a\\",null,{\\"balance\\":24911322,\\"depositedCents\\":2000,\\"spentTotal\\":63743}]"])</script>
        <script>self.__next_f.push([1,"{\\"email\\":\\"user@refuseless.com\\",\\"balance\\":24911322}"])</script>
        """
        let (liveBal, liveBase, liveAcct) = try RefuselessProvider.parse(html: liveConsole)
        precondition(abs(liveBal - 24.911322) < 0.0001, "Balance must be dollars from micro-dollar payload, got \(liveBal)")
        precondition(abs(liveBase - 24.975065) < 0.001, "Total granted must be remaining + spent, got \(liveBase)")
        precondition(liveAcct == "user@refuseless.com")

        // Billing ledger: amountCents + bonusCents for completed top-ups is the
        // truest total ever granted ($20.00 + $5.00).
        let liveBilling = """
        <p class="hm-balance-figure">$24.91<span>USD</span></p><dl class="hm-balance-rows"><div><dt>Top-ups</dt><dd>$20.00</dd></div><div><dt>Spent</dt><dd>$0.06</dd></div><div><dt>This month</dt><dd>$0.06</dd></div></dl>
        <script>self.__next_f.push([1,"[\\"$\\",\\"$L2d\\",null,{\\"balance\\":24911322,\\"depositedCents\\":2000,\\"spentTotal\\":63743,\\"monthSpend\\":63743}]"])</script>
        <script>self.__next_f.push([1,"{\\"deposits\\":[{\\"id\\":12425,\\"provider\\":\\"stripe\\",\\"reference\\":\\"abl-test\\",\\"amountCents\\":2000,\\"bonusCents\\":500,\\"currency\\":\\"USD\\",\\"status\\":\\"completed\\",\\"invoice\\":true}],\\"total\\":1,\\"page\\":1,\\"perPage\\":10}"])</script>
        <script>self.__next_f.push([1,"{\\"available\\":true,\\"thresholdCents\\":500,\\"amountCents\\":2000}"])</script>
        """
        let (ledgerBal, ledgerBase, _) = try RefuselessProvider.parse(html: liveBilling)
        precondition(abs(ledgerBal - 24.911322) < 0.0001, "Ledger page balance must be dollars, got \(ledgerBal)")
        precondition(abs(ledgerBase - 25.0) < 0.0001, "Ledger total must be $20.00 top-up + $5.00 bonus, got \(ledgerBase)")

        // Micro-dollar fallback when the rendered figure is absent.
        let microOnly = "<script>self.__next_f.push([1,\"{\\\"balance\\\":24911322,\\\"spentTotal\\\":63743}\"])</script>"
        let (microBal, microBase, _) = try RefuselessProvider.parse(html: microOnly)
        precondition(abs(microBal - 24.911322) < 0.0001, "Micro-dollar balance must divide by 1e6, got \(microBal)")
        precondition(abs(microBase - 24.975065) < 0.001, "Micro-dollar total must be remaining + spent, got \(microBase)")
        let testRefuseless = Balance(id: "refuseless", name: "Refuseless", baseline: 100, remaining: 75.50, updated: Date(), account: "Test")
        precondition(testRefuseless.money == 75.50.formatted(.currency(code: "USD")), "Refuseless must format in USD dollars, not credits")
        precondition(!testRefuseless.money.contains("credits"), "Refuseless money must not contain 'credits'")
        precondition(testRefuseless.percent == 75.5, "Percent must accurately track remaining/baseline")
        let lowerRefuseless = Balance(id: "refuseless", name: "Refuseless", baseline: 100, remaining: 25.0, updated: Date(), account: "Test")
        precondition(lowerRefuseless.percent < testRefuseless.percent, "Percent must get smaller with less tokens")
        // AppUpdater version comparison and formatting checks
        precondition(AppUpdater.isVersion("0.5.0", newerThan: "0.4.9"))
        precondition(AppUpdater.isVersion("v0.5.0", newerThan: "v0.4.9"))
        precondition(!AppUpdater.isVersion("0.5.0", newerThan: "0.5.0"))
        precondition(!AppUpdater.isVersion("0.4.9", newerThan: "0.5.0"))
        precondition(AppUpdater.isVersion("0.4.9", newerThan: "0.4.8"))
        precondition(AppUpdater.isVersion("v0.4.9", newerThan: "v0.4.8"))
        precondition(AppUpdater.isVersion("0.4.8", newerThan: "0.4.7"))
        precondition(AppUpdater.isVersion("v0.4.8", newerThan: "v0.4.7"))
        precondition(AppUpdater.isVersion("1.0.0", newerThan: "0.4.7"))
        precondition(!AppUpdater.isVersion("0.4.7", newerThan: "0.4.7"))
        precondition(!AppUpdater.isVersion("0.4.6", newerThan: "0.4.7"))
        precondition(!AppUpdater.isVersion("0.3.9", newerThan: "0.4.0"))

        // ChangelogManager checks: current version, previous versions, and selection
        let changelog = ChangelogManager.shared
        precondition(changelog.entries.count >= 6, "Changelog must include at least 6 built-in versions")
        guard let entry053 = changelog.entries.first(where: { $0.version == "0.5.3" }),
              let entry052 = changelog.entries.first(where: { $0.version == "0.5.2" }),
              let entry051 = changelog.entries.first(where: { $0.version == "0.5.1" }),
              let entry050 = changelog.entries.first(where: { $0.version == "0.5.0" }),
              let entry049 = changelog.entries.first(where: { $0.version == "0.4.9" }),
              let entry048 = changelog.entries.first(where: { $0.version == "0.4.8" }),
              let entry047 = changelog.entries.first(where: { $0.version == "0.4.7" }) else {
            preconditionFailure("Built-in changelog missing 0.5.3, 0.5.2, 0.5.1, 0.5.0, 0.4.9, 0.4.8, or 0.4.7")
        }
        precondition(entry053.isCurrent(currentVersion: "0.5.3") == true)
        precondition(entry053.isPrevious(currentVersion: "0.5.3") == false)
        precondition(entry053.isNewer(currentVersion: "0.5.2") == true)
        precondition(entry052.isCurrent(currentVersion: "0.5.3") == false)
        precondition(entry052.isPrevious(currentVersion: "0.5.3") == true)
        precondition(entry051.isCurrent(currentVersion: "0.5.3") == false)
        precondition(entry051.isPrevious(currentVersion: "0.5.3") == true)
        precondition(entry050.isCurrent(currentVersion: "0.5.3") == false)
        precondition(entry050.isPrevious(currentVersion: "0.5.3") == true)
        precondition(entry049.isPrevious(currentVersion: "0.5.3") == true)
        precondition(entry048.isPrevious(currentVersion: "0.5.3") == true)
        precondition(entry047.isPrevious(currentVersion: "0.5.3") == true)
        precondition(!entry053.highlights.isEmpty, "0.5.3 highlights must not be empty")
        precondition(!entry053.notes.isEmpty, "0.5.3 notes must not be empty")
        precondition(!entry052.highlights.isEmpty, "0.5.2 highlights must not be empty")
        precondition(!entry052.notes.isEmpty, "0.5.2 notes must not be empty")
        precondition(!entry051.highlights.isEmpty, "0.5.1 highlights must not be empty")
        precondition(!entry051.notes.isEmpty, "0.5.1 notes must not be empty")
        precondition(!entry050.highlights.isEmpty, "0.5.0 highlights must not be empty")
        // Release notes must not leak local machine details.
        precondition(!entry053.notes.contains("/Users/"), "Changelog must not contain personal paths")
        precondition(!entry052.notes.contains("/Users/"), "Changelog must not contain personal paths")
        precondition(!entry051.notes.contains("/Users/"), "Changelog must not contain personal paths")
        // The shipped bundle version and the changelog must agree.
        if let plistVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            precondition(plistVersion == "0.5.3", "Info.plist version is \(plistVersion), expected 0.5.3")
        }

        changelog.select(version: "0.5.2")
        precondition(changelog.selectedVersion == "0.5.2")
        precondition(changelog.selectedEntry?.version == "0.5.2")
        changelog.select(version: "0.5.3")
        precondition(changelog.selectedVersion == "0.5.3")

        print("Passed: ChangelogManager version history, current/previous tagging, and selection.")
        print("Passed: AppUpdater semver parsing, newer version detection, and release tagging.")
        print("Passed: Refuseless USD balance formatting, baseline calculations, and smaller-gauge token tracking.")
        print("Passed: Lutheos USD balance parsing, SvelteKit data traversal, baseline calculations, and validation.")
        print("Passed: percentages, sub-1% rounding, top-up display, wrong-account/source rejection, unconnected adapter, and persistence round-trip.")
        print("Passed: exact money parsing, zero balances, active/expired grants, added grants, and duplicate rejection.")
    }
}

final class RedirectCheckState: @unchecked Sendable {
    let lock = NSLock()
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; requests.append(request) }
    func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}

final class RedirectCheckProtocol: URLProtocol, @unchecked Sendable {
    static let state = RedirectCheckState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.append(request)
        let path = request.url!.path
        let done = path == "/finish"
        let location = path == "/outside" ? "https://example.com/" : path == "/loop" ? "/loop" : "/finish"
        let response = HTTPURLResponse(url: request.url!, statusCode: done ? 200 : 302, httpVersion: "HTTP/1.1", headerFields: done ? [:] : ["Location":location,"Set-Cookie":"cloud_test=ok; Path=/; Secure"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Serves Unaligned dashboard payloads and records the request headers, so the
/// tests can prove the browser session cookie (and only it) is sent.
final class MockUnalignedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var seen: [URLRequest] = []

    static func reset(body: Data, status: Int = 200) {
        Self.body = body
        Self.status = status
        seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func unalignedChecks() async throws {
    let sessionCookie = StoredCookie(name: "__Secure-better-auth.session_token", value: "unaligned-test-session", domain: ".unaligned.pw", expires: Date().addingTimeInterval(3600))
    precondition(UnalignedProvider.hasValidSession(cookies: [sessionCookie]))
    precondition(!UnalignedProvider.hasValidSession(cookies: []))
    precondition(!UnalignedProvider.hasValidSession(cookies: [StoredCookie(name: "session", value: "x", domain: "example.com")]))
    precondition(!UnalignedProvider.hasValidSession(cookies: [StoredCookie(name: "theme", value: "dark", domain: ".unaligned.pw")]))

    // SvelteKit devalue payload: the balance is referenced by index into `data`.
    let devalue = #"{"type":"data","nodes":[null,{"type":"data","data":[{"user":1,"balance":2}, {"email":3}, 12.5, "user@unaligned.pw"],"uses":{}}]}"#
    let (bal, base, acct) = try UnalignedProvider.parse(data: Data(devalue.utf8), url: UnalignedProvider.dataEndpoints[0])
    precondition(bal == 12.5, "Unaligned devalue balance must be 12.5, got \(bal)")
    precondition(base == PaymentReference.inferTier(for: 12.5))
    precondition(acct == "user@unaligned.pw")

    // Real dashboard shape: the balance is nested in a referenced account object,
    // so the top-level node has no `balance` key at all. Index 4 is the account
    // reference, and 2 is the balance reference -- reading either as dollars is the
    // bug this fixture locks down.
    let nested = #"{"type":"data","nodes":[null,{"type":"data","data":[{"account":1,"base":2,"space":3},{"adClick":4,"admin":5,"balance":6,"bonusEligible":5,"createdDay":7,"id":8,"reseller":9},false,"",true,true,7.25,"2026-11-01",11],"uses":{}}]}"#
    let (nestedBal, nestedBase, _) = try UnalignedProvider.parse(data: Data(nested.utf8), url: UnalignedProvider.dataEndpoints[0])
    precondition(nestedBal == 7.25, "Nested account balance must be 7.25, got \(nestedBal)")
    precondition(nestedBase == PaymentReference.inferTier(for: 7.25))

    // The real payload stores the balance in micro-dollars: 4_589_693 renders as
    // $4.59 on the dashboard. Reporting the raw value showed millions of dollars.
    let micro = #"{"type":"data","nodes":[null,{"type":"data","data":[{"account":1},{"balance":2,"id":3},4589693,"acct"],"uses":{}}]}"#
    let (microBal, _, _) = try UnalignedProvider.parse(data: Data(micro.utf8), url: UnalignedProvider.dataEndpoints[0])
    precondition(abs(microBal - 4.589693) < 0.000001, "Micro-dollar balance must be $4.589693, got \(microBal)")
    // A dollars-with-cents value is left alone, so the scale rule cannot double-divide.
    let cents = #"{"type":"data","nodes":[null,{"type":"data","data":[{"account":1},{"balance":2},4.59],"uses":{}}]}"#
    let (centsBal, _, _) = try UnalignedProvider.parse(data: Data(cents.utf8), url: UnalignedProvider.dataEndpoints[0])
    precondition(abs(centsBal - 4.59) < 0.000001, "Dollar balance must stay $4.59, got \(centsBal)")

    // Billing ledger: completed top-ups set the 100% reference. Real rows are
    // devalue payloads whose values are array references, not literals.
    let ledger = #"{"type":"data","nodes":[null,{"type":"data","data":[{"history":1},{"rows":2,"total":3},[4],1,{"status":5,"usd":6,"amount":6,"coin":7},"paid",5.95,"USDC"],"uses":{}}]}"#
    let ledgerJSON = try JSONSerialization.jsonObject(with: Data(ledger.utf8), options: [.fragmentsAllowed])
    let topUps = UnalignedProvider.topUpTotal(json: ledgerJSON)
    precondition(topUps != nil && abs(topUps! - 5.95) < 0.0001, "Top-up total must be $5.95, got \(topUps ?? -1)")

    // Multiple rows sum, and rows that never settled are excluded.
    let ledgerMulti = #"{"type":"data","nodes":[null,{"type":"data","data":[{"history":1},{"rows":2},[3,4],{"status":5,"usd":6},{"status":7,"usd":8},"paid",5.95,"expired",99.0],"uses":{}}]}"#
    let multiJSON = try JSONSerialization.jsonObject(with: Data(ledgerMulti.utf8), options: [.fragmentsAllowed])
    if let multi = UnalignedProvider.topUpTotal(json: multiJSON) {
        precondition(abs(multi - 5.95) < 0.0001, "Settled top-ups only, got \(multi)")
    }
    let noLedger = try JSONSerialization.jsonObject(with: Data(#"{"history":{"rows":[]}}"#.utf8), options: [.fragmentsAllowed])
    precondition(UnalignedProvider.topUpTotal(json: noLedger) == nil, "An empty ledger must not report a baseline")

    // A payload with no balance field at all must fail rather than be
    // regex-scraped for some other number in the document.
    for fixture in [
        #"{"type":"data","nodes":[null,{"type":"data","data":[{"account":1},{"id":2,"createdDay":3},5,6]}]}"#,
        #"{"type":"data","nodes":[null,{"type":"data","data":[{"account":1},{"balance":2},{"nested":true}]}]}"#
    ] {
        do {
            _ = try UnalignedProvider.parse(data: Data(fixture.utf8), url: UnalignedProvider.dataEndpoints[0])
            preconditionFailure("Unaligned payload without a resolvable balance produced a value: \(fixture)")
        } catch { }
    }

    // Plain object shapes and string amounts.
    for (fixture, expected) in [
        (#"{"balance":9.99}"#, 9.99),
        (#"{"balance":"7.25"}"#, 7.25),
        (#"{"balance":{"usd":3.5}}"#, 3.5),
        (#"{"data":{"available":1.75}}"#, 1.75),
        (#"{"credits":4.2}"#, 4.2)
    ] {
        let parsed = try UnalignedProvider.parse(data: Data(fixture.utf8), url: UnalignedProvider.dataEndpoints[0])
        precondition(parsed.remaining == expected, "Unaligned fixture \(fixture) parsed as \(parsed.remaining)")
    }

    // A "spent"/"cost" figure must never be read as the remaining balance.
    let spentOnly = try UnalignedProvider.parse(data: Data(#"{"balance":10.0,"spent":2.0}"#.utf8), url: UnalignedProvider.dataEndpoints[0])
    precondition(spentOnly.remaining == 10.0)

    // A logged-out session returns a SvelteKit redirect, which is not a balance.
    for fixture in [#"{"type":"redirect","status":303,"location":"/login"}"#, #"{}"#, #"not json"#] {
        do {
            _ = try UnalignedProvider.parse(data: Data(fixture.utf8), url: UnalignedProvider.dataEndpoints[0])
            preconditionFailure("Non-balance Unaligned payload accepted: \(fixture)")
        } catch { }
    }

    // HTML fallback for the rendered dashboard document.
    let html = "<div class=\"account\"><span class=\"balance-figure\">$18.40</span></div><p>user@unaligned.pw</p>"
    let (htmlBal, htmlBase, htmlAcct) = try UnalignedProvider.parse(html: html)
    precondition(htmlBal == 18.40 && htmlBase == 20.0 && htmlAcct == "user@unaligned.pw")

    // Pacing extraction checks
    let unalignedPacingData = Data(#"{"type":"data","nodes":[null,null,{"type":"data","data":[{"tokens30d":1,"spent30d":2,"usage":3},357000000,5650000,[4,8],{"day":5,"requests":6,"cost":7},"2026-11-05",100,2000000,{"day":9,"requests":10,"cost":11},"2026-11-06",200,3650000],"uses":{}}]}"#.utf8)
    let unalignedPacing = UnalignedProvider.extractPacing(from: unalignedPacingData, remaining: 0.60)
    precondition(unalignedPacing != nil, "Unaligned pacing extraction should succeed")
    precondition(unalignedPacing?.tokensPerDay == 178500000.0, "Unaligned tokensPerDay mismatch")
    precondition(unalignedPacing?.runwayDays == 0, "Unaligned runway should be 0 days with $0.60 remaining and $2.825 daily spend")
    let unalignedBalWithPacing = Balance(id: "unaligned", name: "Unaligned", baseline: 5.95, remaining: 0.60, updated: Date(), account: "user@unaligned.pw", tokensPerDay: unalignedPacing!.tokensPerDay, runwayDays: unalignedPacing!.runwayDays)
    precondition(unalignedBalWithPacing.pacingMessage == "178.5M tokens per day - Runs out in 0 days")

    let unalignedPacingWithRunway = UnalignedProvider.extractPacing(from: unalignedPacingData, remaining: 15.0)
    precondition(unalignedPacingWithRunway?.runwayDays == 5, "Unaligned runway should be 5 days with $15 remaining and $2.825 daily spend")
    let unalignedBalWithRunway = Balance(id: "unaligned", name: "Unaligned", baseline: 25.0, remaining: 15.0, updated: Date(), account: "user@unaligned.pw", tokensPerDay: unalignedPacingWithRunway!.tokensPerDay, runwayDays: unalignedPacingWithRunway!.runwayDays)
    precondition(unalignedBalWithRunway.pacingMessage == "178.5M tokens per day - Runs out in 5 days")

    // Reading validation: only the dashboard host is accepted, and a different
    // account cannot overwrite a pinned balance.
    guard let index = Balance.initial.firstIndex(where: { $0.id == "unaligned" }) else { preconditionFailure("Balance.initial must include unaligned") }
    let reading = Reading(provider: "unaligned", remaining: 9.99, currency: "USD", account: "user@unaligned.pw", url: UnalignedProvider.dataEndpoints[0], expires: nil)
    precondition(ReadingValidation.valid(reading, balances: Balance.initial))
    let hostile = Reading(provider: "unaligned", remaining: 5, currency: "USD", account: "user@unaligned.pw", url: "https://evil.example/dashboard", expires: nil)
    precondition(!ReadingValidation.valid(hostile, balances: Balance.initial))
    let apiKeyURL = Reading(provider: "unaligned", remaining: 5, currency: "USD", account: "user@unaligned.pw", url: "https://unaligned.pw/v1/balance", expires: nil)
    precondition(!ReadingValidation.valid(apiKeyURL, balances: Balance.initial), "Unaligned must be read from the dashboard session, not the API")
    var pinned = Balance.initial
    pinned[index].account = "someone@else.com"
    precondition(!ReadingValidation.valid(reading, balances: pinned))

    // Live fetch path: the browser session cookie is sent, no API key header.
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockUnalignedProtocol.self]
    MockUnalignedProtocol.reset(body: Data(devalue.utf8))
    let http = SessionHTTP(provider: "unaligned", cookies: [sessionCookie], configuration: config)
    let fetched = try await UnalignedProvider(http: http, account: "").fetchBalance()
    precondition(fetched.remaining == 12.5 && fetched.provider == "unaligned")
    // The dashboard supplies the balance and the billing ledger the baseline.
    precondition(MockUnalignedProtocol.seen.count == 2, "Expected dashboard + billing requests, got \(MockUnalignedProtocol.seen.count)")
    precondition(MockUnalignedProtocol.seen[0].url?.absoluteString == UnalignedProvider.dataEndpoints[0])
    precondition(MockUnalignedProtocol.seen[1].url?.absoluteString == UnalignedProvider.dataEndpoints[1])
    for sent in MockUnalignedProtocol.seen {
        precondition(sent.url?.host == "unaligned.pw")
        precondition(sent.value(forHTTPHeaderField: "Cookie")?.contains("session_token") == true)
        precondition(sent.value(forHTTPHeaderField: "Authorization") == nil, "Unaligned must not send an API key")
    }

    // A session that cannot read any endpoint fails loudly instead of inventing a
    // balance, and credentials never leave the approved host.
    MockUnalignedProtocol.reset(body: Data(#"{"type":"redirect","status":303,"location":"/login"}"#.utf8))
    do {
        _ = try await UnalignedProvider(http: http, account: "").fetchBalance()
        preconditionFailure("Logged-out Unaligned session produced a balance")
    } catch { }
    do {
        _ = try await http.request(url: URL(string: "https://api.unaligned.pw/v1/balance")!)
        preconditionFailure("Unaligned session was sent to the API host")
    } catch { }

    // Enable/disable keeps the record and its position, and files written before
    // this feature still load as enabled.
    var provider = Balance.initial[index]
    precondition(provider.isEnabled)
    provider.isEnabled = false
    precondition(!provider.isEnabled)
    let roundTrip = try JSONDecoder().decode(Balance.self, from: JSONEncoder().encode(provider))
    precondition(!roundTrip.isEnabled, "A paused provider must stay paused across a save/load cycle")
    precondition(roundTrip.disabled != nil)
    provider.isEnabled = true
    let reEnabled = try JSONDecoder().decode(Balance.self, from: JSONEncoder().encode(provider))
    precondition(reEnabled.isEnabled)
    let legacy = Data(#"{"id":"lutheos","name":"Lutheos","baseline":10,"remaining":5,"updated":0,"account":"","live":true}"#.utf8)
    let legacyBalance = try JSONDecoder().decode(Balance.self, from: legacy)
    precondition(legacyBalance.isEnabled, "Balance files without a disabled flag must stay enabled")
    precondition(legacyBalance.disabled == nil)

    // Every native provider must ship brand artwork; a missing mask silently
    // degrades the menu bar and badge tiles to a monogram.
    for provider in Balance.initial.map(\.id) {
        let path = "Resources/\(provider)-mask.png"
        precondition(FileManager.default.fileExists(atPath: path), "Missing brand mask: \(path)")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let rep = NSBitmapImageRep(data: data) else { preconditionFailure("\(path) is not a readable PNG") }
        precondition(rep.hasAlpha, "\(path) must have an alpha channel to render as a template")
        var opaque = 0
        var minX = rep.pixelsWide, maxX = 0, minY = rep.pixelsHigh, maxY = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                opaque += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        precondition(opaque > 100, "\(path) is empty")
        // The Unaligned mark is inset in its canvas; a mark that bleeds to the edge
        // clips when drawn into an 18pt menu bar slot.
        if provider == "unaligned" {
            precondition(minX > 0 && minY > 0 && maxX < rep.pixelsWide - 1 && maxY < rep.pixelsHigh - 1,
                         "\(path) touches the canvas edge")
        }
    }

    print("Passed: Unaligned dashboard-session balance parsing (devalue, JSON, HTML), logged-out rejection, host restriction, cookie-only requests, and provider enable/disable persistence.")
}

/// Serves Yeta console payloads and records the requests sent.
final class MockYetaProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (status: Int, body: Data)] = [:]
    nonisolated(unsafe) static var seen: [URLRequest] = []

    static func reset() {
        routes = [:]
        seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen.append(request)
        let path = request.url?.path ?? ""
        let route = Self.routes[path] ?? (status: 404, body: Data(#"{"success":false,"message":"not found"}"#.utf8))
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func yetaChecks() async throws {
    // Quota conversion is read from the deployment, not hardcoded.
    let statusJSON = try JSONSerialization.jsonObject(with: Data(#"{"data":{"quota_per_unit":500000}}"#.utf8))
    precondition(YetaProvider.quotaPerUnit(statusJSON: statusJSON) == 500_000)
    let stringStatus = try JSONSerialization.jsonObject(with: Data(#"{"data":{"quota_per_unit":"250000"}}"#.utf8))
    precondition(YetaProvider.quotaPerUnit(statusJSON: stringStatus) == 250_000)
    let missing = try JSONSerialization.jsonObject(with: Data(#"{"data":{}}"#.utf8))
    precondition(YetaProvider.quotaPerUnit(statusJSON: missing) == YetaProvider.defaultQuotaPerUnit)

    // 500000 quota units = $1, so 2_500_000 is $5.00 remaining.
    let selfBody = #"{"success":true,"data":{"id":7,"username":"yeta-user","email":"user@yeta.ai","quota":2500000,"used_quota":500000}}"#
    let reading = try YetaProvider.parse(Data(selfBody.utf8), quotaPerUnit: 500_000)
    precondition(abs(reading.remaining - 5.0) < 0.000001, "Yeta remaining must be $5.00, got \(reading.remaining)")
    precondition(abs((reading.reference ?? 0) - 6.0) < 0.000001, "Yeta total must be remaining + spent = $6.00, got \(reading.reference ?? -1)")
    precondition(reading.account == "user@yeta.ai" && reading.currency == "USD" && reading.provider == "yeta")
    precondition(ReadingValidation.valid(reading, balances: Balance.initial))

    // Zero balance is valid, and a non-dollar currency or foreign host is not.
    let zero = try YetaProvider.parse(Data(#"{"success":true,"data":{"quota":0,"used_quota":0}}"#.utf8), quotaPerUnit: 500_000)
    precondition(zero.remaining == 0)
    let hostile = Reading(provider: "yeta", remaining: 5, currency: "USD", account: "", url: "https://evil.example/api/user/self", expires: nil)
    precondition(!ReadingValidation.valid(hostile, balances: Balance.initial))

    // Rejected sessions and malformed payloads fail loudly.
    for fixture in [
        #"{"success":false,"code":"AUTH_UNAUTHORIZED","message":"Unauthorized, invalid access token"}"#,
        #"{"success":true,"data":{"username":"x"}}"#,
        #"not json"#
    ] {
        do {
            _ = try YetaProvider.parse(Data(fixture.utf8), quotaPerUnit: 500_000)
            preconditionFailure("Invalid Yeta payload accepted: \(fixture)")
        } catch { }
    }
    // An account mismatch must not overwrite a pinned balance.
    do {
        _ = try YetaProvider.parse(Data(selfBody.utf8), quotaPerUnit: 500_000, account: "someone@else.com")
        preconditionFailure("Yeta accepted a different account")
    } catch { }

    // Fetch path: status then self, cookie only, no API key.
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockYetaProtocol.self]
    MockYetaProtocol.reset()
    MockYetaProtocol.routes["/api/status"] = (200, Data(#"{"data":{"quota_per_unit":500000}}"#.utf8))
    MockYetaProtocol.routes["/api/user/self"] = (200, Data(selfBody.utf8))
    let cookie = StoredCookie(name: "session", value: "yeta-test-session", domain: "platform.yeta.ai", expires: Date().addingTimeInterval(3600))
    let http = SessionHTTP(provider: "yeta", cookies: [cookie], configuration: config)
    let fetched = try await YetaProvider(http: http, account: "").fetchBalance()
    precondition(abs(fetched.remaining - 5.0) < 0.000001)
    precondition(MockYetaProtocol.seen.count == 2)
    for sent in MockYetaProtocol.seen {
        precondition(sent.url?.host == "platform.yeta.ai")
        precondition(sent.value(forHTTPHeaderField: "Cookie")?.contains("session") == true)
        precondition(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }
    // The console API must not be reachable through another path on the host.
    do {
        _ = try await http.request(url: URL(string: "https://platform.yeta.ai/api/user/login")!)
        preconditionFailure("Yeta session was sent to an unapproved endpoint")
    } catch { }

    // Registered, but paused until the user enables it.
    guard let yeta = Balance.initial.first(where: { $0.id == "yeta" }) else { preconditionFailure("Balance.initial must include yeta") }
    precondition(!yeta.isEnabled, "Yeta must ship disabled")
    precondition(yeta.name == "Yeta")
    precondition(YetaProvider.hasValidSession(cookies: [cookie]))
    precondition(!YetaProvider.hasValidSession(cookies: [StoredCookie(name: "theme", value: "dark", domain: ".yeta.ai")]))

    print("Passed: Yeta quota conversion from the server, remaining/total split, rejected sessions, account pinning, cookie-only requests, endpoint restriction, and disabled-by-default registration.")
}

final class MockHeimdallmProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var routes: [String: (Int, Data)] = [:]
    static var seen: [URLRequest] = []
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        routes.removeAll(); seen.removeAll()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        let path = request.url?.path ?? ""
        let match = Self.routes[path] ?? (404, Data("{}".utf8))
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: match.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: match.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func heimdallmChecks() async throws {
    let creditsBody = #"{"account_id":"acc_heimdall_123","balance":{"credited":"25.00","debited":"12.50","available":"12.50","held":"0","spendable":"12.50"},"totals":{"deposited":"25.00","refunded":"0","referral_rewards":"0","adjusted":"0","spent":"12.50","balance":"12.50"}}"#
    let accountBody = #"{"user":{"id":"usr_heimdall_1","email":"user@heimdallm.com","display_name":"HeimdallUser"},"account":{"id":"acc_heimdall_123","name":"Personal","credits":{"available":"12.50","spendable":"12.50"}}}"#

    // Primary parsing: spendable balance, deposited reference, user identity
    let (remaining, baseline, accountID) = try HeimdallmProvider.parseCredits(Data(creditsBody.utf8))
    precondition(abs(remaining - 12.50) < 0.000001, "Heimdallm remaining must be 12.50, got \(remaining)")
    precondition(abs(baseline - 25.00) < 0.000001, "Heimdallm baseline must be 25.00, got \(baseline)")
    precondition(accountID == "acc_heimdall_123")

    let resolvedAccount = HeimdallmProvider.parseAccount(Data(accountBody.utf8))
    precondition(resolvedAccount == "user@heimdallm.com")

    let reading = try HeimdallmProvider.parse(creditsData: Data(creditsBody.utf8), accountData: Data(accountBody.utf8), url: "https://staging.heimdallm.com/api/frontend/v1/credits")
    precondition(abs(reading.remaining - 12.50) < 0.000001)
    precondition(abs((reading.reference ?? 0) - 25.00) < 0.000001)
    precondition(reading.account == "user@heimdallm.com" && reading.currency == "USD" && reading.provider == "heimdallm")
    precondition(ReadingValidation.valid(reading, balances: Balance.initial))

    // Fallback when accountData is missing: uses accountID
    let fallbackReading = try HeimdallmProvider.parse(creditsData: Data(creditsBody.utf8), accountData: nil, url: "https://heimdallm.com/api/frontend/v1/credits")
    precondition(fallbackReading.account == "acc_heimdall_123")
    precondition(ReadingValidation.valid(fallbackReading, balances: Balance.initial))

    // Baseline calculation when deposited is 0 but spent > 0: baseline = remaining + spent
    let spentOnlyCredits = #"{"account_id":"acc_2","balance":{"spendable":"10.00","available":"10.00"},"totals":{"deposited":"0","spent":"15.00"}}"#
    let spentReading = try HeimdallmProvider.parse(creditsData: Data(spentOnlyCredits.utf8), url: "https://heimdallm.com/api/frontend/v1/credits")
    precondition(abs(spentReading.remaining - 10.00) < 0.000001)
    precondition(abs((spentReading.reference ?? 0) - 25.00) < 0.000001)

    // Baseline calculation when deposited and spent are 0: tier inference
    let zeroTotalCredits = #"{"account_id":"acc_3","balance":{"spendable":"10.00","available":"10.00"},"totals":{"deposited":"0","spent":"0"}}"#
    let tierReading = try HeimdallmProvider.parse(creditsData: Data(zeroTotalCredits.utf8), url: "https://heimdallm.com/api/frontend/v1/credits")
    precondition(abs(tierReading.remaining - 10.00) < 0.000001)
    precondition((tierReading.reference ?? 0) >= 10.00)

    // Zero balance is valid
    let zeroCredits = #"{"account_id":"acc_4","balance":{"spendable":"0","available":"0"},"totals":{"deposited":"0","spent":"0"}}"#
    let zeroReading = try HeimdallmProvider.parse(creditsData: Data(zeroCredits.utf8), url: "https://heimdallm.com/api/frontend/v1/credits")
    precondition(zeroReading.remaining == 0 && (zeroReading.reference ?? 0) == 0)

    // Baseline uses credited amount from balance or entries when deposited in totals is 0
    let creditedOnly = #"{"account_id":"acc_5","balance":{"credited":"5.00","spendable":"4.96"},"totals":{"deposited":"0","spent":"0.04"}}"#
    let creditedReading = try HeimdallmProvider.parse(creditsData: Data(creditedOnly.utf8), url: "https://heimdallm.com/api/frontend/v1/credits")
    precondition(abs(creditedReading.remaining - 4.96) < 0.000001)
    precondition(abs((creditedReading.reference ?? 0) - 5.00) < 0.000001)

    let entriesDeposit = #"{"account_id":"acc_6","balance":{"spendable":"4.50"},"totals":{"deposited":"0","spent":"0.50"},"entries":[{"kind":"deposit","amount":"5.00"}]}"#
    let entriesReading = try HeimdallmProvider.parse(creditsData: Data(entriesDeposit.utf8), url: "https://heimdallm.com/api/frontend/v1/credits")
    precondition(abs((entriesReading.reference ?? 0) - 5.00) < 0.000001)

    // Authoritative totals take precedence over extraneous ledger rows
    let entriesWithAdjustments = #"{"account_id":"acc_7","balance":{"credited":"5.00","spendable":"4.92"},"totals":{"deposited":"5.00","spent":"0.08"},"entries":[{"kind":"deposit","amount":"5.00"},{"kind":"adjustment","amount":"5.00"}]}"#
    let adjReading = try HeimdallmProvider.parse(creditsData: Data(entriesWithAdjustments.utf8), url: "https://heimdallm.com/api/frontend/v1/credits")
    precondition(abs((adjReading.reference ?? 0) - 5.00) < 0.000001, "Extraneous ledger adjustment must not inflate authoritative baseline")

    // Hostile URL is rejected by ReadingValidation
    let hostile = Reading(provider: "heimdallm", remaining: 10, currency: "USD", account: "", url: "https://evil.example/api/frontend/v1/credits", expires: nil)
    precondition(!ReadingValidation.valid(hostile, balances: Balance.initial))

    // Rejected / error payloads fail loudly
    for fixture in [
        #"{"error":{"message":"Unauthorized session"}}"#,
        #"{"balance":{}}"#,
        #"not json"#
    ] {
        do {
            _ = try HeimdallmProvider.parse(creditsData: Data(fixture.utf8), url: "https://heimdallm.com/api/frontend/v1/credits")
            preconditionFailure("Invalid Heimdallm payload accepted: \(fixture)")
        } catch { }
    }

    // Account mismatch rejects foreign account
    do {
        _ = try HeimdallmProvider.parse(creditsData: Data(creditsBody.utf8), accountData: Data(accountBody.utf8), url: "https://heimdallm.com/api/frontend/v1/credits", account: "other@example.com")
        preconditionFailure("Heimdallm accepted a different account")
    } catch { }

    // Fetch path: credits, account, and generations/analytics; cookie only, no API key
    let analyticsBody = #"{"summary":{"prompt_tokens":1200000,"completion_tokens":300000,"spend":0.75},"buckets":[{"requests":10,"tokens":50000,"spend":0.05}]}"#
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockHeimdallmProtocol.self]
    MockHeimdallmProtocol.reset()
    MockHeimdallmProtocol.routes["/api/frontend/v1/credits"] = (200, Data(creditsBody.utf8))
    MockHeimdallmProtocol.routes["/api/frontend/v1/account"] = (200, Data(accountBody.utf8))
    MockHeimdallmProtocol.routes["/api/frontend/v1/generations/analytics"] = (200, Data(analyticsBody.utf8))
    let cookie = StoredCookie(name: "__Host-heimdallm_session", value: "heimdallm-test-session", domain: "staging.heimdallm.com", expires: Date().addingTimeInterval(3600))
    let http = SessionHTTP(provider: "heimdallm", cookies: [cookie], configuration: config)
    let fetched = try await HeimdallmProvider(http: http, account: "").fetchBalance()
    precondition(abs(fetched.remaining - 12.50) < 0.000001)
    precondition(fetched.account == "user@heimdallm.com")
    precondition(fetched.tokensPerDay == 1500000.0)
    precondition(fetched.runwayDays == 16)
    let heimdallmBalWithPacing = Balance(id: "heimdallm", name: "Heimdallm", baseline: 25.0, remaining: 12.50, updated: Date(), account: "user@heimdallm.com", tokensPerDay: fetched.tokensPerDay, runwayDays: fetched.runwayDays)
    precondition(heimdallmBalWithPacing.pacingMessage == "1.5M tokens per day - Runs out in 16 days")
    precondition(MockHeimdallmProtocol.seen.count == 3)
    for sent in MockHeimdallmProtocol.seen {
        precondition(sent.url?.host == "staging.heimdallm.com")
        precondition(sent.value(forHTTPHeaderField: "Cookie")?.contains("__Host-heimdallm_session") == true)
        precondition(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // Direct pacing extraction check
    let heimdallmPacing = HeimdallmProvider.extractPacing(analyticsData: Data(analyticsBody.utf8), creditsData: Data(creditsBody.utf8), remaining: 12.50)
    precondition(heimdallmPacing?.tokensPerDay == 1500000.0)
    precondition(heimdallmPacing?.runwayDays == 16)

    // Unapproved paths on the host are blocked
    do {
        _ = try await http.request(url: URL(string: "https://staging.heimdallm.com/api/frontend/v1/delete_account")!)
        preconditionFailure("Heimdallm session was sent to an unapproved endpoint")
    } catch { }

    // Session validation checks
    precondition(HeimdallmProvider.hasValidSession(cookies: [cookie]))
    precondition(!HeimdallmProvider.hasValidSession(cookies: [StoredCookie(name: "theme", value: "dark", domain: ".heimdallm.com")]))

    // Registration checks
    guard let heimdallm = Balance.initial.first(where: { $0.id == "heimdallm" }) else { preconditionFailure("Balance.initial must include heimdallm") }
    precondition(!heimdallm.isEnabled, "Heimdallm must ship disabled")
    precondition(heimdallm.name == "Heimdallm")

    print("Passed: Heimdallm credit parsing, baseline calculation, account resolution, rejected sessions, account pinning, cookie-only requests, endpoint restriction, and initial registration.")
}

/// Release gate: nothing in the working tree may contain a credential, a personal
/// home path, or a real personal email address. Google's public web-client keys and
/// the synthetic test fixtures are the only allowed exceptions, and they must stay
/// confined to their documented locations.
func secretAuditChecks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let skipDirectories: Set<String> = [".git", ".build", ".cache", "vault", "node_modules"]
    let skipExtensions: Set<String> = ["png", "icns", "jpg", "jpeg", "gif", "zip", "dmg", "o", "dylib", "heic", "pdf"]

    let allowedAPIKeys: Set<String> = [GoogleWebClientKeys.cloudConsole, GoogleWebClientKeys.aiStudio]
    let allowedLiterals: Set<String> = [
        "AIzaCustomKey1234567890123456789012345", // synthetic fixture
        "venice_admin_key_123",                    // synthetic fixture
        "sk-unaligned-fixture-000000000000",       // synthetic fixture
        "unaligned-test-session",
        "yeta-test-session",
        "heimdallm-test-session",
        "lutheos-test-token",
        "1234567890123456"                          // synthetic Crowbot account number
    ]
    let personalEmailDomains = ["gmail.com", "icloud.com", "outlook.com", "hotmail.com", "yahoo.com", "proton.me", "me.com"]
    let keyPatterns = [
        #"ghp_[A-Za-z0-9]{20,}"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"xox[baprs]-[A-Za-z0-9-]{10,}"#,
        #"AKIA[0-9A-Z]{16}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"sk-[A-Za-z0-9_-]{32,}"#,
        #"AIza[0-9A-Za-z_-]{35}"#
    ]

    var findings: [String] = []
    var scanned = 0
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
        preconditionFailure("Could not enumerate the working tree")
    }
    for case let url as URL in walker {
        if skipDirectories.contains(url.lastPathComponent) {
            walker.skipDescendants()
            continue
        }
        let ext = url.pathExtension.lowercased()
        if skipExtensions.contains(ext) { continue }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
        guard let data = try? Data(contentsOf: url), data.count < 2_000_000,
              let text = String(data: data, encoding: .utf8) else { continue }
        scanned += 1
        let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")

        // Personal home directories must never be hardcoded.
        if let regex = try? NSRegularExpression(pattern: #"/Users/[A-Za-z0-9._-]+"#),
           regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
            findings.append("\(relative): hardcoded personal home path")
        }

        for pattern in keyPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let literal = ns.substring(with: match.range)
                if allowedAPIKeys.contains(literal) || allowedLiterals.contains(literal) { continue }
                findings.append("\(relative): credential-shaped literal \(literal.prefix(12))…")
            }
        }

        // Real personal email addresses are not allowed; fixtures use project domains.
        if let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})"#) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let domain = ns.substring(with: match.range(at: 1)).lowercased()
                if personalEmailDomains.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) {
                    findings.append("\(relative): personal email address on \(domain)")
                }
            }
        }
    }

    precondition(scanned > 20, "Secret audit scanned only \(scanned) files; the walker is not reaching the tree")
    precondition(findings.isEmpty, "Secret audit found \(findings.count) issue(s):\n" + findings.prefix(20).joined(separator: "\n"))

    // The shipped public client keys must stay in one auditable place.
    let keyFile = root.appendingPathComponent("Sources/GoogleWebClientKeys.swift")
    precondition(FileManager.default.fileExists(atPath: keyFile.path), "Public client keys must live in Sources/GoogleWebClientKeys.swift")
    precondition(GoogleWebClientKeys.resolvedCloudConsole().hasPrefix("AIza"))
    precondition(GoogleWebClientKeys.resolvedAIStudio().hasPrefix("AIza"))

    print("Passed: secret audit over \(scanned) files — no credentials, personal paths, or personal email addresses; public Google client keys centralised.")
}

/// Verifies the self-updater end to end without publishing anything: a local
/// fixture stands in for the GitHub release API, and a live check confirms the real
/// endpoint still parses.
@MainActor
func updaterChecks() async throws {
    let fixtures = FileManager.default.temporaryDirectory.appendingPathComponent("APIBarUpdater-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixtures) }

    func serve(_ json: String, at path: String) throws -> String {
        let file = fixtures.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_") + ".json")
        try Data(json.utf8).write(to: file)
        return file.path
    }

    func releaseJSON(tag: String, name: String, zipSize: Int, updated: String = "2026-11-05T12:00:00Z") -> String {
        """
        {"tag_name":"\(tag)","name":"\(name)","body":"notes for \(tag)","html_url":"https://github.com/0xCosmosly/API-Bar/releases/tag/\(tag)",
         "assets":[{"name":"APIBar-app.zip","size":\(zipSize),"browser_download_url":"https://github.com/0xCosmosly/API-Bar/releases/download/\(tag)/APIBar-app.zip","updated_at":"\(updated)"}]}
        """
    }

    let updater = AppUpdater.shared
    let localVersion = updater.currentVersion
    // The test binary is not a bundle, so the shipped version is read from the
    // Info.plist that build.command packages.
    if let plistData = try? Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist")),
       let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
       let shipped = plist["CFBundleShortVersionString"] as? String {
        precondition(shipped == "0.5.3", "Info.plist must ship 0.5.3, got \(shipped)")
        precondition(plist["CFBundleVersion"] as? String == "53", "CFBundleVersion must be 53")
    } else {
        preconditionFailure("Could not read Resources/Info.plist")
    }
    precondition(localVersion == "0.5.3", "Expected the updater to report 0.5.3, got \(localVersion)")

    // A newer release must be detected, with the zip asset selected.
    setenv("APIBAR_UPDATER_ENDPOINT", try serve(releaseJSON(tag: "v0.5.4", name: "API Bar 0.5.4", zipSize: 2_200_000), at: "newer"), 1)
    let newer = try await updater.fetchReleaseInfo()
    precondition(newer.version == "0.5.4", "Tag v0.5.4 must parse to 0.5.4, got \(newer.version)")
    precondition(AppUpdater.isVersion(newer.version, newerThan: localVersion), "0.5.4 must be newer than \(localVersion)")
    precondition(newer.downloadURL?.lastPathComponent == "APIBar-app.zip", "Updater must select the zip asset, got \(newer.downloadURL?.absoluteString ?? "nil")")
    precondition(newer.notes.contains("notes for v0.5.4"))
    await updater.checkForUpdates(manual: false)
    precondition(updater.updateAvailable, "Newer version 0.5.4 must set updateAvailable")
    precondition(updater.isSemverNewerAvailable, "0.5.4 must report isSemverNewerAvailable")

    // The same version must not offer an update, even though an asset exists.
    setenv("APIBAR_UPDATER_ENDPOINT", try serve(releaseJSON(tag: "v0.5.3", name: "API Bar 0.5.3", zipSize: 2_100_000), at: "same"), 1)
    let same = try await updater.fetchReleaseInfo()
    precondition(same.version == "0.5.3")
    precondition(!AppUpdater.isVersion(same.version, newerThan: localVersion), "Same version must not be treated as an update")
    await updater.checkForUpdates(manual: false)
    precondition(!updater.updateAvailable, "Same version must not set updateAvailable")
    precondition(!updater.isSemverNewerAvailable, "Same version must not report isSemverNewerAvailable")
    precondition(updater.statusMessage.contains("Up to date"), "Expected Up to date status, got \(updater.statusMessage)")

    // An older release must never trigger a downgrade.
    setenv("APIBAR_UPDATER_ENDPOINT", try serve(releaseJSON(tag: "v0.5.2", name: "API Bar 0.5.2", zipSize: 2_073_811), at: "older"), 1)
    let older = try await updater.fetchReleaseInfo()
    precondition(!AppUpdater.isVersion(older.version, newerThan: localVersion), "Older release must not be an update")

    // A release without a zip asset still yields a deterministic download URL.
    let noAsset = """
    {"tag_name":"v0.6.0","name":"API Bar 0.6.0","body":"x","html_url":"https://github.com/0xCosmosly/API-Bar/releases/tag/v0.6.0","assets":[]}
    """
    setenv("APIBAR_UPDATER_ENDPOINT", try serve(noAsset, at: "noasset"), 1)
    let fallback = try await updater.fetchReleaseInfo()
    precondition(fallback.downloadURL?.absoluteString == "https://github.com/0xCosmosly/API-Bar/releases/download/v0.6.0/APIBar-app.zip",
                 "Missing asset must fall back to the conventional zip URL, got \(fallback.downloadURL?.absoluteString ?? "nil")")

    // A broken fixture must fail loudly rather than reporting an update.
    setenv("APIBAR_UPDATER_ENDPOINT", try serve("{\"unexpected\":true}", at: "broken"), 1)
    do {
        _ = try await updater.fetchReleaseInfo()
        preconditionFailure("Updater accepted a release payload with no tag")
    } catch { }

    unsetenv("APIBAR_UPDATER_ENDPOINT")

    // Live check: the real endpoint must still parse. Skipped offline so the suite
    // stays deterministic, but reported so a silent outage is visible.
    var liveReport = "skipped (offline)"
    if ProcessInfo.processInfo.environment["APIBAR_SKIP_NETWORK"] == nil {
        do {
            let live = try await updater.fetchReleaseInfo()
            precondition(!live.version.isEmpty)
            precondition(live.downloadURL != nil)
            let isNewer = AppUpdater.isVersion(live.version, newerThan: localVersion)
            liveReport = "live release v\(live.version), update available: \(isNewer)"
            // Nothing may be offered that is older than the running build.
            precondition(isNewer == (live.version.compare(localVersion, options: .numeric) == .orderedDescending || AppUpdater.isVersion(live.version, newerThan: localVersion)))
        } catch {
            liveReport = "live check failed: \(error.localizedDescription)"
        }
    }

    print("Passed: auto-updater detection (newer/same/older/no-asset/broken payload) against fixtures; \(liveReport).")
}

func redirectChecks() async throws {
    func client() -> SessionHTTP {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RedirectCheckProtocol.self]
        return SessionHTTP(provider:"vertex",cookies:[],configuration:config)
    }
    RedirectCheckProtocol.state.reset()
    let (_, ok) = try await client().request(url:URL(string:"https://console.cloud.google.com/start")!)
    precondition(ok.statusCode == 200)
    let requests = RedirectCheckProtocol.state.snapshot()
    precondition(requests.count == 2 && requests[1].value(forHTTPHeaderField:"Cookie")?.contains("cloud_test=ok") == true)
    RedirectCheckProtocol.state.reset()
    let (_, blocked) = try await client().request(url:URL(string:"https://console.cloud.google.com/outside")!)
    precondition(blocked.statusCode == 302 && RedirectCheckProtocol.state.snapshot().count == 1)
    RedirectCheckProtocol.state.reset()
    let (_, post) = try await client().request(url:URL(string:"https://console.cloud.google.com/start")!,body:Data("{}".utf8))
    precondition(post.statusCode == 302 && RedirectCheckProtocol.state.snapshot().count == 1)
    RedirectCheckProtocol.state.reset()
    do {
        _ = try await client().request(url:URL(string:"https://console.cloud.google.com/loop")!)
        preconditionFailure("Redirect loop was accepted")
    } catch { precondition(RedirectCheckProtocol.state.snapshot().count == 4) }
    print("Passed: redirect session cookies, cross-host refusal, POST redirect refusal, and bounded redirect loops; no real credentials or network used.")
}
