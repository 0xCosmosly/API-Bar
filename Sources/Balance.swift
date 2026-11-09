import Foundation

func relativeTimeString(for date: Date) -> String {
    guard date != .distantPast else { return "Never" }
    let elapsed = Date().timeIntervalSince(date)
    if elapsed < 15 { return "just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

struct Balance: Codable, Equatable {
    var id: String
    var name: String
    var baseline: Double
    var remaining: Double
    var updated: Date
    var account: String
    var expires: String?
    var live: Bool = false
    var dynamicEndpoint: String?
    var dynamicJsonPath: String?
    var dynamicCookieDomain: String?
    var dynamicAuthHeader: String?
    var tokensPerDay: Double? = nil
    var runwayDays: Int? = nil
    /// Optional so older `balances.json` files keep decoding. `true` is stored
    /// for a paused provider; `nil` means enabled.
    var disabled: Bool? = nil

    /// A disabled provider keeps its configuration, credentials, and position in
    /// the list but is skipped by refreshes and hidden from gauges, tabs, totals,
    /// and the menu bar.
    var isEnabled: Bool {
        get { disabled != true }
        set { disabled = newValue ? nil : true }
    }

    init(id: String, name: String, baseline: Double, remaining: Double, updated: Date, account: String, expires: String? = nil, live: Bool = false, dynamicEndpoint: String? = nil, dynamicJsonPath: String? = nil, dynamicCookieDomain: String? = nil, dynamicAuthHeader: String? = nil, tokensPerDay: Double? = nil, runwayDays: Int? = nil, disabled: Bool? = nil) {
        self.id = id; self.name = name; self.baseline = baseline; self.remaining = remaining
        self.updated = updated; self.account = account; self.expires = expires; self.live = live
        self.dynamicEndpoint = dynamicEndpoint; self.dynamicJsonPath = dynamicJsonPath
        self.dynamicCookieDomain = dynamicCookieDomain
        self.dynamicAuthHeader = dynamicAuthHeader
        self.tokensPerDay = tokensPerDay
        self.runwayDays = runwayDays
        self.disabled = disabled
    }
    var percent: Double { baseline > 0 ? max(0, remaining / baseline * 100) : 0 }
    var percentageLabel: String {
        if (!live && baseline == 0) || (id == "crowbot" && account.isEmpty) { return "—" }
        // Do not round a partly used balance back up to 100%.
        if percent > 0 && percent < 1 { return "<1%" }
        return "\(Int(floor(percent)))%"
    }
    var stale: Bool { !live || Date().timeIntervalSince(updated) > 900 }
    var money: String {
        return remaining.formatted(.currency(code: "USD"))
    }
    var pacingMessage: String? {
        PacingCalculator.pacingMessage(tokensPerDay: tokensPerDay, runwayDays: runwayDays)
    }
    static let initial: [Balance] = [
        Balance(id: "vertex", name: "Vertex AI", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "fireworks", name: "Fireworks", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "crowbot", name: "Crowbot", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "aistudio", name: "Google AI Studio", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "cerebras", name: "Cerebras", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "refuseless", name: "Refuseless", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "lutheos", name: "Lutheos", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "unaligned", name: "Unaligned", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        // Available to add, but paused until the user turns it on.
        Balance(id: "heimdallm", name: "Heimdallm", baseline: 0, remaining: 0, updated: .distantPast, account: "", disabled: true),
        Balance(id: "yeta", name: "Yeta", baseline: 0, remaining: 0, updated: .distantPast, account: "", disabled: true)
    ]
}

enum PacingCalculator {
    /// Formats large token figures into compact human-readable representations (e.g. 152.9M, 500K, 8,400).
    static func formatTokens(_ count: Double) -> String {
        guard count.isFinite, count >= 0 else { return "0" }
        if count >= 1_000_000_000 {
            let val = count / 1_000_000_000
            return (val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fB", val) : String(format: "%.1fB", val))
        } else if count >= 1_000_000 {
            let val = count / 1_000_000
            return (val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fM", val) : String(format: "%.1fM", val))
        } else if count >= 100_000 {
            return String(format: "%.0fK", count / 1_000)
        } else if count >= 10_000 {
            let val = count / 1_000
            return (val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fK", val) : String(format: "%.1fK", val))
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: Int(round(count)))) ?? "\(Int(round(count)))"
        }
    }

    /// Formats the pacing message: "x tokens per day - Runs out in x days"
    static func pacingMessage(tokensPerDay: Double?, runwayDays: Int?) -> String? {
        guard let tokens = tokensPerDay, tokens > 0, let days = runwayDays, days >= 0 else { return nil }
        let formattedTokens = formatTokens(tokens)
        let daysString = days == 1 ? "1 day" : "\(days) days"
        return "\(formattedTokens) tokens per day - Runs out in \(daysString)"
    }

    /// Calculates days until depletion based on remaining funds and daily spend.
    static func calculateRunway(remaining: Double, dailySpend: Double) -> Int? {
        guard remaining > 0, dailySpend > 0 else { return nil }
        return max(0, Int(floor(remaining / dailySpend)))
    }

    /// Calculates tokens per day given total tokens over active days.
    static func calculateTokensPerDay(totalTokens: Double, activeDays: Double) -> Double? {
        guard activeDays > 0, totalTokens >= 0 else { return nil }
        return totalTokens / activeDays
    }
}

enum PaymentReference {
    static let standardTiers: [Double] = [5, 10, 15, 20, 25, 50, 100, 150, 200, 250, 300, 500, 1000]

    /// Infers the paid top-up tier from a balance or top-up delta.
    /// For example:
    /// Crowbot paid $5 -> remaining $4.85 -> tier is $5.00.
    /// Fireworks paid $10 -> remaining $10.00 -> tier is $10.00.
    /// Google Cloud grant $300 -> remaining $299.99 -> tier is $300.00.
    static func inferTier(for amount: Double) -> Double {
        guard amount > 0 else { return 0 }
        for tier in standardTiers {
            if amount <= tier { return tier }
            if amount <= tier + max(0.10, tier * 0.015) {
                return tier
            }
        }
        return ceil(amount / 50.0) * 50.0
    }
}

struct Reading: Decodable {
    let provider: String
    let remaining: Double
    let currency: String
    let account: String
    let url: String
    let expires: String?
    var reference: Double? = nil
    var tokensPerDay: Double? = nil
    var runwayDays: Int? = nil

    init(provider: String, remaining: Double, currency: String, account: String, url: String, expires: String?, reference: Double? = nil, tokensPerDay: Double? = nil, runwayDays: Int? = nil) {
        self.provider = provider
        self.remaining = remaining
        self.currency = currency
        self.account = account
        self.url = url
        self.expires = expires
        self.reference = reference
        self.tokensPerDay = tokensPerDay
        self.runwayDays = runwayDays
    }
}

enum ReadingValidation {
    static func valid(_ r: Reading, balances: [Balance]) -> Bool {
        guard r.remaining.isFinite, r.remaining >= 0, r.remaining < 1_000_000_000,
              r.currency == "USD", let url = URL(string: r.url), url.scheme == "https",
              let balance = balances.first(where: { $0.id == r.provider }) else { return false }
        if r.provider == "vertex" {
            let web = url.host == "console.cloud.google.com" && (balance.account.isEmpty || url.path.hasPrefix("/billing/\(balance.account)/credits"))
            let api = url.host == "cloudconsole-pa.clients6.google.com" && url.path == "/v3/entityServices/BillingpricefactorsEntityService/schemas/BILLINGPRICEFACTORS_GRAPHQL:batchGraphql"
            return (web || api) && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "crowbot" {
            return url.absoluteString == CrowbotProvider.endpoint && CrowbotProvider.validAccount(r.account) && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "fireworks" {
            return url.host == "app.fireworks.ai" && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "aistudio" {
            return (url.host == "aistudio.google.com" || url.host == "appsgenaiserver-pa.clients6.google.com") && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "cerebras" {
            return (url.host == "cloud.cerebras.ai" || url.host == "api.cerebras.ai") && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "refuseless" {
            return (url.host == "refuseless.com" || url.host == "api.refuseless.com" || url.host == "console.refuseless.com") && (balance.account.isEmpty || balance.account.hasSuffix(" Account") || r.account == balance.account)
        }
        if r.provider == "lutheos" {
            return (url.host == "lutheos.com" || url.host == "api.lutheos.com") && (balance.account.isEmpty || balance.account.hasSuffix(" Account") || r.account == balance.account)
        }
        if r.provider == "yeta" {
            return url.host == YetaProvider.host && url.path == "/api/user/self" && (balance.account.isEmpty || balance.account.hasSuffix(" Account") || r.account == balance.account)
        }
        if r.provider == "unaligned" {
            return url.host == UnalignedProvider.host && url.path.hasPrefix("/dashboard") && (balance.account.isEmpty || balance.account.hasSuffix(" Account") || r.account == balance.account)
        }
        if r.provider == "heimdallm" {
            let validHosts = ["heimdallm.com", "staging.heimdallm.com", "api.heimdallm.com"]
            return validHosts.contains(url.host ?? "") && url.path.hasPrefix("/api/frontend/v1") && (balance.account.isEmpty || balance.account.hasSuffix(" Account") || r.account == balance.account)
        }
        if let endpoint = balance.dynamicEndpoint, let dynamicURL = URL(string: endpoint) {
            return url.host == dynamicURL.host
        }
        return false
    }
}
