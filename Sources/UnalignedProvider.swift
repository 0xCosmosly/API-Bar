import Foundation

/// Unaligned (unaligned.pw) is a prepaid, per-token inference reseller built on
/// SvelteKit. Balances are read from the signed-in dashboard using the same
/// browser session cookies every other provider uses; no API key is stored.
struct UnalignedProvider: BalanceProvider {
    let providerID = "unaligned"
    let http: SessionHTTP
    let account: String

    static let host = "unaligned.pw"
    /// The dashboard data endpoints, most specific first. They answer with a
    /// SvelteKit node payload once the session cookie is valid and redirect to
    /// `/login` when it is not.
    static let dataEndpoints = [
        "https://unaligned.pw/dashboard/__data.json",
        "https://unaligned.pw/dashboard/billing/__data.json",
        "https://unaligned.pw/dashboard/usage/__data.json"
    ]
    static let dashboardURL = "https://unaligned.pw/dashboard"

    /// A session cookie is anything the app issues for its own origin; the exact
    /// names are not part of the public API, so this accepts the common shapes.
    static func hasValidSession(cookies: [StoredCookie]) -> Bool {
        return cookies.contains { cookie in
            guard cookie.domain.contains("unaligned.pw") else { return false }
            let name = cookie.name.lowercased()
            return name.contains("session") || name.contains("token") || name.contains("auth") || name.contains("sid")
        }
    }

    // MARK: - Parsing

    static func parse(data: Data, url: String) throws -> (remaining: Double, baseline: Double, account: String) {
        // A JSON body must never be re-read as HTML: in a devalue payload the
        // balance is an array index, and regex-scraping it would report the index
        // as a dollar amount.
        let parsedJSON = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if let json = parsedJSON {
            if let parsed = parse(json: json, url: url) { return parsed }
            throw ConnectorError.message("Unaligned did not return a usable balance. The previous balance was retained.")
        }
        if let html = String(data: data, encoding: .utf8) {
            return try parse(html: html)
        }
        throw ConnectorError.message("Could not read the Unaligned balance. The previous balance was retained.")
    }

