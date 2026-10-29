import Foundation
import CryptoKit

struct GoogleProvider: BalanceProvider {
    let providerID = "vertex"
    let http: SessionHTTP
    let account: String
    static let endpoint = "https://cloudconsole-pa.clients6.google.com/v3/entityServices/BillingpricefactorsEntityService/schemas/BILLINGPRICEFACTORS_GRAPHQL:batchGraphql"
    static let signature = "2/PydlIw7s18h/dddSmzGlmxPZVxi71ZcnKjkR278Ovtw="
    static let defaultConsumerKey = "AIzaSyCI-zsRP85UVOi0DjtiCwWBwQ1djDy741g"
    static let consumerKeyDefaultsKey = "GoogleConsumerKey"

    static func consumerKey(in html: String) throws -> String {
        // Cloud Console's bootstrap names its client key LjgHrc. Other Google
        // products also embed keys on this page; do not treat them as candidates.
        let named = try NSRegularExpression(pattern: #"["']LjgHrc["']\s*:\s*["'](AIza[0-9A-Za-z_-]{35})["']"#)
        let range = NSRange(html.startIndex..., in: html)
        let keys = Set(named.matches(in: html, range: range).compactMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        })
        guard keys.count == 1, let key = keys.first else {
            throw ConnectorError.message("Google's billing client identity could not be resolved safely. Its named client configuration is missing or ambiguous.")
        }
        return key
    }

    static func resolvedConsumerKey() -> String {
        UserDefaults.standard.string(forKey: consumerKeyDefaultsKey) ?? defaultConsumerKey
    }

    func discoverConsumerKey(account: String = "") async throws -> String {
        let accountPath = account.isEmpty ? "" : "/\(account)/credits/all"
        let page = URL(string:"https://console.cloud.google.com/billing\(accountPath)")!
        do {
            let (htmlData, pageResponse) = try await http.request(url:page, headers: ["Accept":"text/html,application/xhtml+xml"])
            if pageResponse.statusCode == 200, let html = String(data:htmlData, encoding:.utf8),
               let key = try? Self.consumerKey(in: html) {
                UserDefaults.standard.set(key, forKey: Self.consumerKeyDefaultsKey)
                return key
            }
        } catch {
            // Keep going with default consumer key on failure
        }
        return Self.defaultConsumerKey
    }

