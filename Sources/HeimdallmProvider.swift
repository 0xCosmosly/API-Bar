import Foundation

/// Heimdallm (heimdallm.com) is an AI inference orchestration platform.
/// Balances are read from the signed-in session using the browser session cookies
/// from Brave; no API key is stored.
///
/// The platform reports spendable, available, deposited, and spent amounts via
/// `/api/frontend/v1/credits` and user/account identity via `/api/frontend/v1/account`.
struct HeimdallmProvider: BalanceProvider {
    let providerID = "heimdallm"
    let http: SessionHTTP
    let account: String

    static let defaultHost = "heimdallm.com"
    static let stagingHost = "staging.heimdallm.com"
    static let dashboardURL = "https://heimdallm.com/account?tab=credits"
    static let allowedHosts: Set<String> = [
        "heimdallm.com",
        "staging.heimdallm.com",
        "api.heimdallm.com"
    ]

    static func targetHost(cookies: [StoredCookie]) -> String {
        if cookies.contains(where: { $0.domain.contains("staging.heimdallm.com") }) {
            return stagingHost
        }
        return defaultHost
    }

    static func hasValidSession(cookies: [StoredCookie]) -> Bool {
        cookies.contains { cookie in
            guard cookie.domain.contains("heimdallm.com") else { return false }
            let name = cookie.name.lowercased()
            return name.contains("heimdall") || name.contains("session") || name.contains("token") || name.contains("auth")
        }
    }

    // MARK: - Parsing

    /// Derives the current top-up cycle's total (the true 100% reference) from
    /// the credits ledger: the newest deposit plus whatever was left unspent
    /// right before it. Equivalent to `available + debits since that deposit`,
    /// which stays exact even though `totals.deposited` is a lifetime figure.
    ///
    /// Returns nil when the ledger cannot support the derivation: no deposit
    /// entry in the returned window, or a truncated ledger whose debits do not
    /// reconcile with the balance block (understating the cycle would silently
    /// cap the gauge above 100%).
    static func cycleTotal(balanceDict: [String: Any], entries: [[String: Any]]) -> Double? {
        guard let newestDeposit = newestDepositEntry(entries),
              let available = number(balanceDict["available"]) ?? number(balanceDict["spendable"]) else { return nil }
        var spendSinceDeposit = 0.0
        for entry in entries {
            guard let amount = number(entry["amount"]), amount < 0,
                  let created = entry["created_at"] as? String, created > newestDeposit.created_at else { continue }
            spendSinceDeposit += -amount
        }
        let total = available + spendSinceDeposit
        guard total.isFinite, total > 0, total >= available, total < 1_000_000_000 else { return nil }
        // The ledger window is limited (50 entries). If debits after the newest
        // deposit are incomplete, `total` understates the real cycle. Detect by
        // reconciling with the authoritative balance block: available + debited
        // must equal the lifetime deposited total. A mismatch means the window
        // is truncated, so the derived cycle total cannot be trusted.
        let debited = number(balanceDict["debited"])
        let deposited = number(balanceDict["credited"])
        if let debited, let deposited {
            guard abs((available + debited) - deposited) < 0.01 else { return nil }
        }
        return total
    }

    private static func newestDepositEntry(_ entries: [[String: Any]]) -> (created_at: String, amount: Double)? {
        var newest: (created_at: String, amount: Double)? = nil
        for entry in entries {
            guard (entry["kind"] as? String)?.lowercased() == "deposit",
                  let created = entry["created_at"] as? String,
                  let amount = number(entry["amount"]), amount > 0 else { continue }
            if newest == nil || created > newest!.created_at {
                newest = (created_at: created, amount: amount)
            }
        }
        return newest
    }

    /// Parses the credits payload. `cycleBaseline` is the server-derived current
    /// top-up cycle total (authoritative); `baseline` falls back to the legacy
    /// lifetime-deposit derivation when the ledger cannot support the cycle
    /// calculation, and must not be treated as authoritative.
    static func parseCredits(_ data: Data) throws -> (remaining: Double, baseline: Double, cycleBaseline: Double?, accountID: String) {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw ConnectorError.message("Heimdallm returned a response that was not JSON. The previous balance was retained.")
        }
        if let error = root["error"] as? [String: Any], let msg = error["message"] as? String {
            throw ConnectorError.message("Heimdallm refused the request: \(msg).")
        }

