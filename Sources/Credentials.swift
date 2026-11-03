import Foundation
import Security
import SQLite3
import CommonCrypto
import CryptoKit
import LocalAuthentication
import AppKit

enum ConnectorError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

enum KeychainVault {
    static let service = "app.apibar.APIBar.sessions"
    /// Test/CLI runs must never read, write, or delete the user's real saved
    /// sessions. Setting `APIBAR_VAULT_DIR` redirects storage to a scratch
    /// directory and disables every Keychain operation.
    static let isEphemeral = (ProcessInfo.processInfo.environment["APIBAR_VAULT_DIR"]?.isEmpty == false)
    static let vaultDir: URL = {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_VAULT_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("APIBar/vault")
    }()
    // Brave and local sessions use the macOS file-based keychain. Its legacy
    // ACL dialogs also need an explicit interaction policy. Serialize calls so
    // an interactive Connect cannot accidentally enable a background prompt.
    private static let accessLock = NSLock()
    static func access<T>(interactive: Bool = false, _ operation: () throws -> T) throws -> T {
        accessLock.lock()
        defer { accessLock.unlock() }
        var previous = DarwinBoolean(false)
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(interactive) == errSecSuccess else {
            throw ConnectorError.message("Could not apply the Keychain interaction policy.")
        }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }
    static func load(_ account: String) throws -> Data? {
        let file = vaultDir.appendingPathComponent("\(account).dat")
        if let data = try? Data(contentsOf: file), !data.isEmpty {
            return data
        }
        if isEphemeral { return nil }
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        let status = try access { SecItemCopyMatching(query as CFDictionary, &item) }
        if status == errSecItemNotFound || status == errSecAuthFailed || status == -25293 { return nil }
        if status == errSecSuccess, let bytes = item as? Data {
            try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
            try? bytes.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return bytes
        }
        guard status == errSecSuccess, let bytes = item as? Data else { throw ConnectorError.message("Saved session needs approval. Use Connect in Settings (Keychain \(status)).") }
        return bytes
    }
    static func save(_ data: Data, account: String, interactive: Bool = false) throws {
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let file = vaultDir.appendingPathComponent("\(account).dat")
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        if isEphemeral { return }

        let context = LAContext(); context.interactionNotAllowed = !interactive
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecUseAuthenticationContext as String: context]
        try? access(interactive:interactive) {
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound || status == errSecAuthFailed || status == -25293 {
                if status == errSecAuthFailed || status == -25293 {
                    _ = SecItemDelete(query as CFDictionary)
                }
                var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                _ = SecItemAdd(add as CFDictionary, nil)
            }
        }
    }
    static func clear(_ account: String) {
        let file = vaultDir.appendingPathComponent("\(account).dat")
        try? FileManager.default.removeItem(at: file)
        if isEphemeral { return }
        _ = try? access { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary) }
    }
}

struct StoredCookie: Codable, Sendable {
    let name: String
    var value: String
    let domain: String
    var expires: Date?
}