    static func parse(json: Any, url: String = "") -> (remaining: Double, baseline: Double, account: String)? {
        // A SvelteKit "redirect" payload means the session is no longer signed in.
        if let dict = json as? [String: Any], dict["type"] as? String == "redirect" {
            return nil
        }

        var email = ""
        var remaining: Double? = nil
        var baseline: Double? = nil

        func numeric(_ value: Any?) -> Double? {
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

        /// Unaligned stores the account balance in micro-dollars (4_589_693 is
        /// $4.59 on the dashboard), while the billing ledger reports plain dollars.
        /// Whole values large enough to be micro-dollars are converted; a value
        /// with cents is already dollars.
        func dollars(from raw: Double) -> Double {
            if raw >= 1_000, raw.rounded() == raw { return raw / 1_000_000 }
            return raw
        }

        /// Balance keys are checked before spending keys so a "spent"/"cost" field
        /// can never be mistaken for what is left.
        func findBalance(in obj: Any) -> Double? {
            if let dict = obj as? [String: Any] {
                for key in ["balance", "balanceUsd", "balance_usd", "available", "credit", "credits", "remaining"] {
                    if let found = numeric(dict[key]) { return found }
                    if let nested = dict[key] as? [String: Any] {
                        for nestedKey in ["usd", "amount", "available", "remaining"] {
                            if let found = numeric(nested[nestedKey]) { return found }
                        }
                    }
                }
                for value in dict.values {
                    if let found = findBalance(in: value) { return found }
                }
            } else if let array = obj as? [Any] {
                for value in array {
                    if let found = findBalance(in: value) { return found }
                }
            }
            return nil
        }

        /// Total ever credited, when the page exposes it. Unaligned tops up in
        /// crypto and documents no lifetime total, so this is best-effort.
        func findBaseline(in obj: Any) -> Double? {
            if let dict = obj as? [String: Any] {
                for key in ["totalCredited", "total_credited", "creditedTotal", "deposited", "depositedTotal", "toppedUp", "totalTopUps"] {
                    if let found = numeric(dict[key]), found > 0 { return found }
                }
                for value in dict.values {
                    if let found = findBaseline(in: value) { return found }
                }
            } else if let array = obj as? [Any] {
                for value in array {
                    if let found = findBaseline(in: value) { return found }
                }
            }
            return nil
        }

        func findEmail(in obj: Any) {
            guard email.isEmpty else { return }
            if let dict = obj as? [String: Any] {
                if let value = dict["email"] as? String, value.contains("@") { email = value; return }
                for value in dict.values { findEmail(in: value) }
            } else if let array = obj as? [Any] {
                for value in array { findEmail(in: value) }
            }
        }

        // Strategy A: SvelteKit devalue node arrays, where objects reference values
        // by index into the same `data` array. Nodes may contain nulls, so the
        // array is cast element-wise rather than wholesale.
        var sawDevalue = false
        if let root = json as? [String: Any], let nodes = root["nodes"] as? [Any] {
            func deref(_ value: Any, in data: [Any]) -> Any {
                if let index = value as? Int, index >= 0, index < data.count { return data[index] }
                return value
            }
            for case let node as [String: Any] in nodes {
                if let dataArray = node["data"] as? [Any], let head = dataArray.first as? [String: Any] {
                    sawDevalue = true
                    for key in ["balance", "balanceUsd", "balance_usd", "available", "credit", "credits", "remaining"] {
                        if let found = numeric(deref(head[key] as Any, in: dataArray)) { remaining = dollars(from: found) }
                    }
                    for key in ["totalCredited", "creditedTotal", "deposited", "depositedTotal"] {
                        if let found = numeric(deref(head[key] as Any, in: dataArray)), found > 0 { baseline = found }
                    }
                    if let userRef = head["user"], let user = deref(userRef, in: dataArray) as? [String: Any] {
                        if let emailRef = user["email"], let value = deref(emailRef, in: dataArray) as? String, value.contains("@") { email = value }
                    }
                }
                // The dashboard nests the balance inside a referenced account
                // object, so every value in the node is resolved and inspected.
                guard let dataArray = node["data"] as? [Any] else { continue }
                for element in dataArray {
                    guard let dict = element as? [String: Any] else { continue }
                    for key in ["balance", "balanceUsd", "balance_usd", "available", "credit", "credits", "remaining"] {
                        guard let value = dict[key] else { continue }
                        let resolved = deref(value, in: dataArray)
                        // A value that still resolves to a dictionary is not an amount.
                        if let found = numeric(resolved) {
                            if remaining == nil { remaining = dollars(from: found) }
                        }
                    }
                    if email.isEmpty, let value = dict["email"], let text = deref(value, in: dataArray) as? String, text.contains("@") {
                        email = text
                    }
                    if baseline == nil {
                        for key in ["totalCredited", "creditedTotal", "deposited", "depositedTotal"] {
                            if let value = dict[key], let found = numeric(deref(value, in: dataArray)), found > 0 { baseline = found }
                        }
                    }
                }
            }
        }

        // Strategy B: plain object inspection. Skipped for devalue payloads, where
        // a bare integer under a balance key is an index, not an amount.
        if remaining == nil && !sawDevalue, let found = findBalance(in: json) { remaining = dollars(from: found) }
        if baseline == nil { baseline = findBaseline(in: json) }
        if email.isEmpty { findEmail(in: json) }

        guard let balance = remaining, balance.isFinite, balance >= 0, balance < 1_000_000_000 else { return nil }
        let reference = (baseline ?? 0) > 0 ? max(baseline!, balance) : PaymentReference.inferTier(for: balance)
        return (remaining: balance, baseline: reference, account: email)
    }

    static func parse(html: String) throws -> (remaining: Double, baseline: Double, account: String) {
        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)

        var balance: Double? = nil
        var baseline: Double? = nil

        // Rendered balance figure, e.g. <span class="balance-figure">$12.34</span>
        for pattern in [
            #"class=["'][^"']*balance-figure[^"']*["'][^>]*>\s*\$?([0-9][0-9,]*(?:\.[0-9]+)?)"#,
            #"class=["'][^"']*balance[^"']*["'][^>]*>\s*\$([0-9][0-9,]*(?:\.[0-9]+)?)"#
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: range), match.numberOfRanges > 1 {
                let raw = nsHtml.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                if let value = Double(raw) { balance = value; break }
            }
        }

