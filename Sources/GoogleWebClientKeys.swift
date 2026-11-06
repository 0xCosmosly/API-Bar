import Foundation

/// Public "consumer" keys that Google ships inside its own web front ends.
///
/// These are **not** user credentials and not secrets: every visitor to
/// console.cloud.google.com and aistudio.google.com receives the same values, they
/// identify the browser client rather than an account, and they grant no billing or
/// data access on their own. Account access still comes from the user's own session
/// cookies, which never leave the macOS Keychain.
///
/// They are centralised here (rather than inline at the call sites) so a release
/// audit can see exactly which third-party identifiers the app ships, and so they
/// can be overridden without a rebuild if Google rotates them.
enum GoogleWebClientKeys {
    /// cloudconsole-pa.clients6.google.com billing GraphQL client.
    static let cloudConsole = "AIzaSyCI-zsRP85UVOi0DjtiCwWBwQ1djDy741g"
    /// aistudio.google.com gRPC-web client.
    static let aiStudio = "AIzaSyDdP816MREB3SkjZO04QXbjsigfcI0GWOs"

    static let cloudConsoleDefaultsKey = "GoogleConsumerKey"
    static let aiStudioDefaultsKey = "GoogleAIStudioKey"

    static func resolvedCloudConsole() -> String {
        let override = UserDefaults.standard.string(forKey: cloudConsoleDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? cloudConsole : override
    }

    static func resolvedAIStudio() -> String {
        let override = UserDefaults.standard.string(forKey: aiStudioDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? aiStudio : override
    }
}
