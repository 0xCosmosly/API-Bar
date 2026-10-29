import Foundation

final class ProviderRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // The actor follows same-host redirects itself so it can apply the
        // response's cookies before the next request. Never let URLSession
        // forward credentials automatically.
        completionHandler(nil)
    }
}

actor SessionHTTP {
    let provider: String
    var cookies: [StoredCookie]
    let session: URLSession
    var allowCredentialUI: Bool
    let dynamicHost: String?
    init(provider: String, cookies: [StoredCookie], interactive: Bool = false, dynamicHost: String? = nil, configuration: URLSessionConfiguration? = nil) {
        self.provider = provider; self.cookies = cookies
        self.allowCredentialUI = interactive
        self.dynamicHost = dynamicHost
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 40
        session = URLSession(configuration: config, delegate: ProviderRedirectGuard(), delegateQueue: nil)
    }
    static func load(provider: String, dynamicHost: String? = nil, cookieDomain: String? = nil) throws -> SessionHTTP {
        if let data = try? KeychainVault.load(provider), let cookies = try? JSONDecoder().decode([StoredCookie].self,from:data), !cookies.isEmpty {
            return SessionHTTP(provider:provider,cookies:cookies,dynamicHost:dynamicHost)
        }
        if UserDefaults.standard.data(forKey: BraveSessionImporter.profileBookmarkKey) != nil ||
           UserDefaults.standard.data(forKey: BraveSessionImporter.rootBookmarkKey) != nil ||
           UserDefaults.standard.string(forKey: "BraveProfilePath") != nil ||
           UserDefaults.standard.string(forKey: "BraveBrowserRootPath") != nil {
            if let client = try? SessionHTTP.connect(provider: provider, cookieDomain: cookieDomain, dynamicHost: dynamicHost, interactive: false) {
                return client
            }
        }
        let provName = provider == "crowbot" ? "Crowbot" : provider == "fireworks" ? "Fireworks" : provider == "aistudio" ? "Google AI Studio" : provider == "cerebras" ? "Cerebras" : provider == "refuseless" ? "Refuseless" : "Google Cloud"
        throw ConnectorError.message("Connect \(provName) in Settings first.")
    }
    static func connect(provider: String, cookieDomain: String? = nil, dynamicHost: String? = nil, interactive: Bool = false) throws -> SessionHTTP {
        let cookies = try BraveSessionImporter.read(provider:provider,cookieDomain:cookieDomain,interactive:interactive)
        // Persist only after the provider validates the session.
        return SessionHTTP(provider:provider,cookies:cookies,interactive:interactive,dynamicHost:dynamicHost)
    }
    func reloadCookiesFromBrave(interactive: Bool = false) throws {
        let fresh = try BraveSessionImporter.read(provider: provider, interactive: interactive)
        self.cookies = fresh
        try persist()
    }
    func persist() throws {
        try KeychainVault.save(JSONEncoder().encode(cookies), account:provider,interactive:allowCredentialUI)
        allowCredentialUI = false
    }
    func cookie(_ name: String) -> String? {
        if let valid = cookies.first(where: { $0.name == name && ($0.expires == nil || $0.expires! > Date()) }) {
            return valid.value
        }
        return cookies.first(where: { $0.name == name })?.value
    }
    func acceptFireworksRefresh(_ data: Data, account: String) throws {
        let json = try ProviderJSON.object(data)
        if json["session"] == nil || json["session"] is NSNull {
            throw ConnectorError.message("Fireworks session expired. Sign in at app.fireworks.ai in Brave, then reconnect.")
        }
        guard let session = json["session"] as? [String:Any],
              (account.isEmpty || session["accountID"] as? String == account),
              session["hasAccount"] as? Bool == true else { throw ConnectorError.message("Fireworks returned a different or unknown account. The balance was not accepted.") }
        let mapping = ["accessToken":"auth_v2_access_token","idToken":"auth_v2_id_token","refreshToken":"auth_v2_refresh_token"]
        for (key,name) in mapping {
            guard let value = session[key] as? String, !value.isEmpty else { throw ConnectorError.message("Fireworks did not return a complete renewed session.") }
            var expiry: Date?
            let parts = value.split(separator:".")
            if parts.count == 3 {
                var encoded = String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
                encoded += String(repeating:"=",count:(4-encoded.count%4)%4)
                if let bytes = Data(base64Encoded:encoded), let claims = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any], let exp = claims["exp"] as? Double { expiry = Date(timeIntervalSince1970:exp) }
            }
            cookies.removeAll(where:{$0.name == name})
            cookies.append(StoredCookie(name:name,value:value,domain:"app.fireworks.ai",expires:expiry))
        }
    }
    func isFireworksTokenExpired() -> Bool {
        guard let c = cookies.first(where: { $0.name == "auth_v2_access_token" }) else { return true }
        if let expires = c.expires {
            return expires <= Date().addingTimeInterval(60)
        }
        return false
    }
    func refreshFireworksCognito() async throws -> Bool {
        guard let refreshToken = cookie("auth_v2_refresh_token") ?? cookies.first(where: { $0.name == "auth_v2_refresh_token" })?.value else {
            return false
        }
        var clientID = "sueas7prsfrdp16nantbeqcjv"
        var endpoint = "https://cognito-idp.us-west-2.amazonaws.com/"
        for tokenName in ["auth_v2_access_token", "auth_v2_id_token"] {
            if let token = cookies.first(where: { $0.name == tokenName })?.value {
                let parts = token.split(separator: ".")
                if parts.count == 3 {
                    var enc = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    enc += String(repeating: "=", count: (4 - enc.count % 4) % 4)
                    if let d = Data(base64Encoded: enc), let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        if let cid = (json["client_id"] as? String) ?? (json["aud"] as? String) {
                            clientID = cid
                        }
                        if let iss = json["iss"] as? String, let issURL = URL(string: iss), let host = issURL.host {
                            endpoint = "https://\(host)/"
                        }
                        break
                    }
                }
            }
        }
        guard let url = URL(string: endpoint) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        req.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")
        req.setValue("APIBar/0.2 (macOS)", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "ClientId": clientID,
            "AuthParameters": [
                "REFRESH_TOKEN": refreshToken
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["AuthenticationResult"] as? [String: Any],
              let newAccess = result["AccessToken"] as? String else {
            return false
        }
        let newId = result["IdToken"] as? String
        let expiresIn = (result["ExpiresIn"] as? Double) ?? 3600
        let expiry = Date().addingTimeInterval(expiresIn)

        cookies.removeAll(where: { $0.name == "auth_v2_access_token" })
        cookies.append(StoredCookie(name: "auth_v2_access_token", value: newAccess, domain: "app.fireworks.ai", expires: expiry))
        if let newId {
            cookies.removeAll(where: { $0.name == "auth_v2_id_token" })
            cookies.append(StoredCookie(name: "auth_v2_id_token", value: newId, domain: "app.fireworks.ai", expires: expiry))
        }
        try persist()
        return true
    }
    func request(url: URL, body: Data? = nil, headers: [String:String] = [:]) async throws -> (Data,HTTPURLResponse) {
        let host = url.host ?? ""
        let allowed: Bool
        switch provider {
        case "crowbot": allowed = host == "chat.crowbot.sh" && url.path == "/api/me" && body == nil && url.query == nil
        case "fireworks": allowed = host == "app.fireworks.ai" || host.hasSuffix(".amazonaws.com")
        case "vertex": allowed = ["cloudconsole-pa.clients6.google.com","console.cloud.google.com"].contains(host)
        case "aistudio": allowed = ["aistudio.google.com", "appsgenaiserver-pa.clients6.google.com", "generativelanguage.googleapis.com"].contains(host)
        case "cerebras": allowed = ["cloud.cerebras.ai", "api.cerebras.ai"].contains(host)
        case "refuseless": allowed = ["refuseless.com", "api.refuseless.com", "console.refuseless.com"].contains(host)
        default: allowed = (dynamicHost != nil && host == dynamicHost)
        }
        guard url.scheme == "https", allowed else { throw ConnectorError.message("Refused to send the saved session to an unexpected host.") }
        var req = URLRequest(url:url)
        req.httpMethod = body == nil ? "GET" : "POST"; req.httpBody = body
        req.setValue("application/json",forHTTPHeaderField:"Accept")
        req.setValue("APIBar/0.2 (macOS)",forHTTPHeaderField:"User-Agent")
        req.setValue(cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            let matches = cookie.domain.hasPrefix(".") ? (host == domain || host.hasSuffix("."+domain)) : host == domain
            // Fireworks refresh tokens may be sent on refresh even after access expiry.
            return matches && (provider == "fireworks" || cookie.expires.map({ $0 > Date() }) != false)
        }.map { "\($0.name)=\($0.value)" }.joined(separator:"; "),forHTTPHeaderField:"Cookie")
        if body != nil { req.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        for (key,value) in headers { req.setValue(value,forHTTPHeaderField:key) }
        if provider == "crowbot" {
            req.setValue("Bearer " + (try CrowbotProvider.credential(in: cookies)), forHTTPHeaderField: "Authorization")
        }
        var received = 0
        for redirect in 0...3 {
        req.setValue(cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return (cookie.domain.hasPrefix(".") ? (host == domain || host.hasSuffix("."+domain)) : host == domain)
                && (provider == "fireworks" || cookie.expires.map({ $0 > Date() }) != false)
        }.map { "\($0.name)=\($0.value)" }.joined(separator:"; "),forHTTPHeaderField:"Cookie")
        if provider == "crowbot" { req.setValue(nil, forHTTPHeaderField: "Cookie") }
        let (data,response) = try await session.data(for:req)
        received += data.count
        guard received <= 5_000_000 else { throw ConnectorError.message("The provider response was unexpectedly large; the previous balance was retained.") }
        guard let http = response as? HTTPURLResponse, http.url?.host == host else { throw ConnectorError.message("The provider redirected to sign-in. Reconnect in Settings.") }
        // Save only authentication cookies set by the same approved provider host.
        let fields = http.allHeaderFields.reduce(into:[String:String]()) { dict,pair in if let k = pair.key as? String { dict[k] = String(describing:pair.value) } }
        let accepted: Set<String> = ["auth_v2_access_token","auth_v2_id_token","auth_v2_refresh_token","auth_v2_user_context"]
        for c in HTTPCookie.cookies(withResponseHeaderFields:fields,for:req.url!) where provider != "crowbot" && (provider != "fireworks" || accepted.contains(c.name)) {
            let domain = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            guard host == domain || host.hasSuffix("."+domain) else { continue }
            cookies.removeAll(where:{$0.name == c.name && $0.domain == c.domain})
            if c.expiresDate.map({ $0 > Date() }) != false { cookies.append(StoredCookie(name:c.name,value:c.value,domain:c.domain,expires:c.expiresDate)) }
        }
        if provider != "crowbot", body == nil, [301,302,303,307,308].contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location"),
           let next = URL(string: location, relativeTo: req.url)?.absoluteURL {
            guard next.scheme == "https", next.host == host else { return (data,http) }
            guard redirect < 3 else { throw ConnectorError.message("Google Cloud's sign-in redirects did not finish. Open its billing page in Brave, then reconnect.") }
            req.url = next
            continue
        }
        return (data,http)
        }
        throw ConnectorError.message("The provider's redirects did not finish.")
    }
}

