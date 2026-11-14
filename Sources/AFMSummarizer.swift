import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps the on-device Apple Foundation Model for phrasing sync summaries.
///
/// The deterministic sentence from `SyncChangeLog` is always the source of
/// truth: AFM only re-phrases it, and any failure (framework missing, model
/// unavailable, timeout, empty output) falls back to that sentence. The app
/// must never block or degrade because a language model is slow or absent.
///
/// Measured on an M-series Mac at macOS 27: 1.9 s cold, 330-375 ms warm.
enum AFMSummarizer {
    /// Hard ceiling for a rephrase. Beyond this the deterministic text wins,
    /// so a stalled model can never hold up a sync cycle.
    static let timeout: Duration = .milliseconds(2500)

    /// Whether the on-device model can be used on this machine.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Re-phrases `fallback` using the on-device model, returning `fallback`
    /// unchanged when the model is unavailable, times out, or returns nothing
    /// useful. Never throws: callers always get a displayable string.
    static func rephrase(_ fallback: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await withTimeout(fallback)
        }
        #endif
        return fallback
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func withTimeout(_ fallback: String) async -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return fallback }

        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession()
                let prompt = """
                Rewrite this sync summary as one short past-tense sentence. \
                Do not add filler words. You MUST keep every specific name \
                (provider, model count, and file names) exactly as written. \
                Do not generalize or drop details. No preamble, no quotes:
                \(fallback)
                """
                guard let response = try? await session.respond(to: prompt) else { return nil }
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                // Reject empty or runaway output rather than showing it.
                guard !text.isEmpty, text.count <= 200 else { return nil }
                return text
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? fallback
        }
    }
    #endif
}
