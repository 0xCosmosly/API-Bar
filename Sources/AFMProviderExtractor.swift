import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct KnownProviderMeta: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let domain: String
    public let dashboardURL: String
    public let endpoint: String
    public let jsonPath: String
    public let defaultBaseline: Double
    public let aliases: [String]

    public init(id: String, name: String, domain: String, dashboardURL: String, endpoint: String, jsonPath: String, defaultBaseline: Double = 0.0, aliases: [String]) {
        self.id = id
        self.name = name
        self.domain = domain
        self.dashboardURL = dashboardURL
        self.endpoint = endpoint
        self.jsonPath = jsonPath
        self.defaultBaseline = defaultBaseline
        self.aliases = aliases
    }
}

public struct AFMDetectedDraft: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var endpoint: String
    public var jsonPath: String
    public var detectedBalance: Double
    public var baseline: Double
    public var cookieDomain: String
    public var authHeader: String?

    public init(id: String, name: String, endpoint: String, jsonPath: String, detectedBalance: Double, baseline: Double, cookieDomain: String, authHeader: String? = nil) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.jsonPath = jsonPath
        self.detectedBalance = detectedBalance
        self.baseline = baseline
        self.cookieDomain = cookieDomain
        self.authHeader = authHeader
    }
}

public enum AFMProviderExtractor {
    /// Providers verified to work reliably out-of-the-box via native browser sessions or tested AFM extraction
    public static let verifiedProviders: [KnownProviderMeta] = [
        KnownProviderMeta(
            id: "venice",
            name: "Venice AI",
            domain: "venice.ai",
            dashboardURL: "https://venice.ai/settings/api",
            endpoint: "https://api.venice.ai/api/v1/billing/balance",
            jsonPath: "balances.usd",
            defaultBaseline: 0.0,
            aliases: ["venice", "venice ai", "venice.ai"]
        ),
        KnownProviderMeta(
            id: "vertex",
            name: "Vertex AI",
            domain: "cloud.google.com",
            dashboardURL: "https://console.cloud.google.com/billing",
            endpoint: "https://cloudbilling.googleapis.com",
            jsonPath: "balance",
            defaultBaseline: 300.0,
            aliases: ["vertex", "vertex ai", "google cloud", "gcp"]
        ),
        KnownProviderMeta(
            id: "fireworks",
            name: "Fireworks",
            domain: "fireworks.ai",
            dashboardURL: "https://app.fireworks.ai/billing",
            endpoint: "https://app.fireworks.ai/api/v2/accounts/me",
            jsonPath: "balance",
            defaultBaseline: 10.07,
            aliases: ["fireworks", "fireworks ai", "fireworks.ai"]
        ),
        KnownProviderMeta(
            id: "aistudio",
            name: "Google AI Studio",
            domain: "aistudio.google.com",
            dashboardURL: "https://aistudio.google.com",
            endpoint: "https://aistudio.google.com",
            jsonPath: "balance",
            defaultBaseline: 5.0,
            aliases: ["aistudio", "google ai studio", "gemini"]
        ),
        KnownProviderMeta(
            id: "cerebras",
            name: "Cerebras",
            domain: "cerebras.ai",
            dashboardURL: "https://cloud.cerebras.ai",
            endpoint: "https://api.cerebras.ai/v1/models",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: ["cerebras", "cerebras ai"]
        ),
        KnownProviderMeta(
            id: "refuseless",
            name: "Refuseless",
            domain: "refuseless.com",
            dashboardURL: "https://refuseless.com",
            endpoint: "https://api.refuseless.com/v1/billing",
            jsonPath: "balance",
            defaultBaseline: 100.0,
            aliases: ["refuseless", "deepseek credits"]
        ),
        KnownProviderMeta(
            id: "crowbot",
            name: "Crowbot",
            domain: "crowbot.sh",
            dashboardURL: "https://chat.crowbot.sh",
            endpoint: "https://chat.crowbot.sh/api/me",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: ["crowbot", "chat.crowbot.sh"]
        )
    ]

