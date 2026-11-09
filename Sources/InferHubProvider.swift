import Foundation

/// InferHub (inferhub.dev / api.inferhub.dev) is an AI inference aggregator and routing platform.
/// Balances are reported in USDC / USD, along with token usage metrics and burn-rate pacing.
///
/// Authentication accepts:
/// 1. Direct API keys (`sk-airo-…` or `sk-…`) via `Authorization: Bearer <key>` and `x-api-key: <key>`.
/// 2. Browser session credentials imported from Brave.
struct InferHubProvider: BalanceProvider {
    let providerID = "inferhub"
    let http: SessionHTTP
    let balance: Balance

    static let usageEndpoint = "https://api.inferhub.dev/v1/me/usage?window=day&tz=UTC"
    static let meEndpoint = "https://inferhub.dev/api/me"
    static let dashboardURL = "https://inferhub.dev/dashboard"
    static let sessionEndpoint = "https://inferhub.dev/api/auth/session"
    static let allowedHosts: Set<String> = [
        "api.inferhub.dev",
        "inferhub.dev"
    ]

    // MARK: - Credential Resolution

    static func resolveKey(authHeader: String?, cookies: [StoredCookie]) -> String? {
        if let auth = authHeader?.trimmingCharacters(in: .whitespacesAndNewlines), !auth.isEmpty {
            if auth.hasPrefix("Bearer ") {
                return String(auth.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return auth
        }
        for cookie in cookies {
            let val = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if val.hasPrefix("sk-airo-") || val.hasPrefix("sk-") {
                return val
            }
            let name = cookie.name.lowercased()
            if name == "api_key" || name == "inferhub_api_key" || name == "inferhub_key" || name == "token" {
                if !val.isEmpty { return val }
            }
        }
        return nil
    }

    static func hasValidSession(cookies: [StoredCookie]) -> Bool {
        cookies.contains { cookie in
            guard cookie.domain.contains("inferhub.dev") else { return false }
            let name = cookie.name.lowercased()
            return name.contains("session") || name.contains("token") || name.contains("auth") || name.contains("api_key") || name.contains("key")
        }
    }

    // MARK: - Parsing

    static func parseUsage(_ data: Data, expectedAccount: String = "") throws -> Reading {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw ConnectorError.message("InferHub returned a response that was not JSON. The previous balance was retained.")
        }

        if let error = root["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "Unknown error"
            if message.lowercased().contains("unauthorized") || message.lowercased().contains("authorization") {
                throw ConnectorError.message("InferHub API key or session expired. Provide an API key or sign in at inferhub.dev in Brave, then reconnect.")
            }
            throw ConnectorError.message("InferHub refused the request: \(message).")
        }

        // Remaining balance: check balance object or top-level fields
        var remaining: Double? = nil
        if let balanceDict = root["balance"] as? [String: Any] {
            remaining = number(balanceDict["amount_usdc"])
                ?? number(balanceDict["amount"])
                ?? number(balanceDict["usd"])
                ?? number(balanceDict["credits"])
                ?? number(balanceDict["remaining"])
        }
        if remaining == nil {
            remaining = number(root["amount_usdc"])
                ?? number(root["balance_usdc"])
                ?? number(root["credits"])
                ?? number(root["remaining"])
                ?? number(root["balance"])
        }

        guard let balanceAmount = remaining, balanceAmount.isFinite, balanceAmount >= 0, balanceAmount < 1_000_000_000 else {
            throw ConnectorError.message("InferHub did not return a valid balance. The previous balance was retained.")
        }

        // Pacing metrics from window
        var tokensPerDay: Double? = nil
        var runwayDays: Int? = nil

        let window = (root["window"] as? [String: Any]) ?? [:]
        let totalTokens = number(window["total_tokens"])
        let promptTokens = number(window["prompt_tokens"]) ?? 0
        let completionTokens = number(window["completion_tokens"]) ?? 0
        let sumTokens = (totalTokens != nil && totalTokens! > 0) ? totalTokens! : (promptTokens + completionTokens)

        if sumTokens > 0 {
            tokensPerDay = sumTokens
        }

        let dailySpend = number(window["spend_usdc"]) ?? number(window["spend"]) ?? number(window["cost"]) ?? 0
        if dailySpend > 0 && balanceAmount > 0 {
            runwayDays = PacingCalculator.calculateRunway(remaining: balanceAmount, dailySpend: dailySpend)
        }

        // Baseline: all-time spend + remaining, or tier inference
        let allTime = (root["all_time"] as? [String: Any]) ?? (root["allTime"] as? [String: Any]) ?? [:]
        let allTimeSpend = number(allTime["spend_usdc"]) ?? number(allTime["spend"]) ?? 0
        let baseline: Double
        if allTimeSpend > 0 {
            baseline = max(balanceAmount + allTimeSpend, balanceAmount)
        } else if balanceAmount > 0 {
            baseline = PaymentReference.inferTier(for: balanceAmount)
        } else {
            baseline = 0.0
        }

        // Account identity
        let user = (root["user"] as? [String: Any]) ?? [:]
        let email = ((user["email"] as? String) ?? (root["email"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accountID = ((user["id"] as? String) ?? (root["account_id"] as? String) ?? (root["id"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var resolvedAccount = email.contains("@") ? email : accountID
        if resolvedAccount.isEmpty {
            resolvedAccount = expectedAccount.isEmpty ? "InferHub Account" : expectedAccount
        }

        if !expectedAccount.isEmpty, !expectedAccount.hasSuffix(" Account"), !resolvedAccount.hasSuffix(" Account"),
           resolvedAccount != expectedAccount {
            throw ConnectorError.message("This InferHub key belongs to a different account. The previous balance was retained.")
        }

        return Reading(
            provider: "inferhub",
            remaining: balanceAmount,
            currency: "USD",
            account: resolvedAccount,
            url: usageEndpoint,
            expires: nil,
            reference: baseline,
            tokensPerDay: tokensPerDay,
            runwayDays: runwayDays
        )
    }

    static func parseDashboard(_ dashString: String, sessionData: Data?, expectedAccount: String = "") throws -> Reading {
        var balanceAmount: Double? = nil

        // React component props ["$$", "0.99"] or ["$", "0.99"]
        if let regex = try? NSRegularExpression(pattern: #""children":\["(?:\$\$|\$)","([0-9]+(?:\.[0-9]+)?)"\]"#) {
            let range = NSRange(dashString.startIndex..<dashString.endIndex, in: dashString)
            if let match = regex.firstMatch(in: dashString, options: [], range: range),
               let groupRange = Range(match.range(at: 1), in: dashString) {
                balanceAmount = Double(dashString[groupRange])
            }
        }

        // Contextual regex fallback
        if balanceAmount == nil {
            let patterns = [
                #"Balance.*?children":\["(?:\$\$|\$)","([0-9]+(?:\.[0-9]+)?)"\]"#,
                #"children":\["(?:\$\$|\$)","([0-9]+(?:\.[0-9]+)?)"\].*?Consumer USDC"#,
                #"(?:\$\$|\$)\s*([0-9]+(?:\.[0-9]+)?).*?Consumer USDC"#,
                #"Consumer USDC.*?([0-9]+(?:\.[0-9]+)?)"#
            ]
            for p in patterns {
                if let regex = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) {
                    let range = NSRange(dashString.startIndex..<dashString.endIndex, in: dashString)
                    if let match = regex.firstMatch(in: dashString, options: [], range: range),
                       let groupRange = Range(match.range(at: 1), in: dashString) {
                        if let val = Double(dashString[groupRange]) {
                            balanceAmount = val
                            break
                        }
                    }
                }
            }
        }

        guard let balance = balanceAmount, balance.isFinite, balance >= 0, balance < 1_000_000_000 else {
            throw ConnectorError.message("InferHub did not return a valid balance. The previous balance was retained.")
        }

        // Spend stats from {"stats":{"24h":{"requests":...,"spend":"..."}}}
        var dailySpend: Double = 0
        var allTimeSpend: Double = 0
        var requestsPerDay: Double? = nil

        if let statsRegex = try? NSRegularExpression(pattern: #""stats":(\{"24h":\{.*?\}\})"#) {
            let range = NSRange(dashString.startIndex..<dashString.endIndex, in: dashString)
            if let match = statsRegex.firstMatch(in: dashString, options: [], range: range),
               let groupRange = Range(match.range(at: 1), in: dashString),
               let statsData = dashString[groupRange].data(using: .utf8),
               let statsJSON = try? JSONSerialization.jsonObject(with: statsData) as? [String: Any] {
                if let d24 = statsJSON["24h"] as? [String: Any] {
                    dailySpend = number(d24["spend"]) ?? number(d24["spend_usdc"]) ?? 0
                    if let reqs = number(d24["requests"]), reqs > 0 {
                        requestsPerDay = reqs
                    }
                }
                if let dall = statsJSON["all"] as? [String: Any] {
                    allTimeSpend = number(dall["spend"]) ?? number(dall["spend_usdc"]) ?? 0
                }
            }
        }

        var runwayDays: Int? = nil
        if dailySpend > 0 && balance > 0 {
            runwayDays = PacingCalculator.calculateRunway(remaining: balance, dailySpend: dailySpend)
        }

        let baseline: Double
        if allTimeSpend > 0 {
            baseline = max(balance + allTimeSpend, balance)
        } else if balance > 0 {
            if balance <= 1.0 {
                baseline = 1.0
            } else if balance <= 2.0 {
                baseline = 2.0
            } else {
                baseline = PaymentReference.inferTier(for: balance)
            }
        } else {
            baseline = 0.0
        }

        // Account resolution from /api/auth/session
        var resolvedAccount = ""
        var sessionExpires: String? = nil
        if let sessionData,
           let sessionJSON = try? JSONSerialization.jsonObject(with: sessionData) as? [String: Any] {
            if let exp = sessionJSON["expires"] as? String {
                sessionExpires = exp
            }
            if let user = sessionJSON["user"] as? [String: Any] {
                let email = ((user["email"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let id = ((user["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedAccount = email.contains("@") ? email : id
            }
        }
        if resolvedAccount.isEmpty {
            resolvedAccount = expectedAccount.isEmpty ? "InferHub Account" : expectedAccount
        }

        if !expectedAccount.isEmpty, !expectedAccount.hasSuffix(" Account"), !resolvedAccount.hasSuffix(" Account"),
           resolvedAccount != expectedAccount {
            throw ConnectorError.message("This InferHub key belongs to a different account. The previous balance was retained.")
        }

        return Reading(
            provider: "inferhub",
            remaining: balance,
            currency: "USD",
            account: resolvedAccount,
            url: dashboardURL,
            expires: sessionExpires,
            reference: baseline,
            tokensPerDay: requestsPerDay,
            runwayDays: runwayDays
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            let cleaned = string
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        }
        return nil
    }

    // MARK: - Fetch

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        var key = Self.resolveKey(authHeader: balance.dynamicAuthHeader, cookies: cookies)

        if key == nil && !Self.hasValidSession(cookies: cookies) {
            if (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
                cookies = await http.cookies
                key = Self.resolveKey(authHeader: balance.dynamicAuthHeader, cookies: cookies)
            }
        }

        guard key != nil || Self.hasValidSession(cookies: cookies) else {
            throw ConnectorError.message("No InferHub sign-in or API key found. Enter your API key or sign in at inferhub.dev in Brave, then reconnect.")
        }

        // 1. Direct API key: query developer API endpoints
        if let key {
            let headers: [String: String] = [
                "Accept": "application/json",
                "Authorization": "Bearer \(key)",
                "x-api-key": key
            ]

            // Try the usage endpoint first
            if let usageURL = URL(string: Self.usageEndpoint) {
                do {
                    let (data, response) = try await http.request(url: usageURL, headers: headers)
                    if response.statusCode == 200 {
                        let reading = try Self.parseUsage(data, expectedAccount: balance.account)
                        if !cookies.isEmpty { try? await http.persist() }
                        return reading
                    } else if response.statusCode == 401 {
                        throw ConnectorError.message("InferHub API key or session expired. Provide an API key or sign in at inferhub.dev in Brave, then reconnect.")
                    }
                } catch {
                    if let connErr = error as? ConnectorError {
                        throw connErr
                    }
                }
            }

            // Fallback to me endpoint
            if let meURL = URL(string: Self.meEndpoint) {
                let (data, response) = try await http.request(url: meURL, headers: headers)
                guard response.statusCode == 200 else {
                    if response.statusCode == 401 {
                        throw ConnectorError.message("InferHub API key or session expired. Provide an API key or sign in at inferhub.dev in Brave, then reconnect.")
                    }
                    throw ConnectorError.message("InferHub returned HTTP \(response.statusCode). The previous balance was retained.")
                }
                let reading = try Self.parseUsage(data, expectedAccount: balance.account)
                if !cookies.isEmpty { try? await http.persist() }
                return reading
            }
        }

        // 2. Browser session: query dashboard and session endpoints
        if let dashboardURL = URL(string: Self.dashboardURL) {
            var sessionData: Data? = nil
            if let sessionURL = URL(string: Self.sessionEndpoint) {
                if let (sData, sResp) = try? await http.request(url: sessionURL, headers: ["Accept": "application/json"]),
                   sResp.statusCode == 200 {
                    sessionData = sData
                }
            }

            let rscHeaders = [
                "Accept": "*/*",
                "RSC": "1"
            ]
            let (dashData, dashResp) = try await http.request(url: dashboardURL, headers: rscHeaders)
            guard dashResp.statusCode == 200 else {
                if dashResp.statusCode == 401 || dashResp.statusCode == 403 {
                    throw ConnectorError.message("InferHub session expired. Sign in at inferhub.dev in Brave, then reconnect.")
                }
                throw ConnectorError.message("InferHub returned HTTP \(dashResp.statusCode). The previous balance was retained.")
            }

            let dashString = String(decoding: dashData, as: UTF8.self)
            let reading = try Self.parseDashboard(dashString, sessionData: sessionData, expectedAccount: balance.account)
            try? await http.persist()
            return reading
        }

        throw ConnectorError.message("Could not read InferHub balance. The previous balance was retained.")
    }
}
