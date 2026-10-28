import Foundation

/// Future adapters must return the actual account-wide available money plus
/// active credits, including automatic top-ups. Usage-only estimates do not meet
/// this contract. Credentials belong in macOS Keychain, never in this project.
protocol BalanceProvider: Sendable {
    var providerID: String { get }
    func fetchBalance() async throws -> Reading
}

enum DetectionError: LocalizedError {
    case notConnected
    var errorDescription: String? { "Automatic credit detection is not connected yet." }
}

struct UnconnectedProvider: BalanceProvider {
    let providerID: String
    func fetchBalance() async throws -> Reading { throw DetectionError.notConnected }
}

struct DynamicProvider: BalanceProvider {
    let http: SessionHTTP
    let balance: Balance

    var providerID: String { balance.id }

    func fetchBalance() async throws -> Reading {
        guard let endpointStr = balance.dynamicEndpoint, let url = URL(string: endpointStr) else {
            throw ConnectorError.message("Invalid endpoint for \(balance.name)")
        }
        var headers: [String: String] = [:]
        if let auth = balance.dynamicAuthHeader, !auth.isEmpty {
            headers["Authorization"] = auth.hasPrefix("Bearer ") ? auth : "Bearer \(auth)"
        }
        let (data, response) = try await http.request(url: url, headers: headers)
        guard response.statusCode == 200 else {
            throw ConnectorError.message("\(balance.name) returned HTTP \(response.statusCode)")
        }
        let json = try JSONSerialization.jsonObject(with: data)

        // Special handling for multi-bucket balances (such as Venice AI diem + usd + bundled + earned credits)
        if (balance.id.contains("venice") || endpointStr.contains("venice.ai")),
           let dict = json as? [String: Any],
           let balancesObj = dict["balances"] as? [String: Any] {
            let consumption = (dict["consumptionCurrency"] as? String)?.uppercased()
            let canConsume = (dict["canConsume"] as? Bool) ?? true
            let epoch = (dict["diemEpochAllocation"] as? Double) ?? (dict["diemEpochAllocation"] as? Int).map(Double.init) ?? (dict["diemEpochAllocation"] as? String).flatMap(Double.init)

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

            let remaining: Double
            let currency: String
            let baseline: Double

            // Check if user has explicitly configured a specific path
            if let customPath = balance.dynamicJsonPath, customPath != "balances.total", customPath != "balances.sum" {
                if customPath.hasSuffix("diem") {
                    remaining = canConsume ? (diem ?? 0.0) : 0.0
                    currency = "DIEM"
                    baseline = epoch.map { max($0, remaining) } ?? max(balance.baseline, 100.0)
                } else if customPath.hasSuffix("bundledCredits") {
                    remaining = canConsume ? (bundled ?? 0.0) : 0.0
                    currency = "USD"
                    baseline = remaining > 0 ? max(balance.baseline, PaymentReference.inferTier(for: remaining)) : balance.baseline
                } else if customPath.hasSuffix("earnedCredits") {
                    remaining = canConsume ? (earned ?? 0.0) : 0.0
                    currency = "USD"
                    baseline = remaining > 0 ? max(balance.baseline, PaymentReference.inferTier(for: remaining)) : balance.baseline
                } else {
                    remaining = canConsume ? (usd ?? 0.0) : 0.0
                    currency = "USD"
                    baseline = remaining > 0 ? max(balance.baseline, PaymentReference.inferTier(for: remaining)) : balance.baseline
                }
            } else {
                if consumption == "DIEM", let d = diem {
                    remaining = !canConsume ? 0.0 : d
                    currency = "DIEM"
                    baseline = epoch.map { max($0, d) } ?? max(balance.baseline, 100.0)
                } else if let u = usd {
                    // USD is the primary fiat pool for Venice AI, even when remaining is 0.0
                    remaining = !canConsume ? 0.0 : u
                    currency = "USD"
                    baseline = remaining > 0 ? max(balance.baseline, PaymentReference.inferTier(for: remaining)) : balance.baseline
                } else if let d = diem {
                    remaining = !canConsume ? 0.0 : d
                    currency = "DIEM"
                    baseline = epoch.map { max($0, d) } ?? max(balance.baseline, 100.0)
                } else if let b = bundled {
                    remaining = !canConsume ? 0.0 : b
                    currency = "USD"
                    baseline = remaining > 0 ? max(balance.baseline, PaymentReference.inferTier(for: remaining)) : balance.baseline
                } else {
                    remaining = 0.0
                    currency = "USD"
                    baseline = balance.baseline
                }
            }

            return Reading(
                provider: balance.id,
                remaining: remaining,
                currency: currency,
                account: balance.account.isEmpty ? balance.name : balance.account,
                url: endpointStr,
                expires: nil,
                reference: baseline
            )
        }

        let remaining = try extractDouble(from: json, path: balance.dynamicJsonPath ?? "balance")
        return Reading(
            provider: balance.id,
            remaining: remaining,
            currency: "USD",
            account: balance.account.isEmpty ? balance.name : balance.account,
            url: endpointStr,
            expires: nil,
            reference: balance.baseline
        )
    }

    private func extractDouble(from object: Any, path: String) throws -> Double {
        if (path == "balances.total" || path == "balances.sum"),
           let dict = object as? [String: Any],
           let balancesObj = dict["balances"] as? [String: Any] {
            let consumption = (dict["consumptionCurrency"] as? String)?.uppercased()
            let usd = (balancesObj["usd"] as? Double) ?? (balancesObj["usd"] as? Int).map(Double.init) ?? (balancesObj["usd"] as? String).flatMap(Double.init)
            let diem = (balancesObj["diem"] as? Double) ?? (balancesObj["diem"] as? Int).map(Double.init) ?? (balancesObj["diem"] as? String).flatMap(Double.init)
            if consumption == "DIEM", let d = diem { return d }
            if let u = usd { return u }
            if let d = diem { return d }
            return 0.0
        }
        let parts = path.split(separator: ".")
        var current: Any = object
        for part in parts {
            let key = String(part)
            if let dict = current as? [String: Any], let next = dict[key] {
                current = next
            } else if let arr = current as? [Any], let idx = Int(key), arr.indices.contains(idx) {
                current = arr[idx]
            } else {
                throw ConnectorError.message("Key '\(key)' not found in response JSON.")
            }
        }
        if let d = current as? Double { return d }
        if let i = current as? Int { return Double(i) }
        if let s = current as? String, let d = Double(s) { return d }
        throw ConnectorError.message("Value at '\(path)' is not a numeric balance.")
    }
}