enum ProfileBookmark {
    static func create(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    static func resolve(_ data: Data, stale: inout Bool) throws -> URL {
        try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

struct BraveProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL

    var displayName: String {
        if name != id && !name.isEmpty {
            return "\(name) (\(id))"
        }
        return name
    }
}

enum BraveSessionImporter {
    static let rootBookmarkKey = "BraveRootBookmark"
    static let profileBookmarkKey = "BraveProfileBookmark"
    static let defaultBrowserRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")
    static let accessError = "macOS blocked access to Brave's profile files. In Settings, click 'Choose Brave Profile…' to grant folder access (or grant Full Disk Access in macOS System Settings)."

    static func resolvedBrowserRoot() -> (url: URL, accessing: Bool) {
        if let bookmark = UserDefaults.standard.data(forKey: rootBookmarkKey) {
            var stale = false
            if let url = try? ProfileBookmark.resolve(bookmark, stale: &stale) {
                let accessing = url.startAccessingSecurityScopedResource()
                return (url, accessing)
            }
        }
        if let path = UserDefaults.standard.string(forKey: "BraveBrowserRootPath") {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return (url, false)
            }
        }
        return (defaultBrowserRoot, false)
    }

    static func isBraveInstalled() -> Bool {
        if FileManager.default.fileExists(atPath: "/Applications/Brave Browser.app") {
            return true
        }
        let userApp = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Brave Browser.app")
        if FileManager.default.fileExists(atPath: userApp.path) {
            return true
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.brave.Browser") != nil {
            return true
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: defaultBrowserRoot.path, isDirectory: &isDir) && isDir.boolValue {
            return true
        }
        return false
    }

    static func isAccessBlocked() -> Bool {
        let (root, accessing) = resolvedBrowserRoot()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) || !isDir.boolValue {
            return false
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: root.path)
            return false
        } catch {
            return true
        }
    }

    static func availableProfiles() -> [BraveProfile] {
        let (root, accessing) = resolvedBrowserRoot()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }

        var profiles: [BraveProfile] = []
        var foundDirNames = Set<String>()

        var namesByFolder: [String: String] = [:]
        let localStateURL = root.appendingPathComponent("Local State")
        if let data = try? Data(contentsOf: localStateURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let profileObj = json["profile"] as? [String: Any],
           let infoCache = profileObj["info_cache"] as? [String: Any] {
            for (key, val) in infoCache {
                if let dict = val as? [String: Any], let name = dict["name"] as? String, !name.isEmpty {
                    namesByFolder[key] = name
                }
            }
        }

        if let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path) {
            let matches = (["Default"] + entries.filter { $0.hasPrefix("Profile ") }.sorted())
            for match in matches {
                let url = root.appendingPathComponent(match)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if !foundDirNames.contains(match) {
                        foundDirNames.insert(match)
                        let displayName = namesByFolder[match] ?? match
                        profiles.append(BraveProfile(id: match, name: displayName, url: url))
                    }
                }
            }
        }

        if let bookmark = UserDefaults.standard.data(forKey: profileBookmarkKey) {
            var stale = false
            if let profileURL = try? ProfileBookmark.resolve(bookmark, stale: &stale) {
                let match = profileURL.lastPathComponent
                if !foundDirNames.contains(match) {
                    foundDirNames.insert(match)
                    let displayName = namesByFolder[match] ?? match
                    profiles.append(BraveProfile(id: match, name: displayName, url: profileURL))
                }
            }
        }

        let candidates = ["Default"] + (1...20).map { "Profile \($0)" }
        for cand in candidates {
            if !foundDirNames.contains(cand) {
                let url = root.appendingPathComponent(cand)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    foundDirNames.insert(cand)
                    let displayName = namesByFolder[cand] ?? cand
                    profiles.append(BraveProfile(id: cand, name: displayName, url: url))
                }
            }
        }

        if profiles.isEmpty {
            let defaultURL = root.appendingPathComponent("Default")
            profiles.append(BraveProfile(id: "Default", name: "Default", url: defaultURL))
        }

        return profiles
    }

    static func rememberProfile(_ url: URL) throws {
        let chosen = url.standardizedFileURL

        // 1. If user selected Brave-Browser folder or any folder containing Local State:
        if chosen.lastPathComponent == "Brave-Browser" || FileManager.default.fileExists(atPath: chosen.appendingPathComponent("Local State").path) {
            let rootBookmark = try ProfileBookmark.create(chosen)
            UserDefaults.standard.set(rootBookmark, forKey: rootBookmarkKey)
            UserDefaults.standard.set(chosen.path, forKey: "BraveBrowserRootPath")

            let defaultProfile = chosen.appendingPathComponent("Default")
            if let profBm = try? ProfileBookmark.create(defaultProfile) {
                UserDefaults.standard.set(profBm, forKey: profileBookmarkKey)
            }
            UserDefaults.standard.set(defaultProfile.path, forKey: "BraveProfilePath")
            return
        }

        // 2. If user selected Default or Profile folder:
        if chosen.lastPathComponent == "Default" || chosen.lastPathComponent.hasPrefix("Profile ") ||
           FileManager.default.fileExists(atPath: chosen.appendingPathComponent("Network/Cookies").path) ||
           FileManager.default.fileExists(atPath: chosen.appendingPathComponent("Cookies").path) {
            let bookmark = try ProfileBookmark.create(chosen)
            UserDefaults.standard.set(bookmark, forKey: profileBookmarkKey)
            UserDefaults.standard.set(chosen.path, forKey: "BraveProfilePath")

            let parent = chosen.deletingLastPathComponent()
            if parent.lastPathComponent == "Brave-Browser" || FileManager.default.fileExists(atPath: parent.appendingPathComponent("Local State").path) {
                if let rootBm = try? ProfileBookmark.create(parent) {
                    UserDefaults.standard.set(rootBm, forKey: rootBookmarkKey)
                    UserDefaults.standard.set(parent.path, forKey: "BraveBrowserRootPath")
                }
            }
            return
        }

        throw ConnectorError.message("Please select the 'Brave-Browser' folder or a profile folder (e.g. 'Default').")
    }

    static func read(provider: String, cookieDomain: String? = nil, interactive: Bool = false) throws -> [StoredCookie] {
        let names: Set<String>
        let domains: String
        switch provider {
        case "crowbot":
            names = ["crowbot_key"]
            domains = "('chat.crowbot.sh','.chat.crowbot.sh')"
        case "fireworks":
            names = ["auth_v2_access_token", "auth_v2_id_token", "auth_v2_refresh_token", "auth_v2_user_context"]
            domains = "('app.fireworks.ai','.app.fireworks.ai','.fireworks.ai','fireworks.ai')"
        case "vertex", "aistudio":
            names = ["SID", "SIDCC", "HSID", "SSID", "APISID", "SAPISID", "OSID", "__Secure-OSID", "__Secure-1PSID", "__Secure-3PSID", "__Secure-1PAPISID", "__Secure-3PAPISID", "__Secure-1PSIDTS", "__Secure-3PSIDTS", "__Secure-1PSIDCC", "__Secure-3PSIDCC"]
            domains = "('.google.com','google.com','console.cloud.google.com','.console.cloud.google.com','.cloud.google.com','cloud.google.com','aistudio.google.com','.aistudio.google.com')"
        case "cerebras":
            names = []
            domains = "('.cerebras.ai','cerebras.ai','cloud.cerebras.ai','.cloud.cerebras.ai','auth.cerebras.ai','.auth.cerebras.ai','api.cerebras.ai','.api.cerebras.ai')"
        case "refuseless":
            names = []
            domains = "('.refuseless.com','refuseless.com','api.refuseless.com','.api.refuseless.com','console.refuseless.com','.console.refuseless.com')"
        default:
            if let domain = cookieDomain, !domain.isEmpty {
                let clean = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                names = []
                domains = "('.\(clean)','\(clean)')"
            } else {
                throw ConnectorError.message("Unknown provider.")
            }
        }
        let (rootURL, rootAccessing) = resolvedBrowserRoot()
        defer { if rootAccessing { rootURL.stopAccessingSecurityScopedResource() } }

        var selectedProfile: URL?
        if let bookmark = UserDefaults.standard.data(forKey: profileBookmarkKey) {
            var stale = false
            selectedProfile = try? ProfileBookmark.resolve(bookmark, stale: &stale)
            if let p = selectedProfile, stale {
                if let fresh = try? ProfileBookmark.create(p) {
                    UserDefaults.standard.set(fresh, forKey: profileBookmarkKey)
                }
            }
            if let p = selectedProfile {
                UserDefaults.standard.set(p.path, forKey: "BraveProfilePath")
            }
        }
        if selectedProfile == nil, let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let u = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: u.path) {
                selectedProfile = u
            }
        }
        let accessing = selectedProfile?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { selectedProfile?.stopAccessingSecurityScopedResource() } }
        let profiles: [URL]
        if let selectedProfile { profiles = [selectedProfile] }
        else {
            let available = availableProfiles()
            if !available.isEmpty {
                profiles = available.map(\.url)
            } else {
                throw ConnectorError.message(accessError)
            }
        }
        var encryptedRows: [(String,String,Data,String,Double)] = []
        var version = 0
        var readableDatabases = 0
        var blockedDatabases = 0
        // Read one matching profile only; never merge identities from separate profiles.
        for profile in profiles {
            for suffix in ["Network/Cookies", "Cookies"] {
                let cookieFile = profile.appendingPathComponent(suffix)
                do { _ = try cookieFile.resourceValues(forKeys: [.isRegularFileKey]) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
                catch { blockedDatabases += 1; continue }
                let path = cookieFile.path
                var db: OpaquePointer?
                var opened = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
                var tempDirURL: URL? = nil
                if opened != SQLITE_OK {
                    if db != nil { sqlite3_close(db); db = nil }
                    // Fall back to copying to a temporary file if Brave has an exclusive lock
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    if (try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)) != nil {
                        let tempFile = tempDir.appendingPathComponent("Cookies")
                        if (try? FileManager.default.copyItem(at: cookieFile, to: tempFile)) != nil {
                            let wal = cookieFile.deletingLastPathComponent().appendingPathComponent("\(cookieFile.lastPathComponent)-wal")
                            if FileManager.default.fileExists(atPath: wal.path) {
                                _ = try? FileManager.default.copyItem(at: wal, to: tempDir.appendingPathComponent("Cookies-wal"))
                            }
                            tempDirURL = tempDir
                            opened = sqlite3_open_v2(tempFile.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
                        }
                    }
                }
                defer {
                    if let db { sqlite3_close(db) }
                    if let tempDirURL { try? FileManager.default.removeItem(at: tempDirURL) }
                }
                guard opened == SQLITE_OK, let db else {
                    blockedDatabases += 1
                    continue
                }
                sqlite3_busy_timeout(db, 3000)
                var q: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &q, nil) == SQLITE_OK, sqlite3_step(q) == SQLITE_ROW, let text = sqlite3_column_text(q, 0) { version = Int(String(cString: text)) ?? 0 }
                sqlite3_finalize(q); q = nil
                let sql: String
                if provider == "cerebras" {
                    sql = "SELECT host_key,name,encrypted_value,value,expires_utc FROM cookies WHERE host_key LIKE '%cerebras.ai'"
                } else if provider == "refuseless" {
                    sql = "SELECT host_key,name,encrypted_value,value,expires_utc FROM cookies WHERE host_key LIKE '%refuseless.com'"
                } else {
                    sql = "SELECT host_key,name,encrypted_value,value,expires_utc FROM cookies WHERE host_key IN \(domains)"
                }
                guard sqlite3_prepare_v2(db, sql, -1, &q, nil) == SQLITE_OK else {
                    sqlite3_finalize(q)
                    throw ConnectorError.message("Brave's cookie database could not be read. Close Brave and retry, or choose the correct profile in Settings.")
                }
                readableDatabases += 1
                var step = sqlite3_step(q)
                while step == SQLITE_ROW {
                        defer { step = sqlite3_step(q) }
                        guard let host = sqlite3_column_text(q,0), let name = sqlite3_column_text(q,1) else { continue }
                        let cookieName = String(cString:name)
                        guard names.isEmpty || names.contains(cookieName) else { continue }
                        let count = Int(sqlite3_column_bytes(q,2))
                        let blob = sqlite3_column_blob(q,2).map { Data(bytes:$0,count:count) } ?? Data()
                        let value = sqlite3_column_text(q,3).map { String(cString:$0) } ?? ""
                        encryptedRows.append((String(cString:host),cookieName,blob,value,sqlite3_column_double(q,4)))
                }
                sqlite3_finalize(q)
                guard step == SQLITE_DONE else { throw ConnectorError.message("Brave's cookie database is busy or unreadable. Close Brave and try again.") }
                if !encryptedRows.isEmpty { break }
            }
            if !encryptedRows.isEmpty { break }
        }
        guard readableDatabases > 0 || blockedDatabases == 0 else { throw ConnectorError.message(accessError) }
        guard !encryptedRows.isEmpty else {
            let name = provider == "crowbot" ? "Crowbot" : provider == "fireworks" ? "Fireworks" : provider == "aistudio" ? "Google AI Studio" : provider == "cerebras" ? "Cerebras" : provider == "refuseless" ? "Refuseless" : "Google Cloud"
            throw ConnectorError.message("No signed-in \(name) session was found in Brave. Sign in there, then connect again.")
        }
        // Keychain is queried only after confirming this provider has stored cookies.
        let password = try safeStoragePassword(interactive: interactive)
        guard let key = deriveSafeStorageKey(from: password) else { throw ConnectorError.message("Could not unlock Brave's saved session.") }
        do {
            return try decryptCookieRows(encryptedRows, version: version, key: key)
        } catch {
            cachedPassword = nil
            KeychainVault.clear("brave_safe_storage_key")
            if interactive {
                if let freshPassword = try? safeStoragePassword(interactive: true, forceFresh: true),
                   let freshKey = deriveSafeStorageKey(from: freshPassword),
                   let cookies = try? decryptCookieRows(encryptedRows, version: version, key: freshKey) {
                    return cookies
                }
            }
            throw error
        }
    }

    private static func deriveSafeStorageKey(from password: Data) -> [UInt8]? {
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: 16)
        let result = password.withUnsafeBytes { raw in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), raw.bindMemory(to: CChar.self).baseAddress, password.count, s.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }}
        return result == kCCSuccess ? key : nil
    }

    private static func decryptCookieRows(_ rows: [(String, String, Data, String, Double)], version: Int, key: [UInt8]) throws -> [StoredCookie] {
        return try rows.map { host, name, blob, plain, expiry in
            let value: String
            if !plain.isEmpty { value = plain }
            else {
                guard blob.starts(with: Data("v10".utf8)) else { throw ConnectorError.message("This Brave cookie encryption format is not supported.") }
                let input = Data(blob.dropFirst(3)), iv = [UInt8](repeating: 32, count: 16)
                var output = [UInt8](repeating: 0, count: input.count + 16), moved = 0
                let capacity = output.count
                let status = key.withUnsafeBytes { k in iv.withUnsafeBytes { v in input.withUnsafeBytes { raw in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, key.count, v.baseAddress, raw.baseAddress, input.count, &output, capacity, &moved)
                }}}
                guard status == kCCSuccess else { throw ConnectorError.message("Brave session decryption failed. No credentials were imported.") }
                var decrypted = Data(output.prefix(moved))
                if version >= 24 && decrypted.count > 32 {
                    let digestHost = Data(SHA256.hash(data: Data(host.utf8)))
                    let cleanHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    let digestClean = Data(SHA256.hash(data: Data(cleanHost.utf8)))
                    let digestDotted = Data(SHA256.hash(data: Data(("." + cleanHost).utf8)))

                    if decrypted.starts(with: digestHost) || decrypted.starts(with: digestClean) || decrypted.starts(with: digestDotted) {
                        decrypted = decrypted.dropFirst(32)
                    } else if String(data: decrypted, encoding: .utf8) == nil {
                        throw ConnectorError.message("The saved cookie did not match its provider domain.")
                    }
                }
                guard let string = String(data: decrypted, encoding: .utf8), !string.isEmpty else { throw ConnectorError.message("The saved session could not be decoded.") }
                value = string
            }
            return StoredCookie(name: name, value: value, domain: host, expires: expiry > 0 ? Date(timeIntervalSince1970: expiry / 1_000_000 - 11_644_473_600) : nil)
        }
    }
    private static nonisolated(unsafe) var cachedPassword: Data?
    static func discoverGoogleBillingAccount() -> String? {
        let (root, accessingRoot) = resolvedBrowserRoot()
        defer { if accessingRoot { root.stopAccessingSecurityScopedResource() } }

        var selectedProfile: URL?
        if let bookmark = UserDefaults.standard.data(forKey: profileBookmarkKey) {
            var stale = false
            selectedProfile = try? ProfileBookmark.resolve(bookmark, stale: &stale)
        }
        if selectedProfile == nil, let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let u = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: u.path) { selectedProfile = u }
        }
        let profiles: [URL]
        if let selectedProfile { profiles = [selectedProfile] }
        else { profiles = availableProfiles().map(\.url) }

        let pattern = #"([0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        for profile in profiles {
            let accessing = profile.startAccessingSecurityScopedResource()
            defer { if accessing { profile.stopAccessingSecurityScopedResource() } }

            let historyFile = profile.appendingPathComponent("History")
            guard FileManager.default.fileExists(atPath: historyFile.path) else { continue }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("APIBarHistory-" + UUID().uuidString)
            guard (try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)) != nil else { continue }
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let tempHistory = tempDir.appendingPathComponent("History")
            guard (try? FileManager.default.copyItem(at: historyFile, to: tempHistory)) != nil else { continue }
            let wal = profile.appendingPathComponent("History-wal")
            if FileManager.default.fileExists(atPath: wal.path) {
                _ = try? FileManager.default.copyItem(at: wal, to: tempDir.appendingPathComponent("History-wal"))
            }

            var db: OpaquePointer?
            guard sqlite3_open_v2(tempHistory.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let database = db else {
                continue
            }
            defer { sqlite3_close(database) }

            let query = "SELECT url FROM urls WHERE url LIKE '%console.cloud.google.com/billing/%' ORDER BY last_visit_time DESC LIMIT 50;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(stmt, 0) {
                        let urlStr = String(cString: cStr)
                        if let match = regex.firstMatch(in: urlStr, range: NSRange(urlStr.startIndex..., in: urlStr)),
                           let r = Range(match.range(at: 1), in: urlStr) {
                            return String(urlStr[r]).uppercased()
                        }
                    }
                }
            }
        }
        return nil
    }

    static func discoverGoogleAIStudioProjectID() -> String? {
        let (root, accessingRoot) = resolvedBrowserRoot()
        defer { if accessingRoot { root.stopAccessingSecurityScopedResource() } }

        var selectedProfile: URL?
        if let bookmark = UserDefaults.standard.data(forKey: profileBookmarkKey) {
            var stale = false
            selectedProfile = try? ProfileBookmark.resolve(bookmark, stale: &stale)
        }
        if selectedProfile == nil, let path = UserDefaults.standard.string(forKey: "BraveProfilePath") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) { selectedProfile = url }
        }
        let profiles = selectedProfile.map { [$0] } ?? availableProfiles().map(\.url)
        let projectPattern = #"^gen-lang-client-[A-Za-z0-9_-]+$"#
        guard let projectRegex = try? NSRegularExpression(pattern: projectPattern) else { return nil }

        for profile in profiles {
            let accessing = profile.startAccessingSecurityScopedResource()
            defer { if accessing { profile.stopAccessingSecurityScopedResource() } }

            let historyFile = profile.appendingPathComponent("History")
            guard FileManager.default.fileExists(atPath: historyFile.path) else { continue }
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("APIBarHistory-" + UUID().uuidString)
            guard (try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)) != nil else { continue }
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let tempHistory = tempDir.appendingPathComponent("History")
            guard (try? FileManager.default.copyItem(at: historyFile, to: tempHistory)) != nil else { continue }
            let wal = profile.appendingPathComponent("History-wal")
            if FileManager.default.fileExists(atPath: wal.path) {
                _ = try? FileManager.default.copyItem(at: wal, to: tempDir.appendingPathComponent("History-wal"))
            }

            var db: OpaquePointer?
            guard sqlite3_open_v2(tempHistory.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let database = db else { continue }
            defer { sqlite3_close(database) }

            let query = "SELECT url FROM urls WHERE url LIKE '%aistudio.google.com/spend%' ORDER BY last_visit_time DESC LIMIT 100;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(stmt, 0) else { continue }
                let value = String(cString: cString)
                guard let components = URLComponents(string: value),
                      components.host == "aistudio.google.com", components.path == "/spend",
                      let project = components.queryItems?.first(where: { $0.name == "project" })?.value,
                      projectRegex.firstMatch(in: project, range: NSRange(project.startIndex..., in: project)) != nil else { continue }
                return project
            }
        }
        return nil
    }

    private static func safeStoragePassword(interactive: Bool, forceFresh: Bool = false) throws -> Data {
        if !forceFresh {
            if let cachedPassword { return cachedPassword }
            if let stored = try? KeychainVault.load("brave_safe_storage_key"), !stored.isEmpty {
                cachedPassword = stored
                return stored
            }
        }
        let context = LAContext(); context.interactionNotAllowed = !interactive
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"Brave Safe Storage",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationContext as String:context]
        var item: CFTypeRef?
        let status = try KeychainVault.access(interactive:interactive) { SecItemCopyMatching(query as CFDictionary,&item) }
        guard status == errSecSuccess, let value = item as? Data else { throw ConnectorError.message("Brave Safe Storage access was not granted (\(status)). Your session was not imported.") }
        cachedPassword = value
        try? KeychainVault.save(value, account: "brave_safe_storage_key", interactive: interactive)
        return value
    }
}
