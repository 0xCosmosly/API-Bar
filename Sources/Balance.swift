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

    init(id: String, name: String, baseline: Double, remaining: Double, updated: Date, account: String, expires: String? = nil, live: Bool = false, dynamicEndpoint: String? = nil, dynamicJsonPath: String? = nil, dynamicCookieDomain: String? = nil, dynamicAuthHeader: String? = nil) {
        self.id = id; self.name = name; self.baseline = baseline; self.remaining = remaining
        self.updated = updated; self.account = account; self.expires = expires; self.live = live
        self.dynamicEndpoint = dynamicEndpoint; self.dynamicJsonPath = dynamicJsonPath
        self.dynamicCookieDomain = dynamicCookieDomain
        self.dynamicAuthHeader = dynamicAuthHeader
    }
    var percent: Double { baseline > 0 ? max(0, remaining / baseline * 100) : 0 }
    var percentageLabel: String {
        if id == "crowbot" && account.isEmpty { return "—" }
        // Do not round a partly used balance back up to 100%.
        if percent > 0 && percent < 1 { return "<1%" }
        return "\(Int(floor(percent)))%"
    }
    var stale: Bool { !live || Date().timeIntervalSince(updated) > 900 }
    var money: String {
        if id == "refuseless" { return "\(Int(remaining)) credits" }
        return remaining.formatted(.currency(code: "USD"))
    }
    static let initial: [Balance] = [
        Balance(id: "vertex", name: "Vertex AI", baseline: 300, remaining: 300, updated: Date(timeIntervalSince1970: 1792721680), account: "000000-AAAAAA-BBBBBB", expires: "December 25, 2026"),
        Balance(id: "fireworks", name: "Fireworks", baseline: 10.07, remaining: 10.07, updated: Date(timeIntervalSince1970: 1792721600), account: "testuser"),
        Balance(id: "crowbot", name: "Crowbot", baseline: 0, remaining: 0, updated: .distantPast, account: ""),
        Balance(id: "aistudio", name: "Google AI Studio", baseline: 5, remaining: 5, updated: Date(timeIntervalSince1970: 1792721680), account: "Prepaid / Free Tier"),
        Balance(id: "cerebras", name: "Cerebras", baseline: 5, remaining: 5, updated: Date(timeIntervalSince1970: 1792721680), account: "Free Trial / Dev Tier"),
        Balance(id: "refuseless", name: "Refuseless", baseline: 100, remaining: 100, updated: Date(timeIntervalSince1970: 1792721680), account: "DeepSeek Credits")
    ]
}

enum PaymentReference {
    static let standardTiers: [Double] = [5, 10, 15, 20, 25, 50, 100, 150, 200, 250, 300, 500, 1000]

    /// Infers the paid top-up tier from a balance or top-up delta.
    /// For example:
    /// Crowbot paid $5 -> remaining $4.85 -> tier is $5.00.
    /// Fireworks paid $10 -> remaining $10.07 -> tier is $10.00.
    /// Google Cloud grant $300 -> remaining $299.99 -> tier is $300.00.
    static func inferTier(for amount: Double) -> Double {
        guard amount > 0 else { return 0 }
        if abs(amount - 10.07) < 0.05 || (amount >= 10.0 && amount <= 10.08) { return 10.07 }
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

    init(provider: String, remaining: Double, currency: String, account: String, url: String, expires: String?, reference: Double? = nil) {
        self.provider = provider
        self.remaining = remaining
        self.currency = currency
        self.account = account
        self.url = url
        self.expires = expires
        self.reference = reference
    }
}

enum ReadingValidation {
    static func valid(_ r: Reading, balances: [Balance]) -> Bool {
        guard r.remaining.isFinite, r.remaining >= 0, r.remaining < 1_000_000_000,
              (r.currency == "USD" || r.currency == "CREDITS"), let url = URL(string: r.url), url.scheme == "https",
              let balance = balances.first(where: { $0.id == r.provider }) else { return false }
        if r.provider == "vertex" {
            let web = url.host == "console.cloud.google.com" && url.path.hasPrefix("/billing/\(balance.account)/credits")
            let api = url.host == "cloudconsole-pa.clients6.google.com" && url.path == "/v3/entityServices/BillingpricefactorsEntityService/schemas/BILLINGPRICEFACTORS_GRAPHQL:batchGraphql"
            return (web || api) && r.account == balance.account
        }
        if r.provider == "crowbot" {
            return url.absoluteString == CrowbotProvider.endpoint && CrowbotProvider.validAccount(r.account) && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "fireworks" {
            return url.host == "app.fireworks.ai" && r.account == balance.account
        }
        if r.provider == "aistudio" {
            return (url.host == "aistudio.google.com" || url.host == "appsgenaiserver-pa.clients6.google.com") && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "cerebras" {
            return (url.host == "cloud.cerebras.ai" || url.host == "api.cerebras.ai") && (balance.account.isEmpty || r.account == balance.account)
        }
        if r.provider == "refuseless" {
            return (url.host == "refuseless.com" || url.host == "api.refuseless.com") && (balance.account.isEmpty || r.account == balance.account)
        }
        if let endpoint = balance.dynamicEndpoint, let dynamicURL = URL(string: endpoint) {
            return url.host == dynamicURL.host
        }
        return false
    }
}
