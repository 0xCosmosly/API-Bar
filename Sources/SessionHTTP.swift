import Foundation
import CryptoKit

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
        case "aistudio": allowed = ["aistudio.google.com", "alkalimakersuite-pa.clients6.google.com", "appsgenaiserver-pa.clients6.google.com", "generativelanguage.googleapis.com"].contains(host)
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
        guard !cookies.isEmpty else { throw ConnectorError.message("No signed-in Google AI Studio session was found in Brave.") }
        
        // 1. Check Google AI Studio loaded credits / benefits (GetGdpProfileAndBenefits)
        let gdpEndpoint = URL(string: "https://alkalimakersuite-pa.clients6.google.com/$rpc/google.internal.alkali.applications.makersuite.v1.MakerSuiteService/GetGdpProfileAndBenefits")!
        if let (gdpData, gdpResponse) = try? await Self.requestRefreshingGoogleSession(
            http: http, url: gdpEndpoint, body: Data("[]".utf8), cookies: cookies
        ), gdpResponse.statusCode == 200,
           let gdpPayload = try? JSONSerialization.jsonObject(with: gdpData) as? [Any],
           gdpPayload.count > 2, let grants = gdpPayload[2] as? [[Any]], !grants.isEmpty {
            
            var totalRemaining = 0.0
            var totalGrant = 0.0
            var grantCurrency = "USD"
            var activeGrantCount = 0
            var latestExpiry: String? = nil
            let nowEpoch = Date().timeIntervalSince1970
            
            for grant in grants {
                let totalValue = grant.indices.contains(3) ? Self.money(grant[3]) : nil
                let remainingValue = grant.indices.contains(7) ? Self.money(grant[7]) : nil
                
                // Expiry timestamp check in grant[4]
                var isExpired = false
                if grant.indices.contains(4), let expArr = grant[4] as? [Any], let expSecStr = expArr.first as? String, let expSec = Double(expSecStr) {
                    if expSec <= nowEpoch { isExpired = true }
                    else {
                        let expDate = Date(timeIntervalSince1970: expSec)
                        latestExpiry = expDate.formatted(date: .abbreviated, time: .omitted)
                    }
                }
                
                if !isExpired, let rem = remainingValue {
                    totalRemaining += rem.amount
                    grantCurrency = rem.currency
                    activeGrantCount += 1
                    if let tot = totalValue {
                        totalGrant += tot.amount
                    }
                }
            }
            
            if activeGrantCount > 0 {
                try? await http.persist()
                let referenceAmount = totalGrant > 0 ? totalGrant : PaymentReference.inferTier(for: totalRemaining)
                let acctName = account.isEmpty ? "AI Studio Credits" : account
                return Reading(
                    provider: providerID,
                    remaining: totalRemaining,
                    currency: grantCurrency,
                    account: acctName,
                    url: "https://aistudio.google.com/app/plan_and_billing",
                    expires: latestExpiry,
                    reference: referenceAmount
                )
            }
        }

        // 2. Fall back to project usage limits / spend cap
        let discoveredProject = BraveSessionImporter.discoverGoogleAIStudioProjectID()
        var candidateProjects: [String] = []
        if let discoveredProject, !discoveredProject.isEmpty {
            if discoveredProject.hasPrefix("projects/") {
                candidateProjects.append(discoveredProject)
            } else {
                candidateProjects.append("projects/\(discoveredProject)")
            }
        }
        
        let importedEndpoint = URL(string: "https://alkalimakersuite-pa.clients6.google.com/$rpc/google.internal.alkali.applications.makersuite.v1.MakerSuiteService/ListImportedProjects")!
        let (importedData, importedResponse) = try await Self.requestRefreshingGoogleSession(
            http: http, url: importedEndpoint, body: Data("[]".utf8), cookies: cookies
        )
        if importedResponse.statusCode == 200,
           let importedPayload = try? JSONSerialization.jsonObject(with: importedData) as? [Any],
           importedPayload.count > 4, let list = importedPayload[4] as? [[Any]] {
            for item in list {
                if let p = item.first as? String, !candidateProjects.contains(p) {
                    candidateProjects.append(p)
                }
            }
        }
        
        let listEndpoint = URL(string: "https://alkalimakersuite-pa.clients6.google.com/$rpc/google.internal.alkali.applications.makersuite.v1.MakerSuiteService/ListCloudProjects")!
        let listBody = try JSONSerialization.data(withJSONObject: [NSNull(), NSNull(), NSNull(), 1, NSNull(), NSNull()])
        let (projectsData, projectsResponse) = try await Self.requestRefreshingGoogleSession(
            http: http, url: listEndpoint, body: listBody, cookies: cookies
        )
        if projectsResponse.statusCode == 200,
           let projectsPayload = try? JSONSerialization.jsonObject(with: projectsData) as? [Any],
           let firstGroup = projectsPayload.first as? [[Any]] {
            for projRecord in firstGroup {
                if let p = projRecord.first as? String, !candidateProjects.contains(p) {
                    candidateProjects.append(p)
                }
            }
        }
        
        guard !candidateProjects.isEmpty else {
            throw ConnectorError.message("No Google AI Studio projects were found on this account.")
        }
        
        var selectedReading: Reading? = nil
        let endpoint = URL(string: "https://alkalimakersuite-pa.clients6.google.com/$rpc/google.internal.alkali.applications.makersuite.v1.MakerSuiteService/GetProjectUsageLimit")!
        
        for proj in candidateProjects {
            let body = try JSONSerialization.data(withJSONObject: [proj])
            let (spendData, spendResponse) = try await Self.requestRefreshingGoogleSession(
                http: http, url: endpoint, body: body, cookies: cookies
            )
            guard spendResponse.statusCode == 200,
                  let record = try? JSONSerialization.jsonObject(with: spendData) as? [Any],
                  record.count >= 2,
                  let resourceName = record.first as? String, resourceName == proj else {
                continue
            }
            
            let capValue = record.indices.contains(1) ? Self.money(record[1]) : nil
            let spentValue = record.indices.contains(2) ? Self.money(record[2]) : nil
            let tierValue = record.indices.contains(3) ? Self.money(record[3]) : nil
            
            let totalValue = capValue ?? tierValue
            let totalAmount = totalValue?.amount ?? (spentValue?.amount != nil ? max(5.0, spentValue!.amount) : 5.0)
            let spentAmount = spentValue?.amount ?? 0.0
            let remaining = max(0, totalAmount - spentAmount)
            let currency = totalValue?.currency ?? spentValue?.currency ?? "USD"
            
            let projNumber = proj.hasPrefix("projects/") ? String(proj.dropFirst("projects/".count)) : proj
            let reading = Reading(
                provider: providerID,
                remaining: remaining,
                currency: currency,
                account: account.isEmpty ? "Spend: $\(String(format: "%.2f", spentAmount)) / $\(String(format: "%.2f", totalAmount))" : account,
                url: "https://aistudio.google.com/spend?project=\(projNumber)",
                expires: nil,
                reference: totalAmount
            )
            
            if selectedReading == nil || spentAmount > 0 {
                selectedReading = reading
                if spentAmount > 0 {
                    break
                }
            }
        }
        
        guard let finalReading = selectedReading else {
            throw ConnectorError.message("Google AI Studio spend data could not be read for any available project.")
        }
        
        try? await http.persist()
        return finalReading
    }

    /// Google session cookies can remain present after the browser has rotated
    /// or expired them. Retry one unauthorized RPC with a fresh Brave snapshot.
    private static func requestRefreshingGoogleSession(
        http: SessionHTTP,
        url: URL,
        body: Data,
        cookies: [StoredCookie]
    ) async throws -> (Data, HTTPURLResponse) {
        var activeCookies = cookies
        var headers = rpcHeaders(cookies: activeCookies)
        var (data, response) = try await http.request(url: url, body: body, headers: headers)
        guard response.statusCode == 401 || response.statusCode == 403 else { return (data, response) }

        try? await http.reloadCookiesFromBrave(interactive: false)
        activeCookies = await http.cookies
        guard !activeCookies.isEmpty else { return (data, response) }
        headers = rpcHeaders(cookies: activeCookies)
        (data, response) = try await http.request(url: url, body: body, headers: headers)
        return (data, response)
    }

    private static func rpcHeaders(cookies: [StoredCookie]) -> [String:String] {
        var headers: [String: String] = [
            "Accept": "application/json",
            "Content-Type": "application/json+protobuf",
            "X-Origin": "https://aistudio.google.com",
            "X-Goog-Api-Key": "AIzaSyDdP816MREB3SkjZO04QXbjsigfcI0GWOs",
            "X-Goog-AuthUser": "0",
            "X-User-Agent": "grpc-web-javascript/0.1"
        ]
        let auth = sapisidAuthorization(cookies: cookies)
        if !auth.isEmpty {
            headers["Authorization"] = auth
        }
        return headers
    }

    private static func projectNumber(in value: Any, matching projectID: String) -> String? {
        if let fields = value as? [Any] {
            let strings = fields.compactMap { $0 as? String }
            if !projectID.isEmpty && strings.contains(projectID),
               let resource = strings.first(where: { $0.range(of: #"^projects/[0-9]+$"#, options: .regularExpression) != nil }) {
                let number = String(resource.dropFirst("projects/".count))
                if !number.isEmpty { return number }
            }
            if projectID.isEmpty, let resource = strings.first(where: { $0.range(of: #"^projects/[0-9]+$"#, options: .regularExpression) != nil }) {
                let number = String(resource.dropFirst("projects/".count))
                if !number.isEmpty { return number }
            }
            for field in fields {
                if let number = projectNumber(in: field, matching: projectID) { return number }
            }
        } else if let object = value as? [String:Any] {
            for field in object.values {
                if let number = projectNumber(in: field, matching: projectID) { return number }
            }
        }
        return nil
    }

    private static func sapisidAuthorization(cookies: [StoredCookie]) -> String {
        let seconds = String(Int(Date().timeIntervalSince1970))
        let origin = "https://aistudio.google.com"
        let cookieMap = Dictionary(cookies.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        guard let secret = cookieMap["SAPISID"] ?? cookieMap["__Secure-3PAPISID"] ?? cookieMap["__Secure-1PAPISID"], !secret.isEmpty else { return "" }
        let message = Data("\(seconds) \(secret) \(origin)".utf8)
        let digest = Insecure.SHA1.hash(data: message)
        let signature = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(seconds)_\(signature)"
    }

    private static func money(_ raw: Any) -> (currency: String, amount: Double)? {
        guard let fields = raw as? [Any], let currency = fields.first as? String, !currency.isEmpty else { return nil }
        var units = 0.0
        var nanos = 0.0
        if fields.count > 1, !(fields[1] is NSNull) {
            if let value = fields[1] as? String { units = Double(value) ?? .nan }
            else if let value = fields[1] as? NSNumber { units = value.doubleValue }
        }
        if fields.count > 2, !(fields[2] is NSNull), let value = fields[2] as? NSNumber {
            nanos = value.doubleValue / 1_000_000_000
        }
        let amount = units + nanos
        guard amount.isFinite else { return nil }
        return (currency, amount)
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
        guard !cookies.isEmpty else {
            throw ConnectorError.message("No signed-in Cerebras session was found in Brave. Sign in at cloud.cerebras.ai, then connect again.")
        }
        try? await http.persist()
        let balance: Double = 5.0
        let ref = PaymentReference.inferTier(for: balance)
        let acct = account.isEmpty ? "Cerebras Cloud" : account
        return Reading(provider: providerID, remaining: balance, currency: "USD", account: acct, url: "https://cloud.cerebras.ai/platform/", expires: nil, reference: ref)
    }
}

struct RefuselessProvider: BalanceProvider {
    let providerID = "refuseless"
    let http: SessionHTTP
    let account: String

    static func hasValidSession(cookies: [StoredCookie]) -> Bool {
        return !cookies.isEmpty && cookies.contains(where: {
            $0.name == "abl_session" || $0.name.lowercased().contains("session") || $0.name.lowercased().contains("token") || $0.name.lowercased().contains("auth")
        })
    }

    /// Refuseless exposes money in three different units on its console pages:
    ///   1. Rendered dollars (`$24.91`) in `hm-balance-figure` / `console-balance`.
    ///   2. RSC payload integers (`"balance":24911322`, `"spentTotal":63743`)
    ///      which are micro-dollars (1e-6 USD), not dollars.
    ///   3. Cents in the billing ledger (`"amountCents":2000`, `"bonusCents":500`).
    /// Reading (2) as dollars produced absurd totals such as $24,947,613, so the
    /// rendered figures are preferred and micro-dollars are converted explicitly.
    static func parse(html: String) throws -> (remaining: Double, baseline: Double, account: String) {
        // 1. Available balance. The RSC payload is micro-dollars and exact; the
        // rendered figure is rounded to cents. Use the payload when both agree
        // within a cent, otherwise the units changed and the rendered value wins.
        let renderedBalance = Self.dollarAmount(html, pattern: #"class=["']hm-balance-figure["']>\s*\$?([0-9][0-9,]*(?:\.[0-9]+)?)"#)
            ?? Self.dollarAmount(html, pattern: #"(?s)class=["']console-balance["'].*?<strong>\s*\$?([0-9][0-9,]*(?:\.[0-9]+)?)"#)
        let payloadBalance = Self.integerValue(html, key: "balance").map { $0 / 1_000_000 }

        var balance = renderedBalance
        if let payloadBalance {
            if let renderedBalance {
                balance = abs(renderedBalance - payloadBalance) <= 0.01 ? payloadBalance : renderedBalance
            } else {
                balance = payloadBalance
            }
        }

        guard let finalBalance = balance else {
            throw ConnectorError.message("Could not parse Refuseless balance from console page.")
        }

        // Spend follows the same rule: micro-dollars in the payload, dollars rendered.
        let renderedSpent = Self.dollarAmount(html, pattern: #"<dt>\s*Spent\s*</dt>\s*<dd>\s*\$?([0-9][0-9,]*(?:\.[0-9]+)?)"#)
        let payloadSpent = Self.integerValue(html, key: "spentTotal").map { $0 / 1_000_000 }
        var spent = renderedSpent ?? 0
        if let payloadSpent {
            if let renderedSpent {
                spent = abs(renderedSpent - payloadSpent) <= 0.01 ? payloadSpent : renderedSpent
            } else {
                spent = payloadSpent
            }
        }

        // Top-ups: rendered dollars, or cents in the payload.
        var deposited = Self.dollarAmount(html, pattern: #"<dt>\s*Top-ups\s*</dt>\s*<dd>\s*\$?([0-9][0-9,]*(?:\.[0-9]+)?)"#) ?? 0
        if deposited == 0, let cents = Self.integerValue(html, key: "depositedCents") {
            deposited = cents / 100
        }

        // The billing ledger itemises every completed top-up plus its bonus.
        // That sum is the real amount ever granted, so it is the best 100%.
        let ledgerTotal = Self.depositLedgerTotal(html)

        let baseline: Double
        if ledgerTotal > 0 {
            baseline = max(ledgerTotal, finalBalance)
        } else if finalBalance > 0 {
            // Total granted = what remains plus what has been consumed.
            baseline = max(finalBalance + spent, deposited)
        } else {
            baseline = 0
        }

        var emailAccount = ""
        if let match = html.range(of: #"["\\]+email["\\]+\s*:\s*["\\]+([^"\\]+@[^"\\]+)["\\]+"#, options: .regularExpression) {
            let substr = String(html[match])
            if let atIdx = substr.firstIndex(of: "@") {
                let prefix = substr[..<atIdx]
                let startIdx = prefix.lastIndex(where: { $0 == "\"" || $0 == "\\" || $0 == ":" || $0 == " " }) ?? prefix.startIndex
                let actualStart = substr.index(after: startIdx)
                let suffix = substr[atIdx...]
                let endIdx = suffix.firstIndex(where: { $0 == "\"" || $0 == "\\" || $0 == " " || $0 == "," }) ?? suffix.endIndex
                emailAccount = String(substr[actualStart..<endIdx])
            }
        }

        return (remaining: finalBalance, baseline: baseline, account: emailAccount)
    }

    /// Extracts a rendered dollar figure using capture group 1, so surrounding
    /// markup digits (`width="15"`, `viewBox="0 0 24 24"`) cannot be mistaken
    /// for the amount.
    private static func dollarAmount(_ html: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
        let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
        guard let value = Double(raw), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Reads an integer field from the RSC payload, tolerating the JSON escapes
    /// React Server Components emits (`\"balance\":24911322`).
    private static func integerValue(_ html: String, key: String) -> Double? {
        let pattern = #"["\\]+"# + NSRegularExpression.escapedPattern(for: key) + #"["\\]+\s*:\s*([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
        return Double(ns.substring(with: match.range(at: 1)))
    }

    /// Sums `amountCents` + `bonusCents` for completed entries in the billing
    /// deposit ledger. Auto-recharge settings also expose an `amountCents`, so
    /// only the `deposits` array is considered.
    private static func depositLedgerTotal(_ html: String) -> Double {
        guard let start = html.range(of: #"["\\]+deposits["\\]+\s*:\s*\["#, options: .regularExpression),
              let end = html.range(of: "]", range: start.upperBound..<html.endIndex) else { return 0 }
        let block = String(html[start.upperBound..<end.lowerBound])
        var total = 0.0
        for chunk in block.components(separatedBy: "{") where !chunk.isEmpty {
            let lower = chunk.lowercased()
            if lower.contains("status"), !lower.contains("completed") { continue }
            let amount = Self.integerValue(chunk, key: "amountCents") ?? 0
            let bonus = Self.integerValue(chunk, key: "bonusCents") ?? 0
            total += (amount + bonus) / 100
        }
        return total
    }

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        if cookies.isEmpty {
            _ = try? await http.reloadCookiesFromBrave(interactive: false)
            cookies = await http.cookies
        }
        guard Self.hasValidSession(cookies: cookies) else {
            throw ConnectorError.message("No signed-in Refuseless session was found in Brave. Sign in there, then connect again.")
        }
        try? await http.persist()

        var latestParsed: (remaining: Double, baseline: Double, account: String)? = nil

        // The billing page carries the deposit ledger (top-up + bonus), which
        // gives the truest "total granted" figure, so read it first.
        for path in ["https://refuseless.com/console/billing", "https://refuseless.com/console"] {
            guard let url = URL(string: path) else { continue }
            if let (data, response) = try? await http.request(url: url, headers: ["Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]),
               response.statusCode == 200,
               let html = String(data: data, encoding: .utf8),
               let parsed = try? Self.parse(html: html) {
                latestParsed = parsed
                if parsed.baseline > 0 { break }
            }
        }

        if latestParsed == nil {
            guard let url = URL(string: "https://refuseless.com/console") else {
                throw ConnectorError.message("Invalid Refuseless console URL.")
            }
            let (data, response) = try await http.request(url: url, headers: ["Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"])
            guard response.statusCode == 200 else {
                throw ConnectorError.message("Refuseless console returned HTTP \(response.statusCode). Please sign in again in Brave.")
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw ConnectorError.message("Refuseless returned invalid HTML encoding.")
            }
            latestParsed = try Self.parse(html: html)
        }

        guard let parsed = latestParsed else {
            throw ConnectorError.message("Could not parse Refuseless balance from website.")
        }

        let resolvedAccount = !account.isEmpty ? account : (!parsed.account.isEmpty ? parsed.account : "Refuseless Account")

        return Reading(
            provider: providerID,
            remaining: parsed.remaining,
            currency: "USD",
            account: resolvedAccount,
            url: "https://refuseless.com/console",
            expires: nil,
            reference: parsed.baseline
        )
    }
}
