import Foundation

/// Produces specific, human-readable descriptions of what a sync cycle
/// actually moved, by diffing the previous cloud state against the new local
/// state. Deterministic: every phrase maps to an observed difference, never to
/// an inference about intent.
///
/// Kept free of AppKit so the test suite compiles it directly.
enum SyncChangeLog {
    /// Friendly display name for a provider identifier.
    static func displayName(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let known: [String: String] = [
            "mistral": "Mistral",
            "mistral-vibe": "Mistral",
            "heimdallm": "Heimdallm",
            "inferhub": "InferHub",
            "refuseless": "Refuseless",
            "lutheos": "Lutheos",
            "unaligned": "Unaligned",
            "yeta": "Yeta",
            "crowbot": "Crowbot",
            "togetherai": "Together AI",
            "together": "Together AI",
            "fireworks": "Fireworks",
            "cerebras": "Cerebras",
            "vertex": "Vertex AI",
            "aistudio": "AI Studio",
            "opencode": "OpenCode",
            "anthropic": "Anthropic",
            "openai": "OpenAI",
            "groq": "Groq",
            "openrouter": "OpenRouter",
            "deepseek": "DeepSeek"
        ]
        if let match = known[lower] { return match }
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "-_ "))
        let capitalized = parts.filter { !$0.isEmpty }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return capitalized.joined(separator: " ")
    }

    /// Provider name resolved from a vault session file (e.g. "inferhub.dat" -> "InferHub").
    static func vaultSessionName(for filename: String) -> String {
        var base = filename
        if base.hasSuffix(".dat") {
            base = String(base.dropLast(4))
        }
        return displayName(for: base)
    }

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

    /// Parses provider-to-model mapping from YAML or JSON model configs.
    static func parseModelProviders(from data: Data, filename: String) -> [String: [String]] {
        let lowerName = filename.lowercased()
        if lowerName.hasSuffix(".yml") || lowerName.hasSuffix(".yaml") {
            if let text = String(data: data, encoding: .utf8) {
                return parseYAMLProviders(text)
            }
        } else if lowerName.hasSuffix(".json") {
            return parseJSONProviders(data)
        }
        return [:]
    }

    static func parseYAMLProviders(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        let lines = text.components(separatedBy: .newlines)
        var currentProvider: String? = nil
        var inModels = false
        var modelItemIndent: Int? = nil
        var currentModels: [String] = []

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = raw.prefix(while: { $0 == " " }).count

            if indent == 2 && trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") && !trimmed.contains(" ") {
                let key = String(trimmed.dropLast())
                if let p = currentProvider {
                    result[p] = currentModels
                }
                currentProvider = key
                inModels = false
                modelItemIndent = nil
                currentModels = []
                continue
            }

            if indent == 4 && (trimmed == "models:" || trimmed.hasPrefix("models:")) {
                inModels = true
                modelItemIndent = nil
                continue
            }

            if inModels {
                if indent <= 4 && trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") {
                    inModels = false
                    modelItemIndent = nil
                } else if trimmed.hasPrefix("-") {
                    if modelItemIndent == nil {
                        modelItemIndent = indent
                    }
                    if indent == modelItemIndent {
                        let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                        if rest.hasPrefix("id:") {
                            let idVal = rest.dropFirst(3).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                            if !idVal.isEmpty { currentModels.append(idVal) }
                        } else if !rest.isEmpty && !rest.hasPrefix("name:") {
                            currentModels.append(rest)
                        }
                    }
                } else if trimmed.hasPrefix("id:") && (modelItemIndent == nil || indent == (modelItemIndent! + 2) || indent == modelItemIndent!) {
                    let idVal = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !idVal.isEmpty && (currentModels.isEmpty || currentModels.last != idVal) {
                        currentModels.append(idVal)
                    }
                }
            }
        }
        if let p = currentProvider {
            result[p] = currentModels
        }
        return result
    }

    static func parseJSONProviders(_ data: Data) -> [String: [String]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: [String]] = [:]
        let providersDict: [String: Any]
        if let p = json["providers"] as? [String: Any] {
            providersDict = p
        } else if let p = json["provider"] as? [String: Any] {
            providersDict = p
        } else {
            providersDict = json
        }

        for (pKey, pVal) in providersDict {
            if pKey == "$schema" || pKey == "version" || pKey == "settings" || pKey == "enabled_providers" { continue }
            if let pObj = pVal as? [String: Any] {
                if let modelsDict = pObj["models"] as? [String: Any] {
                    result[pKey] = Array(modelsDict.keys).sorted()
                } else if let modelsArr = pObj["models"] as? [[String: Any]] {
                    let ids = modelsArr.compactMap { $0["id"] as? String ?? $0["name"] as? String }
                    result[pKey] = ids
                } else if let modelsArr = pObj["models"] as? [String] {
                    result[pKey] = modelsArr
                } else {
                    result[pKey] = []
                }
            } else if let modelsArr = pVal as? [[String: Any]] {
                let ids = modelsArr.compactMap { $0["id"] as? String ?? $0["name"] as? String }
                result[pKey] = ids
            } else if let modelsArr = pVal as? [String] {
                result[pKey] = modelsArr
            }
        }
        return result
    }

    /// Diffs previous and new model configurations (YAML or JSON) and returns
    /// granular phrases (e.g. "Added Mistral provider with 3 models", "Added 2 models to Heimdallm").
    static func modelConfigChanges(oldData: Data?, newData: Data, filename: String, fallback: String) -> [String] {
        let newProviders = parseModelProviders(from: newData, filename: filename)
        if newProviders.isEmpty {
            return [fallback]
        }
        guard let oldData = oldData else {
            var added: [String] = []
            for (p, models) in newProviders.sorted(by: { $0.key < $1.key }) {
                let name = displayName(for: p)
                if models.isEmpty {
                    added.append("\(name) added")
                } else {
                    let countStr = "\(models.count) \(models.count == 1 ? "model" : "models")"
                    added.append("\(name) added with \(countStr)")
                }
            }
            return added.isEmpty ? [fallback] : added
        }

        let oldProviders = parseModelProviders(from: oldData, filename: filename)
        if oldProviders == newProviders {
            return []
        }

        var changes: [String] = []
        let oldKeys = Set(oldProviders.keys)
        let newKeys = Set(newProviders.keys)

        for p in newKeys.subtracting(oldKeys).sorted() {
            let models = newProviders[p] ?? []
            let name = displayName(for: p)
            if models.isEmpty {
                changes.append("\(name) added")
            } else {
                let countStr = "\(models.count) \(models.count == 1 ? "model" : "models")"
                changes.append("\(name) added with \(countStr)")
            }
        }

        for p in oldKeys.subtracting(newKeys).sorted() {
            let name = displayName(for: p)
            changes.append("\(name) removed")
        }

        for p in oldKeys.intersection(newKeys).sorted() {
            let oldModels = Set(oldProviders[p] ?? [])
            let newModels = Set(newProviders[p] ?? [])
            let added = newModels.subtracting(oldModels)
            let removed = oldModels.subtracting(newModels)
            let name = displayName(for: p)

            if oldModels.isEmpty && !newModels.isEmpty {
                let countStr = "\(newModels.count) \(newModels.count == 1 ? "model" : "models")"
                changes.append("\(name) added with \(countStr)")
            } else if !added.isEmpty && removed.isEmpty {
                let countStr = "\(added.count) \(added.count == 1 ? "model" : "models")"
                changes.append("\(name) updated with \(countStr)")
            } else if !removed.isEmpty && added.isEmpty {
                let countStr = "\(removed.count) \(removed.count == 1 ? "model" : "models")"
                changes.append("\(countStr) removed from \(name)")
            } else if !added.isEmpty || !removed.isEmpty {
                changes.append("\(name) models updated")
            }
        }

        return changes.isEmpty ? [fallback] : changes
    }

    /// Formats elapsed time since a sync change event into human-readable relative time
    /// (e.g. "just now", "15 minutes ago", "2 hours ago", "yesterday").
    static func relativeTimeString(from date: Date, relativeTo now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 45 && elapsed >= -5 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
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

    /// Whether a change phrase represents a meaningful configuration event
    /// (provider/harness/settings edits) rather than routine data refresh.
    /// Routine changes — a balance ticking down, a regenerated widget snapshot
    /// — should not trigger the on-device model or bump "last synced".
    static func isMajor(_ change: String) -> Bool {
        let lowered = change.lowercased()
        // Balance-only churn and regenerated snapshots are routine.
        let routineMarkers = [
            "updated scriptable widget snapshot",
            "scriptable widget snapshot",
            "updated providers & models",
            "providers & models",
            "session"
        ]
        if routineMarkers.contains(where: { lowered.contains($0) }) { return false }
        // Everything else (added/removed/paused/resumed/updated a named config,
        // sessions, preferences, credentials) is a substantive change.
        return true
    }

    static func containsMajor(_ changes: [String]) -> Bool {
        changes.contains(where: { isMajor($0) })
    }

    /// Names and quantities that must survive an AFM rephrase: provider/harness names,
    /// config filenames, and model counts. A narrative that drops any of them is
    /// discarded in favour of the deterministic sentence, so specificity is never lost.
    static func specificTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        if let regex = try? NSRegularExpression(pattern: "[A-Za-z0-9_-]+\\.(?:yml|yaml|json|md)") {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                tokens.append(ns.substring(with: m.range))
            }
        }
        if let numRegex = try? NSRegularExpression(pattern: "\\b(\\d+)\\s+models?\\b", options: .caseInsensitive) {
            let ns = text as NSString
            for m in numRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                tokens.append(ns.substring(with: m.range(at: 1)))
            }
        }
        let leadVerbs: Set<String> = [
            "Added", "Updated", "Removed", "Paused", "Resumed", "Reconnected",
            "Uploaded", "No", "Everything", "Waiting", "The", "And", "Balances"
        ]
        for word in text.components(separatedBy: CharacterSet.alphanumerics.inverted) {
            guard word.count > 1, word.first?.isUppercase == true, !leadVerbs.contains(word) else { continue }
            tokens.append(word)
        }
        return tokens
    }

    /// True when every specific name from the original sentence is still
    /// present in the model's rephrasing.
    static func preservesSpecifics(_ original: String, in narrative: String) -> Bool {
        for token in specificTokens(original) where !narrative.localizedCaseInsensitiveContains(token) {
            return false
        }
        return true
    }

    /// Validates an AFM narrative against its deterministic source, ensuring
    /// no hallucinated phrases or dropped specifics.
    static func isValidNarrative(_ narrative: String, source: String) -> Bool {
        let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return false }
        let forbidden = ["using the harness", "the file names", "the provider updated", "session"]
        let lower = trimmed.lowercased()
        for f in forbidden {
            if lower.contains(f) { return false }
        }
        let sourceTokens = specificTokens(source)
        if sourceTokens.isEmpty { return false }
        return preservesSpecifics(source, in: trimmed)
    }
}
