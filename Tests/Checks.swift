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
        print("Passed: available Brave profiles detection without file path navigation.")
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
        let refuselessHTTP = SessionHTTP(provider: "refuseless", cookies: [refuselessCookie])
        let refuselessReading = try await RefuselessProvider(http: refuselessHTTP, account: "").fetchBalance()
        precondition(refuselessReading.provider == "refuseless")
        precondition(ReadingValidation.valid(refuselessReading, balances: Balance.initial))
        print("Passed: Refuseless session validation, reading generation, and empty session rejection.")
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