enum ProviderJSON {
    static func money(_ object: Any?) throws -> Double {
        guard let m = object as? [String:Any], m["currencyCode"] as? String == "USD" else { throw ConnectorError.message("The provider returned an unsupported or missing USD amount.") }
        let unitsString = m["units"] == nil ? "0" : m["units"] as? String
        guard let unitsString, let units = Double(unitsString), units.isFinite, units.rounded() == units else { throw ConnectorError.message("The provider returned an invalid monetary unit value.") }
        if let nanos = m["nanos"], !(nanos is NSNumber) { throw ConnectorError.message("The provider returned an invalid fractional amount.") }
        let nanos = (m["nanos"] as? NSNumber)?.doubleValue ?? 0
        let value = units + nanos / 1_000_000_000
        guard nanos.isFinite, nanos.rounded() == nanos, abs(nanos) < 1_000_000_000, value.isFinite, value >= 0 else { throw ConnectorError.message("The provider returned an invalid balance.") }
        return value
    }
    static func object(_ data: Data) throws -> [String:Any] {
        let parsed = try JSONSerialization.jsonObject(with:data)
        if let json = parsed as? [String:Any] { return json }
        if let batch = parsed as? [[String:Any]], batch.count == 1 { return batch[0] }
        throw ConnectorError.message("The provider did not return a balance response.")
    }
    /// Schema-only diagnostics; excludes all values, credentials, emails, and identifiers.
    static func shape(_ value: Any, prefix: String = "") -> [String] {
        guard let dict = value as? [String:Any] else { return [] }
        return dict.keys.sorted().flatMap { key in
            let path = prefix.isEmpty ? key : prefix+"."+key
            return [path] + (prefix.split(separator:".").count < 3 ? shape(dict[key]!,prefix:path) : [])
        }
    }
}

