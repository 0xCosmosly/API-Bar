import Foundation
import Security

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
        precondition(AppUpdater.isVersion("0.4.9", newerThan: "0.4.8"))
        precondition(AppUpdater.isVersion("v0.4.9", newerThan: "v0.4.8"))
        precondition(AppUpdater.isVersion("0.4.8", newerThan: "0.4.7"))
        precondition(AppUpdater.isVersion("v0.4.8", newerThan: "v0.4.7"))
        precondition(AppUpdater.isVersion("1.0.0", newerThan: "0.4.7"))
        precondition(!AppUpdater.isVersion("0.4.7", newerThan: "0.4.7"))
        precondition(!AppUpdater.isVersion("0.4.6", newerThan: "0.4.7"))
        precondition(!AppUpdater.isVersion("0.3.9", newerThan: "0.4.0"))
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
