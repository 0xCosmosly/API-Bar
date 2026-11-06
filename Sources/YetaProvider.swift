import Foundation

/// Yeta (platform.yeta.ai) is a prepaid AI gateway console. Balances are read
/// from the signed-in console with the same browser session cookies the other
/// providers use; no API key is stored.
///
/// The console reports quota in integer units and publishes the conversion at
/// `/api/status` (`quota_per_unit`, 500000 = $1 on this deployment), so the
/// divisor is read from the server instead of being hardcoded.
struct YetaProvider: BalanceProvider {
    let providerID = "yeta"
    let http: SessionHTTP
    let account: String

    static let host = "platform.yeta.ai"
    static let selfEndpoint = "https://platform.yeta.ai/api/user/self"
    static let statusEndpoint = "https://platform.yeta.ai/api/status"
    static let dashboardURL = "https://platform.yeta.ai/"
    /// Matches the published `quota_per_unit` and is only used if `/api/status`
    /// cannot be read.
    static let defaultQuotaPerUnit: Double = 500_000

    static func hasValidSession(cookies: [StoredCookie]) -> Bool {
        cookies.contains { cookie in
            guard cookie.domain.contains("yeta.ai") else { return false }
            let name = cookie.name.lowercased()
            return name.contains("session") || name.contains("token") || name.contains("auth") || name == "uid"
        }
    }

    // MARK: - Parsing

    static func quotaPerUnit(statusJSON: Any?) -> Double {
        guard let root = statusJSON as? [String: Any] else { return defaultQuotaPerUnit }
        let data = (root["data"] as? [String: Any]) ?? root
        if let value = data["quota_per_unit"] as? NSNumber, value.doubleValue > 0 {
            return value.doubleValue
        }
        if let value = data["quota_per_unit"] as? String, let parsed = Double(value), parsed > 0 {
            return parsed
        }
        return defaultQuotaPerUnit
    }

    /// Reads the signed-in user object. `quota` is what is left, `used_quota` what
    /// was spent; together they are the credit this account has had.
    static func parse(_ data: Data, quotaPerUnit: Double, account expectedAccount: String = "") throws -> Reading {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw ConnectorError.message("Yeta returned a response that was not JSON. The previous balance was retained.")
        }
        if let success = root["success"] as? Bool, success == false {
            let message = (root["message"] as? String) ?? "request refused"
            if (root["code"] as? String)?.contains("AUTH") == true || message.lowercased().contains("unauthorized") {
                throw ConnectorError.message("Yeta rejected the saved session. Sign in at platform.yeta.ai in Brave, then reconnect.")
            }
            throw ConnectorError.message("Yeta refused the request: \(message).")
        }
        guard let user = (root["data"] as? [String: Any]) ?? (root["data"] as? [[String: Any]])?.first else {
            throw ConnectorError.message("Yeta did not return an account. The previous balance was retained.")
        }
        guard let quota = number(user["quota"]) else {
            throw ConnectorError.message("Yeta did not return a quota balance. The previous balance was retained.")
        }
        let perUnit = quotaPerUnit > 0 ? quotaPerUnit : defaultQuotaPerUnit
        let remaining = quota / perUnit
        guard remaining.isFinite, remaining >= 0, remaining < 1_000_000_000 else {
            throw ConnectorError.message("Yeta returned an invalid balance. The previous balance was retained.")
        }
        let used = number(user["used_quota"]) ?? 0
        let granted = (quota + used) / perUnit
        let baseline = granted > 0 ? max(granted, remaining) : PaymentReference.inferTier(for: remaining)

        let email = (user["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = (user["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedAccount = email.contains("@") ? email : username
        if !expectedAccount.isEmpty, !expectedAccount.hasSuffix(" Account"), !resolvedAccount.isEmpty,
           resolvedAccount != expectedAccount {
            throw ConnectorError.message("This Yeta sign-in belongs to a different account. The previous balance was retained.")
        }

        return Reading(
            provider: "yeta",
            remaining: remaining,
            currency: "USD",
            account: resolvedAccount,
            url: selfEndpoint,
            expires: nil,
            reference: baseline
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    // MARK: - Fetch

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        if !Self.hasValidSession(cookies: cookies), (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
            cookies = await http.cookies
        }
        guard Self.hasValidSession(cookies: cookies) else {
            throw ConnectorError.message("No Yeta sign-in was found. Sign in at platform.yeta.ai in Brave, then reconnect.")
        }

        // The conversion factor is public; a failure here falls back to the default.
        var perUnit = Self.defaultQuotaPerUnit
        if let statusURL = URL(string: Self.statusEndpoint),
           let (statusData, statusResponse) = try? await http.request(url: statusURL),
           statusResponse.statusCode == 200,
           let statusJSON = try? JSONSerialization.jsonObject(with: statusData, options: [.fragmentsAllowed]) {
            perUnit = Self.quotaPerUnit(statusJSON: statusJSON)
        }

        guard let url = URL(string: Self.selfEndpoint) else {
            throw ConnectorError.message("Yeta endpoint is unavailable.")
        }
        let (data, response) = try await http.request(url: url)
        switch response.statusCode {
        case 200:
            let reading = try Self.parse(data, quotaPerUnit: perUnit, account: account)
            try await http.persist()
            return reading
        case 401, 403:
            throw ConnectorError.message("Yeta rejected the saved session. Sign in at platform.yeta.ai in Brave, then reconnect.")
        default:
            throw ConnectorError.message("Yeta returned HTTP \(response.statusCode). The previous balance was retained.")
        }
    }
}