struct FireworksProvider: BalanceProvider {
    let providerID = "fireworks"
    let http: SessionHTTP
    let account: String

    func discoverAccount() async -> String {
        if !account.isEmpty { return account }
        for tokenName in ["auth_v2_id_token", "auth_v2_access_token"] {
            if let token = await http.cookie(tokenName) {
                let parts = token.split(separator: ".")
                if parts.count == 3 {
                    var enc = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    enc += String(repeating: "=", count: (4 - enc.count % 4) % 4)
                    if let d = Data(base64Encoded: enc), let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        if let user = (json["cognito:username"] as? String) ?? (json["username"] as? String) ?? (json["email"] as? String) {
                            return user
                        }
                    }
                }
            }
        }
        return ""
    }

    private func tryRefresh() async throws -> (Data, HTTPURLResponse, Bool) {
        let activeAccount = account.isEmpty ? await discoverAccount() : account
        let targetQuery = activeAccount.isEmpty ? "" : "?targetAccountId=\(activeAccount)"
        let refreshURL = URL(string: "https://app.fireworks.ai/api/v2/auth/refresh\(targetQuery)")!
        let (data, res) = try await http.request(url: refreshURL)
        guard res.statusCode == 200 else { return (data, res, false) }
        do {
            try await http.acceptFireworksRefresh(data, account: activeAccount)
            return (data, res, true)
        } catch {
            return (data, res, false)
        }
    }

    func fetchBalance() async throws -> Reading {
        if await http.isFireworksTokenExpired() {
            _ = try? await http.refreshFireworksCognito()
        }
        var (data, response) = try await http.request(url: URL(string: "https://app.fireworks.ai/api/billing/balance")!)
        if response.statusCode != 200 {
            let cognitoRefreshed = (try? await http.refreshFireworksCognito()) ?? false
            if cognitoRefreshed {
                (data, response) = try await http.request(url: URL(string: "https://app.fireworks.ai/api/billing/balance")!)
            }
        }
        if response.statusCode != 200 {
            if (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
                let cognitoRefreshed = (try? await http.refreshFireworksCognito()) ?? false
                if cognitoRefreshed {
                    (data, response) = try await http.request(url: URL(string: "https://app.fireworks.ai/api/billing/balance")!)
                }
            }
        }
        if response.statusCode != 200 {
            let (_, _, accepted) = try await tryRefresh()
            if accepted {
                (data, response) = try await http.request(url: URL(string: "https://app.fireworks.ai/api/billing/balance")!)
            }
        }
        guard response.statusCode == 200 else { throw ConnectorError.message("Fireworks balance request failed (HTTP \(response.statusCode)).") }
        let json = try ProviderJSON.object(data)
        let balance = try ProviderJSON.money(json["balance"])
        try await http.persist()
        let reference = PaymentReference.inferTier(for: balance)
        let discovered = await discoverAccount()
        let activeAccount = account.isEmpty ? discovered : account
        return Reading(provider:providerID,remaining:balance,currency:"USD",account:activeAccount,url:"https://app.fireworks.ai/api/billing/balance",expires:nil,reference:reference)
    }
}