        // Serialized SvelteKit payload embedded in the page.
        if balance == nil,
           let regex = try? NSRegularExpression(pattern: #"(?:\\?"balance(?:Usd|_usd)?\\?")\s*:\s*([0-9]+(?:\.[0-9]+)?)"#),
           let match = regex.firstMatch(in: html, range: range), match.numberOfRanges > 1 {
            let raw = nsHtml.substring(with: match.range(at: 1))
            if let value = Double(raw) { balance = value }
        }

        if let regex = try? NSRegularExpression(pattern: #"(?:totalCredited|creditedTotal|depositedTotal)\\?"?\s*:\s*([0-9]+(?:\.[0-9]+)?)"#),
           let match = regex.firstMatch(in: html, range: range), match.numberOfRanges > 1 {
            let raw = nsHtml.substring(with: match.range(at: 1))
            if let value = Double(raw), value > 0 { baseline = value }
        }

        guard let balance else {
            throw ConnectorError.message("Could not read the Unaligned balance. The previous balance was retained.")
        }
        let reference = (baseline ?? 0) > 0 ? max(baseline!, balance) : PaymentReference.inferTier(for: balance)
        return (remaining: balance, baseline: reference, account: extractEmail(from: html))
    }

    private static func extractEmail(from html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+"#) else { return "" }
        let nsHtml = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length)) {
            let candidate = nsHtml.substring(with: match.range)
            if !candidate.hasPrefix("support@") && !candidate.hasPrefix("hello@") && !candidate.contains("example.com") {
                return candidate
            }
        }
        return ""
    }

    /// Sum of completed crypto top-ups from the billing ledger. Unaligned pays out
    /// per token from a prepaid balance, so what was actually paid in is the honest
    /// 100% reference. Ledger rows are devalue payloads, so values are resolved
    /// through their array references before they are read.
    static func topUpTotal(json: Any) -> Double? {
        var total: Double = 0
        var sawRow = false

        func numeric(_ value: Any?) -> Double? {
            if let number = value as? NSNumber { return number.doubleValue }
            if let string = value as? String {
                return Double(string.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
            }
            return nil
        }

        func scan(_ obj: Any, resolve: (Any) -> Any) {
            if let dict = obj as? [String: Any] {
                let status = (resolve(dict["status"] as Any) as? String)?.lowercased()
                if let status, ["paid", "completed", "confirmed", "credited"].contains(status) {
                    let amount = numeric(resolve(dict["usd"] as Any))
                        ?? numeric(resolve(dict["amount"] as Any))
                        ?? numeric(resolve(dict["credited"] as Any))
                    if let amount, amount > 0, amount < 1_000_000 {
                        total += amount
                        sawRow = true
                    }
                }
                for value in dict.values { scan(value, resolve: resolve) }
            } else if let array = obj as? [Any] {
                for value in array { scan(value, resolve: resolve) }
            }
        }

        let identity: (Any) -> Any = { $0 }
        if let root = json as? [String: Any], let nodes = root["nodes"] as? [Any] {
            for case let node as [String: Any] in nodes {
                guard let dataArray = node["data"] as? [Any] else { continue }
                let deref: (Any) -> Any = { value in
                    if let index = value as? Int, index >= 0, index < dataArray.count { return dataArray[index] }
                    return value
                }
                for element in dataArray { scan(element, resolve: deref) }
            }
        } else {
            scan(json, resolve: identity)
        }
        return sawRow ? total : nil
    }

    // MARK: - Fetch

    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        if !Self.hasValidSession(cookies: cookies), (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
            cookies = await http.cookies
        }
        guard Self.hasValidSession(cookies: cookies) else {
            throw ConnectorError.message("No Unaligned sign-in was found. Sign in at unaligned.pw in Brave, then reconnect.")
        }

        var lastError: Error = ConnectorError.message("Could not read the Unaligned balance. The previous balance was retained.")
        for endpoint in Self.dataEndpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                let (data, response) = try await http.request(url: url)
                guard response.statusCode == 200 else {
                    lastError = ConnectorError.message("Unaligned returned HTTP \(response.statusCode). The previous balance was retained.")
                    continue
                }
                let parsed = try Self.parse(data: data, url: endpoint)
                guard !parsed.account.isEmpty || account.isEmpty || account.hasSuffix(" Account") || account == parsed.account else {
                    throw ConnectorError.message("This Unaligned sign-in belongs to a different account. The previous balance was retained.")
                }
                // A verified top-up total always wins over an inferred tier.
                var baseline = parsed.baseline
                if let billingURL = URL(string: Self.dataEndpoints[1]),
                   let (billingData, billingResponse) = try? await http.request(url: billingURL),
                   billingResponse.statusCode == 200,
                   let billingJSON = try? JSONSerialization.jsonObject(with: billingData, options: [.fragmentsAllowed]),
                   let topUps = Self.topUpTotal(json: billingJSON), topUps > 0 {
                    baseline = max(topUps, parsed.remaining)
                }
                try await http.persist()
                return Reading(
                    provider: "unaligned",
                    remaining: parsed.remaining,
                    currency: "USD",
                    account: parsed.account,
                    url: endpoint,
                    expires: nil,
                    reference: baseline
                )
            } catch {
                lastError = error
            }
        }

        // Fall back to the rendered dashboard page, which also carries the
        // balance for clients that receive the HTML document.
        if let url = URL(string: Self.dashboardURL) {
            do {
                let (data, response) = try await http.request(url: url)
                if response.statusCode == 200, let html = String(data: data, encoding: .utf8) {
                    let parsed = try Self.parse(html: html)
                    try await http.persist()
                    return Reading(
                        provider: "unaligned",
                        remaining: parsed.remaining,
                        currency: "USD",
                        account: parsed.account,
                        url: Self.dashboardURL,
                        expires: nil,
                        reference: parsed.baseline
                    )
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