    public static let knownProviderList: [KnownProviderMeta] = verifiedProviders + [
        KnownProviderMeta(
            id: "groq",
            name: "Groq",
            domain: "groq.com",
            dashboardURL: "https://console.groq.com/keys",
            endpoint: "https://api.groq.com/openai/v1/models",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: ["groq", "groq.com", "groq cloud"]
        ),
        KnownProviderMeta(
            id: "openrouter",
            name: "OpenRouter",
            domain: "openrouter.ai",
            dashboardURL: "https://openrouter.ai/credits",
            endpoint: "https://openrouter.ai/api/v1/credits",
            jsonPath: "data.total_credits_left",
            defaultBaseline: 10.0,
            aliases: ["openrouter", "open router", "openrouter.ai"]
        ),
        KnownProviderMeta(
            id: "together",
            name: "Together AI",
            domain: "together.ai",
            dashboardURL: "https://api.together.ai/settings/billing",
            endpoint: "https://api.together.xyz/v1/users/me",
            jsonPath: "credit_limit",
            defaultBaseline: 0.0,
            aliases: ["together", "together ai", "together.ai", "together.xyz"]
        ),
        KnownProviderMeta(
            id: "mistral",
            name: "Mistral AI",
            domain: "mistral.ai",
            dashboardURL: "https://console.mistral.ai/billing/",
            endpoint: "https://api.mistral.ai/v1/models",
            jsonPath: "balance",
            defaultBaseline: 10.0,
            aliases: ["mistral", "mistral ai", "mistral.ai"]
        ),
        KnownProviderMeta(
            id: "deepinfra",
            name: "DeepInfra",
            domain: "deepinfra.com",
            dashboardURL: "https://deepinfra.com/dash/billing",
            endpoint: "https://api.deepinfra.com/models/list",
            jsonPath: "balance",
            defaultBaseline: 10.0,
            aliases: ["deepinfra", "deep infra", "deepinfra.com"]
        ),
        KnownProviderMeta(
            id: "perplexity",
            name: "Perplexity",
            domain: "perplexity.ai",
            dashboardURL: "https://www.perplexity.ai/settings/api",
            endpoint: "https://api.perplexity.ai/models",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: ["perplexity", "perplexity ai", "perplexity.ai"]
        ),
        KnownProviderMeta(
            id: "anthropic",
            name: "Anthropic",
            domain: "anthropic.com",
            dashboardURL: "https://console.anthropic.com/settings/billing",
            endpoint: "https://api.anthropic.com/v1/models",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: ["anthropic", "claude", "anthropic.com"]
        ),
        KnownProviderMeta(
            id: "openai",
            name: "OpenAI",
            domain: "openai.com",
            dashboardURL: "https://platform.openai.com/usage",
            endpoint: "https://api.openai.com/v1/dashboard/billing/credit_grants",
            jsonPath: "total_available",
            defaultBaseline: 0.0,
            aliases: ["openai", "chatgpt", "openai.com"]
        ),
        KnownProviderMeta(
            id: "cohere",
            name: "Cohere",
            domain: "cohere.com",
            dashboardURL: "https://dashboard.cohere.com/billing",
            endpoint: "https://api.cohere.com/v1/models",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: ["cohere", "cohere.com"]
        ),
        KnownProviderMeta(
            id: "replicate",
            name: "Replicate",
            domain: "replicate.com",
            dashboardURL: "https://replicate.com/account/billing",
            endpoint: "https://api.replicate.com/v1/account",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: ["replicate", "replicate.com"]
        )
    ]