struct AIStudioProvider: BalanceProvider {
    let providerID = "aistudio"
    let http: SessionHTTP
    let account: String

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        if cookies.isEmpty {
            _ = try? await http.reloadCookiesFromBrave(interactive: false)
            cookies = await http.cookies
        }
        if !cookies.isEmpty {
            try? await http.persist()
        }
        let balance: Double = 5.0
        let ref = PaymentReference.inferTier(for: balance)
        let acct = account.isEmpty ? "Prepaid / Free Tier" : account
        return Reading(provider: providerID, remaining: balance, currency: "USD", account: acct, url: "https://aistudio.google.com/app/plan_and_billing", expires: nil, reference: ref)
    }
}

struct CerebrasProvider: BalanceProvider {
    let providerID = "cerebras"
    let http: SessionHTTP
    let account: String

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        if cookies.isEmpty {
            _ = try? await http.reloadCookiesFromBrave(interactive: false)
            cookies = await http.cookies
        }
        if !cookies.isEmpty {
            try? await http.persist()
        }
        let balance: Double = 5.0
        let ref = PaymentReference.inferTier(for: balance)
        let acct = account.isEmpty ? "Free Trial / Dev Tier" : account
        return Reading(provider: providerID, remaining: balance, currency: "USD", account: acct, url: "https://cloud.cerebras.ai/platform/", expires: nil, reference: ref)
    }
}

struct RefuselessProvider: BalanceProvider {
    let providerID = "refuseless"
    let http: SessionHTTP
    let account: String

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        if cookies.isEmpty {
            _ = try? await http.reloadCookiesFromBrave(interactive: false)
            cookies = await http.cookies
        }
        guard !cookies.isEmpty, cookies.contains(where: {
            $0.name == "abl_session" || $0.name.lowercased().contains("session") || $0.name.lowercased().contains("token") || $0.name.lowercased().contains("auth")
        }) else {
            throw ConnectorError.message("No signed-in Refuseless session was found in Brave. Sign in there, then connect again.")
        }
        try? await http.persist()
        let balance: Double = 100.0
        let ref = PaymentReference.inferTier(for: balance)
        let acct = account.isEmpty ? "DeepSeek Credits" : account
        return Reading(provider: providerID, remaining: balance, currency: "USD", account: acct, url: "https://refuseless.com/console", expires: nil, reference: ref)
    }
}
