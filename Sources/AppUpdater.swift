import Foundation
import AppKit
import SwiftUI

public enum InstallStage: String, Equatable, Codable, Sendable {
    case downloading = "downloading"
    case extracting = "extracting"
    case replacingBundle = "replacingBundle"
    case relaunching = "relaunching"
    case failed = "failed"

    public var displayLabel: String {
        switch self {
        case .downloading: return "Downloading update from GitHub…"
        case .extracting: return "Extracting update archive…"
        case .replacingBundle: return "Replacing application bundle…"
        case .relaunching: return "Relaunching API Bar…"
        case .failed: return "Installation failed."
        }
    }
}

public enum UpdaterState: Equatable, Sendable {
    case idle(lastChecked: Date?)
    case checking(manual: Bool)
    case available(version: String, title: String, notes: String, releaseURL: URL?, downloadURL: URL?, assetUpdatedAt: Date?, isRebuild: Bool)
    case upToDate(version: String, checkedAt: Date)
    case installing(stage: InstallStage)
    case failed(message: String)

    public var telemetryName: String {
        switch self {
        case .idle: return "idle"
        case .checking: return "checking"
        case .available: return "available"
        case .upToDate: return "upToDate"
        case .installing: return "installing"
        case .failed: return "failed"
        }
    }
}

@MainActor
public final class AppUpdater: ObservableObject {
    public static let shared = AppUpdater()

    public static let repoOwner = "0xCosmosly"
    public static let repoName = "API-Bar"
    public static let latestReleaseEndpoint = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    public static let fallbackFeedEndpoint = "https://github.com/\(repoOwner)/\(repoName)/releases.atom"
    public static let latestHtmlEndpoint = "https://github.com/\(repoOwner)/\(repoName)/releases/latest"

    @Published public private(set) var state: UpdaterState = .idle(lastChecked: nil)
    @Published public var isChecking: Bool = false
    @Published public var updateAvailable: Bool = false
    @Published public var latestVersion: String? = nil
    @Published public var releaseTitle: String? = nil
    @Published public var releaseNotes: String? = nil
    @Published public var releaseURL: URL? = nil
    @Published public var downloadURL: URL? = nil
    @Published public var assetUpdatedAt: Date? = nil
    @Published public var checkError: String? = nil

    public func transition(to newState: UpdaterState) {
        self.state = newState
        switch newState {
        case .idle(let date):
            self.isChecking = false
            self.isInstalling = false
            if let date { self.lastCheckedDate = date }
        case .checking(let manual):
            self.isChecking = true
            self.checkError = nil
            if manual { self.statusMessage = "Checking for updates…" }
        case .available(let ver, let title, let notes, let relURL, let dlURL, let assetDate, let isRebuild):
            self.isChecking = false
            self.isInstalling = false
            self.updateAvailable = true
            self.latestVersion = ver
            self.releaseTitle = title
            self.releaseNotes = notes
            self.releaseURL = relURL
            self.downloadURL = dlURL
            self.assetUpdatedAt = assetDate
            self.checkError = nil
            self.statusMessage = isRebuild ? "Updated build available: v\(ver)" : "Update available: v\(ver)"
        case .upToDate(let ver, let date):
            self.isChecking = false
            self.isInstalling = false
            self.updateAvailable = false
            self.latestVersion = ver
            self.checkError = nil
            self.lastCheckedDate = date
            self.statusMessage = "Up to date (v\(ver))."
        case .installing(let stage):
            self.isChecking = false
            self.isInstalling = true
            self.installStatusText = stage.displayLabel
        case .failed(let message):
            self.isChecking = false
            self.isInstalling = false
            self.checkError = message
            self.statusMessage = message
        }
    }

    public var telemetryRepresentation: [String: Any] {
        var dict: [String: Any] = [
            "state": state.telemetryName,
            "currentVersion": currentVersion,
            "isChecking": isChecking,
            "updateAvailable": updateAvailable,
            "isInstalling": isInstalling
        ]
        if let latestVersion { dict["latestVersion"] = latestVersion }
        if let checkError { dict["checkError"] = checkError }
        if !installStatusText.isEmpty { dict["installStatusText"] = installStatusText }
        if !statusMessage.isEmpty { dict["statusMessage"] = statusMessage }
        if let lastCheckedDate { dict["lastChecked"] = lastCheckedDate.timeIntervalSince1970 }
        return dict
    }