        let balanceDict = (root["balance"] as? [String: Any]) ?? [:]
        let totalsDict = (root["totals"] as? [String: Any]) ?? [:]
        let entries = root["entries"] as? [[String: Any]] ?? []

        guard let remaining = number(balanceDict["spendable"]) ?? number(balanceDict["available"]) ?? number(totalsDict["balance"]) else {
            throw ConnectorError.message("Heimdallm did not return a credit balance. The previous balance was retained.")
        }

        guard remaining.isFinite, remaining >= 0, remaining < 1_000_000_000 else {
            throw ConnectorError.message("Heimdallm returned an invalid balance. The previous balance was retained.")
        }

        let cycle = cycleTotal(balanceDict: balanceDict, entries: entries)
        let baseline: Double
        if let cycle {
            baseline = max(cycle, remaining)
        } else {
            baseline = fallbackBaseline(balanceDict: balanceDict, totalsDict: totalsDict, entries: entries, remaining: remaining)
        }

        let accountID = (root["account_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (remaining: remaining, baseline: baseline, cycleBaseline: cycle, accountID: accountID)
    }

    /// Legacy derivation used only when the ledger cannot produce a cycle total.
    private static func fallbackBaseline(balanceDict: [String: Any], totalsDict: [String: Any], entries: [[String: Any]], remaining: Double) -> Double {
        let credited = number(balanceDict["credited"]) ?? 0.0
        let deposited = number(totalsDict["deposited"]) ?? 0.0
        let rewards = number(totalsDict["referral_rewards"]) ?? 0.0
        let adjusted = number(totalsDict["adjusted"]) ?? 0.0
        let totalCredited = max(credited, deposited + rewards + adjusted)

        var ledgerDeposits = 0.0
        for entry in entries {
            let kind = (entry["kind"] as? String)?.lowercased()
            if let kind, ["deposit", "credit", "referral_reward", "adjustment", "bonus"].contains(kind) {
                if let amt = number(entry["amount"]), amt > 0 {
                    ledgerDeposits += amt
                }
            }
        }

        let spent = number(totalsDict["spent"]) ?? 0.0
        let totalFunds = totalCredited > 0 ? totalCredited : ledgerDeposits
        if totalFunds > 0 {
            return max(totalFunds, remaining)
        } else if spent > 0 {
            return max(remaining + spent, remaining)
        } else if remaining > 0 {
            return PaymentReference.inferTier(for: remaining)
        } else {
            return 0.0
        }
    }

    static func parseAccount(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            return nil
        }
        let user = root["user"] as? [String: Any]
        let email = (user?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if email.contains("@") { return email }
        let displayName = (user?["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        let account = root["account"] as? [String: Any]
        let accountName = (account?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !accountName.isEmpty { return accountName }
        return nil
    }

    static func parse(creditsData: Data, accountData: Data? = nil, url: String, account expectedAccount: String = "", tokensPerDay: Double? = nil, runwayDays: Int? = nil) throws -> Reading {
        let (remaining, _, cycleBaseline, accountID) = try parseCredits(creditsData)
        var resolvedAccount = ""
        if let accountData {
            resolvedAccount = parseAccount(accountData) ?? ""
        }
        if resolvedAccount.isEmpty {
            resolvedAccount = !accountID.isEmpty ? accountID : "Heimdallm Account"
        }

        if !expectedAccount.isEmpty, !expectedAccount.hasSuffix(" Account"), !resolvedAccount.isEmpty,
           resolvedAccount != expectedAccount {
            throw ConnectorError.message("This Heimdallm sign-in belongs to a different account. The previous balance was retained.")
        }

        return Reading(
            provider: "heimdallm",
            remaining: remaining,
            currency: "USD",
            account: resolvedAccount,
            url: url,
            expires: nil,
            // Only the server-derived cycle total is authoritative. The legacy
            // lifetime-deposit fallback must never reset the gauge's 100% point,
            // so it is not forwarded as a reference.
            reference: cycleBaseline,
            tokensPerDay: tokensPerDay,
            runwayDays: runwayDays
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            let cleaned = string.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        }
        return nil
    }

    // MARK: - Pacing

    /// Extracts 30-day token pacing and runway metrics from Heimdallm analytics and credits payloads.
    static func extractPacing(analyticsData: Data, creditsData: Data? = nil, remaining: Double) -> (tokensPerDay: Double, runwayDays: Int)? {
        guard let analyticsJSON = try? JSONSerialization.jsonObject(with: analyticsData, options: [.fragmentsAllowed]) as? [String: Any] else {
            return nil
        }
        return extractPacing(analyticsJSON: analyticsJSON, creditsData: creditsData, remaining: remaining)
    }

    static func extractPacing(analyticsJSON: [String: Any], creditsData: Data? = nil, remaining: Double) -> (tokensPerDay: Double, runwayDays: Int)? {
        guard remaining >= 0 else { return nil }

        let summary = analyticsJSON["summary"] as? [String: Any]
        let promptTokens = number(summary?["prompt_tokens"]) ?? 0
        let completionTokens = number(summary?["completion_tokens"]) ?? 0
        var totalTokens = promptTokens + completionTokens

        let buckets = analyticsJSON["buckets"] as? [[String: Any]] ?? []
        var activeBuckets = 0
        for bucket in buckets {
            let reqs = number(bucket["requests"]) ?? 0
            let tok = number(bucket["tokens"]) ?? 0
            let spend = number(bucket["spend"]) ?? 0
            if reqs > 0 || tok > 0 || spend > 0 {
                activeBuckets += 1
            }
            if totalTokens == 0, tok > 0 {
                totalTokens += tok
            }
        }

        guard totalTokens > 0 else { return nil }

        let activeDays = max(1, activeBuckets > 0 ? activeBuckets : 30)
        let tokensPerDay = totalTokens / Double(activeDays)

        var totalSpend = number(summary?["spend"]) ?? 0
        if totalSpend <= 0, let creditsData {
            if let creditsRoot = try? JSONSerialization.jsonObject(with: creditsData, options: [.fragmentsAllowed]) as? [String: Any],
               let totals = creditsRoot["totals"] as? [String: Any],
               let spent = number(totals["spent"]), spent > 0 {
                totalSpend = spent
            }
        }

        let dailySpend = totalSpend > 0 ? (totalSpend / Double(activeDays)) : 0
        let runwayDays = dailySpend > 0 ? max(0, Int(floor(remaining / dailySpend))) : nil

        if let runway = runwayDays {
            return (tokensPerDay: tokensPerDay, runwayDays: runway)
        }
        return nil
    }

    // MARK: - Fetch

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        if !Self.hasValidSession(cookies: cookies), (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
            cookies = await http.cookies
        }
        guard Self.hasValidSession(cookies: cookies) else {
            throw ConnectorError.message("No Heimdallm sign-in was found. Sign in at heimdallm.com in Brave, then reconnect.")
        }

        let host = Self.targetHost(cookies: cookies)
        guard let creditsURL = URL(string: "https://\(host)/api/frontend/v1/credits") else {
            throw ConnectorError.message("Heimdallm endpoint is unavailable.")
        }

        let (creditsData, creditsResponse) = try await http.request(url: creditsURL)
        switch creditsResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw ConnectorError.message("Heimdallm rejected the saved session. Sign in at heimdallm.com in Brave, then reconnect.")
        default:
            throw ConnectorError.message("Heimdallm returned HTTP \(creditsResponse.statusCode). The previous balance was retained.")
        }

        var accountData: Data? = nil
        if let accountURL = URL(string: "https://\(host)/api/frontend/v1/account"),
           let (accData, accResp) = try? await http.request(url: accountURL),
           accResp.statusCode == 200 {
            accountData = accData
        }

        var pacing: (tokensPerDay: Double, runwayDays: Int)? = nil
        if let (remaining, _, _, _) = try? Self.parseCredits(creditsData),
           let analyticsURL = URL(string: "https://\(host)/api/frontend/v1/generations/analytics"),
           let (analyticsData, analyticsResp) = try? await http.request(url: analyticsURL),
           analyticsResp.statusCode == 200 {
            pacing = Self.extractPacing(analyticsData: analyticsData, creditsData: creditsData, remaining: remaining)
        }

        let reading = try Self.parse(
            creditsData: creditsData,
            accountData: accountData,
            url: creditsURL.absoluteString,
            account: account,
            tokensPerDay: pacing?.tokensPerDay,
            runwayDays: pacing?.runwayDays
        )
        try await http.persist()
        return reading
    }
}