    func discoverAccount() async throws -> String {
        if !account.isEmpty { return account }
        if let fromBrave = BraveSessionImporter.discoverGoogleBillingAccount(), !fromBrave.isEmpty {
            return fromBrave
        }
        let page = URL(string: "https://console.cloud.google.com/billing")!
        let (htmlData, pageResponse) = try await http.request(url: page, headers: ["Accept": "text/html,application/xhtml+xml"])
        if let redirectedURL = pageResponse.url?.absoluteString {
            let pattern = #"billing/([0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6})"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: redirectedURL, range: NSRange(redirectedURL.startIndex..., in: redirectedURL)),
               let range = Range(match.range(at: 1), in: redirectedURL) {
                return String(redirectedURL[range]).uppercased()
            }
        }
        if let html = String(data: htmlData, encoding: .utf8) {
            let pattern = #"\b([0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6})\b"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).uppercased()
            }
        }
        return account
    }

    private func executeGraphQL(consumerKey: String, account: String = "") async throws -> (Data, HTTPURLResponse) {
        let primary = await http.cookie("SAPISID")
        let fallback3P = await http.cookie("__Secure-3PAPISID")
        let fallback1P = await http.cookie("__Secure-1PAPISID")
        guard let sapisid = primary ?? fallback3P ?? fallback1P else {
            throw ConnectorError.message("The Google session is missing its billing authentication cookie. Sign in to Cloud Console in Brave and reconnect.")
        }
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let origin = "https://console.cloud.google.com"
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(sapisid) \(origin)".utf8)).map { String(format:"%02x",$0) }.joined()
        let auth = "SAPISIDHASH \(timestamp)_\(digest)"
        let varName = account.isEmpty ? "billingAccounts" : "billingAccounts/\(account)"
        let body: [String:Any] = ["operationName":"ListCreditsDetail", "querySignature":Self.signature, "variables":["name":varName], "requestContext":[:]]
        // Native requests use Google's X-Origin signing context, not a browser CORS Origin.
        return try await http.request(url:URL(string:Self.endpoint)!,body:JSONSerialization.data(withJSONObject:body),headers:["Authorization":auth,"X-Origin":origin,"X-Goog-AuthUser":"0","X-Goog-Api-Key":consumerKey])
    }

    static func isAuthError(_ json: [String: Any]) -> Bool {
        let payload: [String: Any]
        if let results = json["results"] as? [[String: Any]], let first = results.first {
            payload = first
        } else { payload = json }
        if let errors = (payload["errors"] as? [[String: Any]]) ?? (json["errors"] as? [[String: Any]]) {
            for err in errors {
                let msg = (err["message"] as? String ?? "").lowercased()
                if msg.contains("unauthenticated") || msg.contains("auth") || msg.contains("permission") || msg.contains("login") || msg.contains("expired") || msg.contains("credential") {
                    return true
                }
                if let ext = err["extensions"] as? [String: Any],
                   let status = ext["status"] as? [String: Any] {
                    let code = status["code"] as? Int ?? 0
                    if code == 16 || code == 7 { return true }
                }
            }
        }
        return false
    }

    func response(for acct: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let targetAccount = acct ?? account
        var key = Self.resolvedConsumerKey()
        do {
            let (data, res) = try await executeGraphQL(consumerKey: key, account: targetAccount)
            if res.statusCode == 200 {
                if let json = try? ProviderJSON.object(data), Self.isAuthError(json) {
                    if (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
                        let (retryData, retryRes) = try await executeGraphQL(consumerKey: key, account: targetAccount)
                        if retryRes.statusCode == 200, !Self.isAuthError((try? ProviderJSON.object(retryData)) ?? [:]) {
                            return (retryData, retryRes)
                        }
                    }
                }
                return (data, res)
            }
            if [401, 403].contains(res.statusCode) {
                if (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
                    let (retryData, retryRes) = try await executeGraphQL(consumerKey: key, account: targetAccount)
                    if retryRes.statusCode == 200 { return (retryData, retryRes) }
                }
            }
            if res.statusCode == 400 {
                if let discovered = try? await discoverConsumerKey(account: targetAccount) {
                    key = discovered
                    let (retryData, retryRes) = try await executeGraphQL(consumerKey: key, account: targetAccount)
                    if retryRes.statusCode == 200 { return (retryData, retryRes) }
                }
            }
            return (data, res)
        } catch {
            if (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
                return try await executeGraphQL(consumerKey: key, account: targetAccount)
            }
            throw error
        }
    }
    func fetchBalance() async throws -> Reading {
        var activeAccount = account
        if activeAccount.isEmpty {
            activeAccount = (try? await discoverAccount()) ?? ""
        }
        let (data,response) = try await response(for: activeAccount)
        guard response.statusCode == 200 else { throw ConnectorError.message("Google credit request failed (HTTP \(response.statusCode)). Reconnect if the session expired.") }
        let json = try ProviderJSON.object(data)
        let result: Reading
        do { result = try Self.parse(json, account: activeAccount) }
        catch {
            UserDefaults.standard.set(Self.responseFields(json), forKey: "GoogleResponseFields")
            throw error
        }
        try await http.persist()
        return result
    }
    static func responseFields(_ value: Any, prefix: String = "", depth: Int = 0) -> [String] {
        guard depth < 10 else { return [] }
        if let array = value as? [Any] {
            guard let first = array.first else { return [prefix + "[]"] }
            return responseFields(first, prefix: prefix + "[]", depth: depth + 1)
        }
        guard let dictionary = value as? [String: Any] else { return [] }
        return dictionary.keys.sorted().prefix(25).flatMap { key -> [String] in
            let path = prefix.isEmpty ? key : prefix + "." + key
            return [path] + responseFields(dictionary[key]!, prefix: path, depth: depth + 1)
        }
    }
    static func parse(_ json: [String:Any], account: String, now: Date = Date()) throws -> Reading {
        guard json["errors"] == nil, json["error"] == nil else {
            if Self.isAuthError(json) {
                throw ConnectorError.message("Google session expired. Sign in to Cloud Console in Brave and reconnect.")
            }
            throw ConnectorError.message("Google returned a billing query error; the previous balance was retained.")
        }
        let payload: [String: Any]
        if let results = json["results"] {
            guard let batch = results as? [[String: Any]], batch.count == 1,
                  batch[0]["errors"] == nil, batch[0]["error"] == nil else {
                if Self.isAuthError(json) {
                    throw ConnectorError.message("Google session expired. Sign in to Cloud Console in Brave and reconnect.")
                }
                throw ConnectorError.message("Google returned an incomplete or failed billing batch; the previous balance was retained.")
            }
            payload = batch[0]
        } else { payload = json }
        let root = (payload["data"] as? [String:Any]) ?? payload
        guard let credits = root["creditsQuery"] as? [String:Any], let listing = credits["listCredits"] as? [String:Any], let rows = listing["data"] as? [[String:Any]] else { throw ConnectorError.message("Google did not return a complete credit-grant list.") }
        guard rows.count < 20000, (listing["nextPageToken"] as? String ?? "").isEmpty else { throw ConnectorError.message("Google credit pagination is incomplete; the previous balance was retained.") }
        let iso = ISO8601DateFormatter()
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: Any?) -> Date? {
            guard let text = value as? String else { return nil }
            return iso.date(from: text) ?? fractionalISO.date(from: text)
        }
        var total = 0.0
        var grantTotal = 0.0
        var ends: [Date] = []
        var seen = Set<String>()
        var resolvedAccount = account
        for row in rows {
            if resolvedAccount.isEmpty, let bName = row["billingAccountName"] as? String, bName.hasPrefix("billingAccounts/") {
                resolvedAccount = String(bName.dropFirst("billingAccounts/".count))
            }
            guard row["billingAccountName"] as? String == "billingAccounts/\(resolvedAccount)", let name = row["name"] as? String, !name.isEmpty else { throw ConnectorError.message("Google returned a credit from a different or unknown billing account.") }
            guard seen.insert(name).inserted else { throw ConnectorError.message("Google returned a duplicate credit grant; a double-counted balance was not accepted.") }
            guard let end = date(row["endTime"]) else { throw ConnectorError.message("A Google credit is missing its expiration; a partial balance was not accepted.") }
            if end <= now { continue }
            if let start = row["startTime"] {
                guard let startDate = date(start) else { throw ConnectorError.message("A Google credit has an invalid start date; a partial balance was not accepted.") }
                if startDate > now { continue }
            }
            let amount = try ProviderJSON.money(row["remainingAmount"])
            total += amount
            if let grant = (try? ProviderJSON.money(row["amount"])) ?? (try? ProviderJSON.money(row["initialAmount"])), grant > 0 {
                grantTotal += grant
            }
            if amount > 0 { ends.append(end) }
        }
        let expiry = ends.min().map { $0.formatted(date:.abbreviated,time:.omitted) }
        let reference = grantTotal > 0 ? grantTotal : PaymentReference.inferTier(for: total)
        return Reading(provider:"vertex",remaining:total,currency:"USD",account:resolvedAccount,url:Self.endpoint,expires:expiry,reference:reference)
    }
}

