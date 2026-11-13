import Foundation

/// Pure derivations from CodexBar's `engine-state.json` provider snapshots,
/// shared by the iCloud snapshot writer and the sandboxed test suite. Kept
/// free of AppKit/UI dependencies so `check.command` can compile it directly.
enum CodexBarPacing {
    /// Derives API Bar-style token pacing from a CodexBar provider snapshot:
    /// `tokensPerDay` over active usage days, and `runwayDays` from the
    /// window's remaining spend over the average active-day spend. Returns nil
    /// when the provider publishes no per-day token ledger (e.g. quota-window
    /// providers like Antigravity) or no spend window to derive a runway from.
    ///
    /// Dollar summaries are unreliable across CodexBar providers (not all
    /// models publish pricing), so the widget displays this pacing line
    /// instead of dollar reset descriptions whenever it is available.
    static func pacing(usage: [String: Any], displayWindow: [String: Any]?) -> [String: Any]? {
        guard let mistral = usage["mistralUsage"] as? [String: Any],
              let daily = mistral["daily"] as? [[String: Any]], !daily.isEmpty else {
            return nil
        }

        var activeDays = 0
        var totalTokens = 0.0
        var totalCost = 0.0
        for day in daily {
            let tok = (day["inputTokens"] as? Double ?? 0) + (day["outputTokens"] as? Double ?? 0)
            let cost = day["cost"] as? Double ?? 0
            if tok > 0 || cost > 0 { activeDays += 1 }
            totalTokens += tok
            totalCost += cost
        }
        guard activeDays > 0, totalTokens > 0 else { return nil }
        let tokensPerDay = totalTokens / Double(activeDays)

        // Spend-based runway from the displayed window's dollar summary
        // ("$96.34 / $150.00 · $53.66 left"). Parsed, never displayed as money.
        var runwayDays: Int? = nil
        if let reset = displayWindow?["resetDescription"] as? String,
           let remaining = dollarAmount(after: "· ", in: reset, suffix: " left") {
            let dailySpend = totalCost / Double(activeDays)
            if dailySpend > 0, remaining > 0 {
                runwayDays = max(0, Int(floor(remaining / dailySpend)))
            }
        }
        guard let runway = runwayDays else { return nil }

        return [
            "tokensPerDay": tokensPerDay,
            "runwayDays": runway
        ]
    }

    /// Extracts a dollar figure following `marker` in strings like
    /// "$96.34 / $150.00 · $53.66 left".
    static func dollarAmount(after marker: String, in text: String, suffix: String) -> Double? {
        guard let range = text.range(of: marker) else { return nil }
        let tail = String(text[range.upperBound...])
        let cleaned = tail
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        let value = cleaned.hasSuffix(suffix)
            ? String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            : cleaned.trimmingCharacters(in: .whitespaces)
        return Double(value)
    }
}
