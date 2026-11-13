import Foundation

/// Produces specific, human-readable descriptions of what a sync cycle
/// actually moved, by diffing the previous cloud state against the new local
/// state. Deterministic: every phrase maps to an observed difference, never to
/// an inference about intent.
///
/// Kept free of AppKit so the test suite compiles it directly.
enum SyncChangeLog {
    /// Compares two provider sets and describes the differences.
    /// `old` is the previously synced snapshot, `new` the current local state.
    static func providerChanges(old: [Balance], new: [Balance]) -> [String] {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newByID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var changes: [String] = []

        for balance in new where oldByID[balance.id] == nil {
            changes.append("Added \(balance.name) provider")
        }
        for balance in old where newByID[balance.id] == nil {
            changes.append("Removed \(balance.name) provider")
        }

        for balance in new {
            guard let previous = oldByID[balance.id] else { continue }
            if abs(previous.baseline - balance.baseline) > 0.000001 {
                changes.append("Updated \(balance.name) baseline")
            }
            if previous.disabled != balance.disabled {
                changes.append(balance.isEnabled ? "Resumed \(balance.name)" : "Paused \(balance.name)")
            }
            if previous.account != balance.account, !balance.account.isEmpty {
                changes.append("Reconnected \(balance.name) account")
            }
        }
        return changes
    }

    /// Describes harness config differences by file name.
    static func harnessChanges(harness: String, old: Set<String>, new: Set<String>) -> [String] {
        var changes: [String] = []
        let added = new.subtracting(old)
        let removed = old.subtracting(new)
        if !added.isEmpty {
            let names = added.sorted().joined(separator: ", ")
            changes.append("Added \(harness) \(names)")
        }
        if !removed.isEmpty {
            let names = removed.sorted().joined(separator: ", ")
            changes.append("Removed \(harness) \(names)")
        }
        return changes
    }

    /// Joins phrases into one sentence, capped so the card stays readable.
    static func sentence(_ changes: [String], limit: Int = 3) -> String {
        guard !changes.isEmpty else { return "No changes — everything was already current." }
        let shown = Array(changes.prefix(limit))
        let remaining = changes.count - shown.count
        var text: String
        switch shown.count {
        case 1: text = shown[0]
        case 2: text = "\(shown[0]) and \(shown[1])"
        default: text = shown.dropLast().joined(separator: ", ") + ", and \(shown.last!)"
        }
        if remaining > 0 {
            text += " (+\(remaining) more)"
        }
        return text + "."
    }
}