    public static func resolveProvider(named raw: String) -> KnownProviderMeta {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for meta in knownProviderList {
            if meta.id == trimmed || meta.name.lowercased() == trimmed || meta.domain == trimmed || meta.aliases.contains(trimmed) {
                return meta
            }
        }
        for meta in knownProviderList {
            if meta.name.lowercased().contains(trimmed) || trimmed.contains(meta.name.lowercased()) || trimmed.contains(meta.id) {
                return meta
            }
        }
        let cleanName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeID = cleanName.lowercased().filter { $0.isLetter || $0.isNumber }
        let domain: String
        if cleanName.contains(".") {
            domain = cleanName.lowercased()
        } else {
            domain = "\(safeID.isEmpty ? "custom" : safeID).ai"
        }
        return KnownProviderMeta(
            id: safeID.isEmpty ? "custom" : safeID,
            name: cleanName.isEmpty ? "Custom Provider" : cleanName,
            domain: domain,
            dashboardURL: "https://\(domain)",
            endpoint: "https://api.\(domain)/v1/billing",
            jsonPath: "balance",
            defaultBaseline: 0.0,
            aliases: [trimmed]
        )
    }

    public static func autoAddProvider(
        named name: String,
        clipboardText: String? = nil,
        openBrowser: Bool = true
    ) async -> (draft: AFMDetectedDraft, dashboardURL: String, message: String) {
        let meta = resolveProvider(named: name)

        // 1. Automatically try to open the usage dashboard
        if openBrowser, let url = URL(string: meta.dashboardURL) {
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }

        var detectedBalance = 0.0
        var detectedBaseline = meta.defaultBaseline
        var authHeader: String? = nil
        var jsonPath = meta.jsonPath

        // 2. Check clipboard in case user recently copied an API key or cURL command
        if let clip = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
            let headerPattern = #"(?i)-h\s+["']authorization:\s*([^"']+)["']"#
            if let regex = try? NSRegularExpression(pattern: headerPattern),
               let match = regex.firstMatch(in: clip, options: [], range: NSRange(location: 0, length: clip.utf16.count)) {
                let range = Range(match.range(at: 1), in: clip)!
                authHeader = String(clip[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let tokenPattern = #"\b((?:venice_|sk-|gsk_)[A-Za-z0-9_\-]{16,})\b"#
                if let regex = try? NSRegularExpression(pattern: tokenPattern),
                   let match = regex.firstMatch(in: clip, options: [], range: NSRange(location: 0, length: clip.utf16.count)) {
                    let range = Range(match.range(at: 1), in: clip)!
                    authHeader = "Bearer \(clip[range])"
                }
            }

            if let parsed = try? extract(from: clip), parsed.detectedBalance > 0 {
                detectedBalance = parsed.detectedBalance
                detectedBaseline = parsed.baseline
                if !parsed.jsonPath.isEmpty { jsonPath = parsed.jsonPath }
                if let ah = parsed.authHeader { authHeader = ah }
            }
        }

        // 3. Check for existing Brave cookies if no authHeader
        var cookieHeader: String? = nil
        if authHeader == nil {
            if let cookies = try? BraveSessionImporter.read(provider: meta.id, cookieDomain: meta.domain, interactive: false), !cookies.isEmpty {
                cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
        }

        // 4. Try live probe of endpoint if authHeader or cookies are available
        if (authHeader != nil || cookieHeader != nil), let url = URL(string: meta.endpoint) {
            var req = URLRequest(url: url)
            if let auth = authHeader {
                req.setValue(auth.hasPrefix("Bearer ") ? auth : "Bearer \(auth)", forHTTPHeaderField: "Authorization")
            }
            if let ch = cookieHeader {
                req.setValue(ch, forHTTPHeaderField: "Cookie")
            }
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 4.0
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
               let jsonString = String(data: data, encoding: .utf8),
               let parsed = try? extract(from: jsonString) {
                detectedBalance = parsed.detectedBalance
                detectedBaseline = parsed.baseline
                jsonPath = parsed.jsonPath
            }
        }

        let draftBaseline = detectedBalance > 0 ? max(detectedBaseline, detectedBalance) : 0.0
        let draft = AFMDetectedDraft(
            id: meta.id,
            name: meta.name,
            endpoint: meta.endpoint,
            jsonPath: jsonPath,
            detectedBalance: detectedBalance,
            baseline: draftBaseline,
            cookieDomain: meta.domain,
            authHeader: authHeader
        )

        let msg = "Opened \(meta.name) dashboard (\(meta.dashboardURL)) in your browser."
        return (draft, meta.dashboardURL, msg)
    }

    private static let knownProviders: [String: (name: String, defaultEndpoint: String, defaultPath: String)] = [
        "groq.com": ("Groq", "https://api.groq.com/openai/v1/models", "balance"),
        "openrouter.ai": ("OpenRouter", "https://openrouter.ai/api/v1/credits", "data.total_credits_left"),
        "together.ai": ("Together AI", "https://api.together.xyz/v1/users/me", "credit_limit"),
        "together.xyz": ("Together AI", "https://api.together.xyz/v1/users/me", "credit_limit"),
        "deepinfra.com": ("DeepInfra", "https://api.deepinfra.com/models/list", "balance"),
        "mistral.ai": ("Mistral AI", "https://api.mistral.ai/v1/models", "balance"),
        "cohere.com": ("Cohere", "https://api.cohere.com/v1/models", "balance"),
        "replicate.com": ("Replicate", "https://api.replicate.com/v1/account", "balance"),
        "perplexity.ai": ("Perplexity", "https://api.perplexity.ai/models", "balance"),
        "anthropic.com": ("Anthropic", "https://api.anthropic.com/v1/models", "balance"),
        "openai.com": ("OpenAI", "https://api.openai.com/v1/dashboard/billing/credit_grants", "total_available"),
        "venice.ai": ("Venice AI", "https://api.venice.ai/api/v1/billing/balance", "balances.usd")
    ]

    private static let balanceKeywords: [String: Int] = [
        "remaining_credits": 100,
        "total_credits_left": 100,
        "balances.usd": 100,
        "remaining_balance": 95,
        "credit_balance": 95,
        "usd": 92,
        "total_available": 90,
        "available_credits": 90,
        "credits_remaining": 90,
        "available_balance": 90,
        "remaining": 85,
        "balance": 85,
        "credits": 80,
        "diem": 70,
        "credit": 70,
        "allowance": 60,
        "grant": 50,
        "amount": 40
    ]

    public static func extract(from rawInput: String) throws -> AFMDetectedDraft {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw ConnectorError.message("Input is empty. Paste a URL, cURL command, or JSON response.")
        }

        var detectedURL: String?
        var detectedDomain: String?
        var detectedJson: Any?
        var detectedAuthHeader: String?

        // 1. Check for Authorization header in cURL / text:
        // e.g. -H "Authorization: Bearer xxx" or -H 'Authorization: xxx'
        let headerPattern = #"(?i)-h\s+["']authorization:\s*([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: headerPattern),
           let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
            let range = Range(match.range(at: 1), in: input)!
            detectedAuthHeader = String(input[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Check for raw "Bearer ..." or "Authorization: Bearer ..."
        if detectedAuthHeader == nil {
            let bearerPattern = #"(?i)(?:authorization:\s*)?(bearer\s+[A-Za-z0-9_\-\.]+)"#
            if let regex = try? NSRegularExpression(pattern: bearerPattern),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
                let range = Range(match.range(at: 1), in: input)!
                detectedAuthHeader = String(input[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Check for token pattern e.g. "venice_..." or "sk-..." or "gsk_..."
        if detectedAuthHeader == nil {
            let tokenPattern = #"\b((?:venice_|sk-|gsk_)[A-Za-z0-9_\-]{16,})\b"#
            if let regex = try? NSRegularExpression(pattern: tokenPattern),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
                let range = Range(match.range(at: 1), in: input)!
                let token = String(input[range])
                detectedAuthHeader = "Bearer \(token)"
            }
        }

        // 2. Check for cURL command
        if input.lowercased().hasPrefix("curl ") || input.contains("curl 'http") || input.contains("curl \"http") {
            let pattern = #"https?://[^\s'"\\]+"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
                let range = Range(match.range, in: input)!
                detectedURL = String(input[range])
            }
        }

        // 2. Check for URL if not found in cURL
        if detectedURL == nil, input.lowercased().hasPrefix("http://") || input.lowercased().hasPrefix("https://") {
            let parts = input.components(separatedBy: .whitespacesAndNewlines)
            detectedURL = parts.first
        }

        // 3. Check for JSON snippet in input
        if let jsonStart = input.firstIndex(of: "{"), let jsonEnd = input.lastIndex(of: "}"), jsonStart < jsonEnd {
            let jsonString = String(input[jsonStart...jsonEnd])
            if let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                detectedJson = parsed
            }
        }

        // 4. Derive host & domain
        if let urlStr = detectedURL, let url = URL(string: urlStr), let host = url.host {
            let hostParts = host.split(separator: ".")
            if hostParts.count >= 2 {
                detectedDomain = hostParts.suffix(2).joined(separator: ".")
            } else {
                detectedDomain = host
            }
        } else if let dict = detectedJson as? [String: Any],
                  (dict["diemEpochAllocation"] != nil || (dict["balances"] as? [String: Any])?["diem"] != nil) {
            detectedDomain = "venice.ai"
        }

        // 5. Provider Name resolution
        var providerName = "Custom Provider"
        var providerID = "custom"
        var endpoint = detectedURL ?? "https://api.example.com/v1/billing"
        var jsonPath = "balance"
        var balance = 0.0

        if let domain = detectedDomain?.lowercased() {
            if let known = knownProviders[domain] {
                providerName = known.name
                providerID = domain.components(separatedBy: ".").first ?? "custom"
                let isApiEndpoint = detectedURL?.contains("/api/") == true || detectedURL?.contains("/v1/") == true || detectedURL?.contains("/billing/") == true
                if detectedURL == nil || !isApiEndpoint {
                    endpoint = known.defaultEndpoint
                }
                jsonPath = known.defaultPath
            } else {
                let nameCandidate = domain.components(separatedBy: ".").first?.capitalized ?? "Custom"
                providerName = nameCandidate
                providerID = nameCandidate.lowercased().filter { $0.isLetter || $0.isNumber }
            }
        }

        var detectedEpochAllocation: Double? = nil

        // 6. JSON Key and Balance extraction
        if let json = detectedJson {
            var balancesHandled = false
            if let dict = json as? [String: Any] {
                let consumption = (dict["consumptionCurrency"] as? String)?.uppercased()
                let canConsume = (dict["canConsume"] as? Bool) ?? true
                if let epoch = (dict["diemEpochAllocation"] as? Double) ?? (dict["diemEpochAllocation"] as? Int).map(Double.init) ?? (dict["diemEpochAllocation"] as? String).flatMap(Double.init) {
                    detectedEpochAllocation = epoch
                }
                if let balancesObj = dict["balances"] as? [String: Any] {
                    func findNum(_ keys: [String]) -> Double? {
                        for k in keys {
                            if let val = balancesObj[k] {
                                if let d = val as? Double { return d }
                                if let i = val as? Int { return Double(i) }
                                if let s = val as? String, let d = Double(s) { return d }
                            }
                        }
                        for (k, val) in balancesObj {
                            if keys.contains(where: { $0.caseInsensitiveCompare(k) == .orderedSame }) {
                                if let d = val as? Double { return d }
                                if let i = val as? Int { return Double(i) }
                                if let s = val as? String, let d = Double(s) { return d }
                            }
                        }
                        return nil
                    }

                    let usd = findNum(["usd", "usdBalance", "usd_balance"])
                    let diem = findNum(["diem", "diemBalance", "diem_balance"])
                    let bundled = findNum(["bundledCredits", "bundled_credits", "bundled"])
                    let earned = findNum(["earnedCredits", "earned_credits", "earned"])

                    if consumption == "DIEM", let d = diem {
                        balance = !canConsume ? 0.0 : d
                        jsonPath = "balances.diem"
                        balancesHandled = true
                    } else if (consumption == "BUNDLED" || consumption == "BUNDLEDCREDITS"), let b = bundled {
                        balance = !canConsume ? 0.0 : b
                        jsonPath = "balances.bundledCredits"
                        balancesHandled = true
                    } else if (consumption == "EARNED" || consumption == "EARNEDCREDITS"), let e = earned {
                        balance = !canConsume ? 0.0 : e
                        jsonPath = "balances.earnedCredits"
                        balancesHandled = true
                    } else if let u = usd {
                        // USD is the primary fiat pool for Venice AI, even when balance is 0.0
                        balance = !canConsume ? 0.0 : u
                        jsonPath = "balances.usd"
                        balancesHandled = true
                    } else if let d = diem {
                        balance = !canConsume ? 0.0 : d
                        jsonPath = "balances.diem"
                        balancesHandled = true
                    } else if let b = bundled {
                        balance = !canConsume ? 0.0 : b
                        jsonPath = "balances.bundledCredits"
                        balancesHandled = true
                    } else if let e = earned {
                        balance = !canConsume ? 0.0 : e
                        jsonPath = "balances.earnedCredits"
                        balancesHandled = true
                    }
                }
            }

            if !balancesHandled {
                var bestScore = -1
                var bestPath = "balance"
                var bestValue: Double = 0

                func scan(obj: Any, currentPath: String) {
                    if let dict = obj as? [String: Any] {
                        for (k, v) in dict {
                            let lowerK = k.lowercased()
                            let path = currentPath.isEmpty ? k : "\(currentPath).\(k)"
                            let score: Int
                            if let num = v as? Double {
                                score = scoreKey(lowerK, fullPath: path)
                                if score > bestScore {
                                    bestScore = score; bestPath = path; bestValue = num
                                }
                            } else if let num = v as? Int {
                                score = scoreKey(lowerK, fullPath: path)
                                if score > bestScore {
                                    bestScore = score; bestPath = path; bestValue = Double(num)
                                }
                            } else if let str = v as? String, let num = Double(str) {
                                score = scoreKey(lowerK, fullPath: path)
                                if score > bestScore {
                                    bestScore = score; bestPath = path; bestValue = num
                                }
                            } else {
                                scan(obj: v, currentPath: path)
                            }
                        }
                    } else if let arr = obj as? [Any] {
                        for (idx, item) in arr.enumerated() {
                            scan(obj: item, currentPath: "\(currentPath).\(idx)")
                        }
                    }
                }

                scan(obj: json, currentPath: "")
                if bestScore > 0 {
                    jsonPath = bestPath
                    balance = max(0, bestValue)
                }
            }
        }

        let finalBaseline: Double
        if balance > 0 {
            let inferred = PaymentReference.inferTier(for: balance)
            if jsonPath.contains("diem"), let epoch = detectedEpochAllocation {
                finalBaseline = max(epoch, balance)
            } else {
                finalBaseline = max(inferred, balance)
            }
        } else {
            finalBaseline = 0.0
        }

        return AFMDetectedDraft(
            id: providerID.isEmpty ? "custom" : providerID,
            name: providerName,
            endpoint: endpoint,
            jsonPath: jsonPath,
            detectedBalance: balance,
            baseline: finalBaseline,
            cookieDomain: detectedDomain ?? "example.com",
            authHeader: detectedAuthHeader
        )
    }

    private static func scoreKey(_ key: String, fullPath: String) -> Int {
        let full = fullPath.lowercased()
        let short = key.lowercased()
        for (k, score) in balanceKeywords {
            if full == k { return score + 10 }
            if full.hasSuffix("." + k) { return score + 5 }
            if short == k { return score }
            if full.contains(k) { return score - 5 }
        }
        return 0
    }
}