    /// Test seam: point the release lookup at a fixture server so the update
    /// decision can be verified without publishing a release. Unset in normal runs.
    public static var releaseEndpointOverride: URL? {
        // Read through getenv so a test can change it at runtime; ProcessInfo
        // snapshots the environment at launch. A bare path is treated as a local
        // fixture file.
        guard let raw = getenv("APIBAR_UPDATER_ENDPOINT") else { return nil }
        let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.contains("://"), let url = URL(string: value) { return url }
        return URL(fileURLWithPath: value)
    }

    @Published public var isInstalling: Bool = false
    @Published public var installStatusText: String = ""
    @Published public var statusMessage: String = ""

    private var updateWindow: NSWindow?
    private var lastCheckedDate: Date?

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.5.10"
    }

    public var isSemverNewerAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.isVersion(latest, newerThan: currentVersion)
    }

    public static var localBuildDate: Date {
        if let execPath = Bundle.main.executablePath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: execPath),
           let date = attrs[.modificationDate] as? Date {
            return date
        }
        if let bundlePath = Bundle.main.bundlePath as String?,
           let attrs = try? FileManager.default.attributesOfItem(atPath: bundlePath),
           let date = attrs[.modificationDate] as? Date {
            return date
        }
        return .distantPast
    }

    public struct ReleaseInfo {
        public let version: String
        public let title: String
        public let notes: String
        public let releaseURL: URL?
        public let downloadURL: URL?
        public let assetUpdatedAt: Date?
    }

    public init() {}

    /// Parses a GitHub release payload. Shared by the live path and the offline
    /// fixture path so both are verified by the same rules.
    static func releaseInfo(from json: [String: Any]) -> ReleaseInfo? {
        guard let tagName = json["tag_name"] as? String, !tagName.isEmpty else { return nil }
        let releaseVer = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard !releaseVer.isEmpty else { return nil }
        let title = json["name"] as? String ?? "API Bar v\(releaseVer)"
        let notes = json["body"] as? String ?? "No release notes provided."
        let htmlUrlStr = json["html_url"] as? String
        let releaseHtmlURL = htmlUrlStr.flatMap { URL(string: $0) }

        var zipURL: URL? = nil
        var assetUpdatedAt: Date? = nil
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String, name.hasSuffix(".zip"),
                      let download = asset["browser_download_url"] as? String,
                      let assetURL = URL(string: download) else { continue }
                zipURL = assetURL
                if let updatedStr = asset["updated_at"] as? String {
                    assetUpdatedAt = ISO8601DateFormatter().date(from: updatedStr)
                }
                break
            }
        }
        return ReleaseInfo(
            version: releaseVer,
            title: title,
            notes: notes,
            releaseURL: releaseHtmlURL,
            downloadURL: zipURL ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/\(tagName)/APIBar-app.zip"),
            assetUpdatedAt: assetUpdatedAt
        )
    }

    public func fetchReleaseInfo() async throws -> ReleaseInfo {
        // Strategy 1: Try GitHub REST API
        let override = Self.releaseEndpointOverride
        // A local fixture is read straight from disk; URLSession cannot load file URLs.
        if let override, override.isFileURL {
            let data = try Data(contentsOf: override)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = Self.releaseInfo(from: json) else {
                throw ConnectorError.message("The update fixture at \(override.path) is not a release payload.")
            }
            return info
        }
        if let apiURL = override ?? URL(string: Self.latestReleaseEndpoint) {
            var req = URLRequest(url: apiURL)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            req.setValue("APIBar-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 8

            if let (data, response) = try? await URLSession.shared.data(for: req),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let info = Self.releaseInfo(from: json) {
                return info
            }
        }

        // Strategy 2: GitHub Releases Atom Feed (resilient to GitHub REST API 403 rate limits).
        // A fixture endpoint that fails must not silently fall through to the live feed.
        if override == nil, let feedURL = URL(string: Self.fallbackFeedEndpoint) {
            var req = URLRequest(url: feedURL)
            req.setValue("application/atom+xml, text/xml", forHTTPHeaderField: "Accept")
            req.setValue("APIBar-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 8

            if let (data, response) = try? await URLSession.shared.data(for: req),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let text = String(data: data, encoding: .utf8),
               let entryStart = text.range(of: "<entry>"),
               let entryEnd = text.range(of: "</entry>", range: entryStart.upperBound..<text.endIndex) {
                let entryText = String(text[entryStart.upperBound..<entryEnd.lowerBound])

                if let tagRange = entryText.range(of: #"releases/tag/([^"'\s]+)"#, options: .regularExpression) {
                    let matchedTagUrl = String(entryText[tagRange])
                    let tag = matchedTagUrl.components(separatedBy: "/").last ?? ""
                    if !tag.isEmpty {
                        var title = "API Bar \(tag)"
                        if let titleStart = entryText.range(of: "<title>"),
                           let titleEnd = entryText.range(of: "</title>", range: titleStart.upperBound..<entryText.endIndex) {
                            title = String(entryText[titleStart.upperBound..<titleEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }

                        var notes = ""
                        if let contentStart = entryText.range(of: #"<content[^>]*>"#, options: .regularExpression),
                           let contentEnd = entryText.range(of: "</content>", range: contentStart.upperBound..<entryText.endIndex) {
                            let rawContent = String(entryText[contentStart.upperBound..<contentEnd.lowerBound])
                            notes = rawContent
                                .replacingOccurrences(of: "&lt;", with: "<")
                                .replacingOccurrences(of: "&gt;", with: ">")
                                .replacingOccurrences(of: "&amp;", with: "&")
                                .replacingOccurrences(of: "&quot;", with: "\"")
                                .replacingOccurrences(of: "&#39;", with: "'")
                                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }

                        var assetUpdatedAt: Date? = nil
                        if let updatedStart = entryText.range(of: "<updated>"),
                           let updatedEnd = entryText.range(of: "</updated>", range: updatedStart.upperBound..<entryText.endIndex) {
                            let dateStr = String(entryText[updatedStart.upperBound..<updatedEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            assetUpdatedAt = ISO8601DateFormatter().date(from: dateStr)
                        }

                        let cleanVer = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                        let htmlURL = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/tag/\(tag)")
                        let downloadURL = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/\(tag)/APIBar-app.zip")
                        return ReleaseInfo(
                            version: cleanVer,
                            title: title,
                            notes: notes.isEmpty ? "No release notes provided." : notes,
                            releaseURL: htmlURL,
                            downloadURL: downloadURL,
                            assetUpdatedAt: assetUpdatedAt
                        )
                    }
                }
            }
        }

        // Strategy 3: GitHub /releases/latest web redirect
        if override == nil, let latestWebURL = URL(string: Self.latestHtmlEndpoint) {
            var req = URLRequest(url: latestWebURL)
            req.setValue("APIBar-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 8

            if let (_, response) = try? await URLSession.shared.data(for: req),
               let finalURL = response.url {
                let tag = finalURL.lastPathComponent
                if tag.hasPrefix("v") || tag.first?.isNumber == true {
                    let cleanVer = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                    return ReleaseInfo(
                        version: cleanVer,
                        title: "API Bar v\(cleanVer)",
                        notes: "Latest release available at \(finalURL.absoluteString)",
                        releaseURL: finalURL,
                        downloadURL: URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/\(tag)/APIBar-app.zip"),
                        assetUpdatedAt: nil
                    )
                }
            }
        }

        throw ConnectorError.message("Could not retrieve latest release from GitHub. Please check your internet connection or try again later.")
    }

    public func checkForUpdates(manual: Bool = false, forceSilentInstall: Bool = false) async {
        guard !isChecking else { return }
        transition(to: .checking(manual: manual))

        defer {
            isChecking = false
            lastCheckedDate = Date()
        }

        do {
            let release = try await fetchReleaseInfo()
            let isSemverNewer = Self.isVersion(release.version, newerThan: currentVersion)
            let cleanRel = release.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let cleanCur = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let isSameVersion = cleanRel == cleanCur
            let isSameVersionUpdated: Bool
            let installedTimestamp = UserDefaults.standard.double(forKey: "APIBarInstalledAssetTimestamp")
            let remoteTimestamp = release.assetUpdatedAt?.timeIntervalSince1970 ?? 0
            let alreadyInstalledThisAsset = remoteTimestamp > 0 && abs(remoteTimestamp - installedTimestamp) < 2

            if isSameVersion, !alreadyInstalledThisAsset, Self.localBuildDate != .distantPast, let remoteAssetDate = release.assetUpdatedAt {
                // A legitimate release upload takes 1-3 minutes after local compilation.
                // An asset is only an updated rebuild if uploaded significantly later (> 1 hour / 3600s).
                // Any delta <= 3600s is the original release upload and must not trigger an update.
                isSameVersionUpdated = remoteAssetDate.timeIntervalSince(Self.localBuildDate) > 3600
            } else {
                isSameVersionUpdated = false
            }

            let hasUpdate = isSemverNewer || isSameVersionUpdated
            if hasUpdate {
                transition(to: .available(
                    version: release.version,
                    title: release.title,
                    notes: release.notes,
                    releaseURL: release.releaseURL,
                    downloadURL: release.downloadURL,
                    assetUpdatedAt: release.assetUpdatedAt,
                    isRebuild: isSameVersionUpdated
                ))
            } else {
                transition(to: .upToDate(version: currentVersion, checkedAt: Date()))
            }

            // Cooldown check: prevent rapid reinstallations
            let lastInstallTime = (UserDefaults.standard.object(forKey: "APIBarLastUpdateInstallTime") as? Date) ?? .distantPast
            let elapsed = Date().timeIntervalSince(lastInstallTime)

            if manual {
                // User explicitly clicked "Check for Updates…":
                // If a new version exists on GitHub, show the Software Update window with notes.
                // Otherwise, show the native "You're Up to Date" confirmation dialog.
                if hasUpdate {
                    showUpdateWindow()
                } else {
                    showUpToDateAlert()
                }
            } else if forceSilentInstall {
                // Background silent install triggered by iCloud push:
                // Only execute if not recently updated (>120s cooldown) and there is a newer build or asset
                if elapsed > 120 && hasUpdate {
                    self.statusMessage = "Applying silent update to v\(release.version)…"
                    await self.installUpdate()
                }
            }
        } catch {
            transition(to: .failed(message: error.localizedDescription))
            if manual {
                showAlert("Update Check Failed", error.localizedDescription)
            }
        }
    }

    nonisolated public static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let clean1 = v1.hasPrefix("v") ? String(v1.dropFirst()) : v1
        let clean2 = v2.hasPrefix("v") ? String(v2.dropFirst()) : v2
        let parts1 = clean1.split(separator: ".").compactMap { Int($0.filter { $0.isNumber }) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0.filter { $0.isNumber }) }
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let num1 = i < parts1.count ? parts1[i] : 0
            let num2 = i < parts2.count ? parts2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }

    public func showUpdateWindow() {
        if let updateWindow {
            updateWindow.deminiaturize(nil)
            updateWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Software Update"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 380)

        window.contentView = NSHostingView(rootView: SoftwareUpdateView(updater: self, onDismiss: { [weak window, weak self] in
            window?.close()
            self?.updateWindow = nil
        }))

        window.center()
        window.makeKeyAndOrderFront(nil)
        self.updateWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    public func installUpdate() async {
        let lastInstallTime = (UserDefaults.standard.object(forKey: "APIBarLastUpdateInstallTime") as? Date) ?? .distantPast
        guard Date().timeIntervalSince(lastInstallTime) > 60 else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: "APIBarLastUpdateInstallTime")

        guard let downloadURL else {
            if let releaseURL { NSWorkspace.shared.open(releaseURL) }
            return
        }

        transition(to: .installing(stage: .downloading))
        defer { isInstalling = false }

        do {
            let (tempZipURL, response) = try await URLSession.shared.download(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                transition(to: .failed(message: "Download failed."))
                if let releaseURL { NSWorkspace.shared.open(releaseURL) }
                return
            }

            transition(to: .installing(stage: .extracting))
            let tempExtractDir = FileManager.default.temporaryDirectory.appendingPathComponent("APIBarUpdate-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempExtractDir) }

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", tempZipURL.path, tempExtractDir.path]
            try ditto.run()
            ditto.waitUntilExit()

            let items = try FileManager.default.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil)
            guard let newAppBundle = items.first(where: { $0.pathExtension == "app" }) else {
                transition(to: .failed(message: "Archive did not contain an application bundle."))
                if let releaseURL { NSWorkspace.shared.open(releaseURL) }
                return
            }

            var destURL = Bundle.main.bundleURL
            if destURL.path.contains(".build") || destURL.path.contains(".cache") || !FileManager.default.isWritableFile(atPath: destURL.path) {
                destURL = URL(fileURLWithPath: "/Applications/API Bar.app")
            }

            transition(to: .installing(stage: .replacingBundle))
            let backupURL = destURL.deletingLastPathComponent().appendingPathComponent("APIBar-backup-\(UUID().uuidString).app")
            var didBackup = false
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.moveItem(at: destURL, to: backupURL)
                didBackup = true
            }

            do {
                try FileManager.default.copyItem(at: newAppBundle, to: destURL)
            } catch {
                if didBackup && FileManager.default.fileExists(atPath: backupURL.path) {
                    _ = try? FileManager.default.moveItem(at: backupURL, to: destURL)
                }
                throw error
            }

            if let date = self.assetUpdatedAt {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "APIBarInstalledAssetTimestamp")
            }

            // Strip any quarantine attribute to ensure Gatekeeper permits in-place relaunch
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destURL.path]
            try? xattr.run()
            xattr.waitUntilExit()

            transition(to: .installing(stage: .relaunching))
            let pid = ProcessInfo.processInfo.processIdentifier
            let escapedPath = destURL.path.replacingOccurrences(of: "'", with: "'\\''")
            let escapedBackup = backupURL.path.replacingOccurrences(of: "'", with: "'\\''")

            // Wait for this process to terminate before opening the new bundle.
            // Main.swift enforces single-instance by checking NSRunningApplication,
            // so opening before termination causes the new instance to activate this one and exit immediately.
            let script = """
            while /bin/kill -0 \(pid) 2>/dev/null; do
                /bin/sleep 0.05
            done
            /bin/rm -rf '\(escapedBackup)' 2>/dev/null
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f '\(escapedPath)' 2>/dev/null || true
            /bin/sleep 0.1
            /usr/bin/open '\(escapedPath)' || '\(escapedPath)/Contents/MacOS/APIBar' &
            """

            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", script]
            relaunch.standardInput = FileHandle.nullDevice
            relaunch.standardOutput = FileHandle.nullDevice
            relaunch.standardError = FileHandle.nullDevice
            try relaunch.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                exit(0)
            }
        } catch {
            transition(to: .failed(message: "Installation failed: \(error.localizedDescription)"))
            if let releaseURL { NSWorkspace.shared.open(releaseURL) }
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
        alert.messageText = "You're Up to Date"
        alert.informativeText = "API Bar v\(currentVersion) is currently the latest version. If you're having any issues, hit Redownload to install a fresh copy."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Redownload")
        let prevPolicy = NSApp.activationPolicy()
        if prevPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if prevPolicy != .regular {
            NSApp.setActivationPolicy(.accessory)
        }
        if response == .alertSecondButtonReturn {
            Task {
                UserDefaults.standard.removeObject(forKey: "APIBarLastUpdateInstallTime")
                UserDefaults.standard.removeObject(forKey: "APIBarInstalledAssetTimestamp")
                await self.installUpdate()
            }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        let prevPolicy = NSApp.activationPolicy()
        if prevPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        if prevPolicy != .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Sparkle / CodexBar Styled Software Update Window

struct SoftwareUpdateView: View {
    @ObservedObject var updater: AppUpdater
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: BrandMark.appIconImage(size: 64))
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    let newVer = updater.latestVersion ?? "latest"
                    let isSameVer = updater.latestVersion == updater.currentVersion
                    Text(isSameVer ? "An updated build of API Bar is available!" : "A new version of API Bar is available!")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)

                    if isSameVer {
                        Text("A refreshed build of API Bar \(newVer) is available with the latest updates. Would you like to install it now?")
                            .font(.body)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("API Bar \(newVer) is now available — you have \(updater.currentVersion). Would you like to download it now?")
                            .font(.body)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            // Release Notes / Changelog
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Release Notes:")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if let title = updater.releaseTitle, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let notes = updater.releaseNotes, !notes.isEmpty {
                            RichReleaseNotesView(markdown: notes)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        } else {
                            Text("No release notes available.")
                                .font(.system(.footnote, design: .default))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(14)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer controls
            HStack {
                Button("Remind Me Later") {
                    onDismiss()
                }
                .controlSize(.regular)
                .disabled(updater.isInstalling)

                if let relURL = updater.releaseURL {
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(relURL)
                    }
                    .controlSize(.regular)
                }

                Button("View All Versions…") {
                    NSApp.sendAction(NSSelectorFromString("showChangelog"), to: nil, from: nil)
                }
                .controlSize(.regular)

                Spacer()

                if updater.isInstalling {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(updater.installStatusText)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                } else {
                    Button("Install Update") {
                        Task { await updater.installUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 540, minHeight: 440)
    }
}

// MARK: - Rich Markdown Release Notes View

struct RichReleaseNotesView: View {
    let markdown: String

    struct Block: Identifiable {
        let id = UUID()
        enum Kind {
            case h1(String)
            case h2(String)
            case h3(String)
            case h4(String)
            case divider
            case bullet(indent: Int, text: String)
            case numbered(number: String, text: String)
            case paragraph(String)
        }
        let kind: Kind
    }

    var blocks: [Block] {
        var result: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#### ") {
                result.append(Block(kind: .h4(String(trimmed.dropFirst(5)))))
            } else if trimmed.hasPrefix("### ") {
                result.append(Block(kind: .h3(String(trimmed.dropFirst(4)))))
            } else if trimmed.hasPrefix("## ") {
                result.append(Block(kind: .h2(String(trimmed.dropFirst(3)))))
            } else if trimmed.hasPrefix("# ") {
                result.append(Block(kind: .h1(String(trimmed.dropFirst(2)))))
            } else if trimmed == "---" || trimmed == "***" || (trimmed.allSatisfy({ $0 == "-" || $0 == "_" }) && trimmed.count >= 3) {
                result.append(Block(kind: .divider))
            } else if let match = rawLine.range(of: #"^(\s*)([•\-\*])\s+"#, options: .regularExpression) {
                let prefix = String(rawLine[match])
                let leadingSpaces = prefix.prefix(while: { $0 == " " }).count
                let indent = leadingSpaces >= 4 ? 2 : (leadingSpaces >= 2 ? 1 : 0)
                let text = String(rawLine[match.upperBound...])
                result.append(Block(kind: .bullet(indent: indent, text: text)))
            } else if let numRange = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let num = String(trimmed[numRange])
                let text = String(trimmed[numRange.upperBound...])
                result.append(Block(kind: .numbered(number: num, text: text)))
            } else {
                result.append(Block(kind: .paragraph(trimmed)))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                switch block.kind {
                case .h1(let text):
                    Text(inlineMarkdown(text))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)
                        .padding(.top, 8)
                case .h2(let text):
                    Text(inlineMarkdown(text))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)
                        .padding(.top, 6)
                case .h3(let text):
                    Text(inlineMarkdown(text))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                        .padding(.top, 5)
                case .h4(let text):
                    Text(inlineMarkdown(text))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)
                        .padding(.top, 3)
                case .divider:
                    Divider()
                        .padding(.vertical, 5)
                case .bullet(let indent, let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text(indent > 0 ? "◦" : "•")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 12, alignment: .center)
                        Text(inlineMarkdown(text))
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(Color.primary)
                            .lineSpacing(3.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(indent) * 16)
                case .numbered(let number, let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text(number)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(minWidth: 18, alignment: .leading)
                        Text(inlineMarkdown(text))
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(Color.primary)
                            .lineSpacing(3.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let text):
                    Text(inlineMarkdown(text))
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.primary)
                        .lineSpacing(3.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(text)
    }
}