enum ProviderProbe {
    static func run(provider: String, output: URL) async {
        var result: [String:Any] = ["provider":provider]
        do {
            let client = try SessionHTTP.connect(provider:provider)
            if provider == "crowbot" {
                let (data, response) = try await client.request(url: URL(string: "https://chat.crowbot.sh/api/me")!)
                result["http"] = response.statusCode
                if let json = try? ProviderJSON.object(data) {
                    result["keys"] = Array(json.keys)
                    for (k, v) in json where !k.contains("key") && !k.contains("secret") && !k.contains("token") {
                        result[k] = v
                    }
                }
            } else if provider == "fireworks" {
                let fw = FireworksProvider(http: client, account: "")
                let fwAccount = await fw.discoverAccount()
                let targetQuery = fwAccount.isEmpty ? "" : "?targetAccountId=\(fwAccount)"
                let url = URL(string:"https://app.fireworks.ai/api/v2/auth/refresh\(targetQuery)")!
                let (data,response) = try await client.request(url:url)
                result["refreshHTTP"] = response.statusCode
                let json = try ProviderJSON.object(data)
                result["refreshSchema"] = ProviderJSON.shape(json)
                // No raw cookies, token values, or API headers are printed.
                let (balanceData,balanceHTTP) = try await client.request(url:URL(string:"https://app.fireworks.ai/api/billing/balance")!)
                result["balanceHTTP"] = balanceHTTP.statusCode
                if balanceHTTP.statusCode == 200 {
                    let object = try ProviderJSON.object(balanceData)
                    result["balanceSchema"] = ProviderJSON.shape(object)
                    result["remainingUSD"] = try ProviderJSON.money(object["balance"])
                }
            } else {
                let google = GoogleProvider(http:client,account:"")
                let (data,response) = try await google.response()
                result["http"] = response.statusCode
                if let object = try? ProviderJSON.object(data) {
                    result["schema"] = ProviderJSON.shape(object)
                    result["keys"] = Array(object.keys)
                    if let results = object["results"] as? [[String:Any]], let first = results.first,
                       let d = first["data"] as? [String:Any], let cq = d["creditsQuery"] as? [String:Any],
                       let lc = cq["listCredits"] as? [String:Any], let rows = lc["data"] as? [[String:Any]], let row = rows.first {
                        result["firstGrantKeys"] = Array(row.keys)
                        for (k, v) in row where !k.contains("Account") {
                            result["grant_\(k)"] = v
                        }
                    }
                    if let error = object["error"] as? [String:Any] { result["serverMessage"] = error["message"] }
                    if response.statusCode == 200, let reading = try? GoogleProvider.parse(object,account:"") { result["remainingUSD"] = reading.remaining }
                } else {
                    result["responseType"] = response.mimeType ?? "unknown"
                    if response.statusCode == 400 { result["requestError"] = String(data:data.prefix(1600),encoding:.utf8) }
                }
            }
        } catch { result["error"] = error.localizedDescription }
        if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:output,options:.atomic) }
    }
}
