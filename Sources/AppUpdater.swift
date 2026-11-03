import Foundation
import AppKit
import SwiftUI

@MainActor
public final class AppUpdater: ObservableObject {
    public static let shared = AppUpdater()

    public static let repoOwner = "0xCosmosly"
    public static let repoName = "API-Bar"
    public static let latestReleaseEndpoint = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    public static let fallbackFeedEndpoint = "https://github.com/\(repoOwner)/\(repoName)/releases.atom"
    public static let latestHtmlEndpoint = "https://github.com/\(repoOwner)/\(repoName)/releases/latest"

    @Published public var isChecking: Bool = false
    @Published public var updateAvailable: Bool = false
    @Published public var latestVersion: String? = nil
    @Published public var releaseTitle: String? = nil
    @Published public var releaseNotes: String? = nil
    @Published public var releaseURL: URL? = nil
    @Published public var downloadURL: URL? = nil
    @Published public var checkError: String? = nil
    @Published public var isInstalling: Bool = false
    @Published public var installStatusText: String = ""
    @Published public var statusMessage: String = ""

    private var updateWindow: NSWindow?
    private var lastCheckedDate: Date?

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.8"
    }

    public struct ReleaseInfo {
        public let version: String
        public let title: String
        public let notes: String
        public let releaseURL: URL?
        public let downloadURL: URL?
    }

    public init() {}

    public func fetchReleaseInfo() async throws -> ReleaseInfo {
        // Strategy 1: Try GitHub REST API
        if let apiURL = URL(string: Self.latestReleaseEndpoint) {
            var req = URLRequest(url: apiURL)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            req.setValue("APIBar-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 8

            if let (data, response) = try? await URLSession.shared.data(for: req),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                let releaseVer = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                let title = json["name"] as? String ?? "API Bar v\(releaseVer)"
                let notes = json["body"] as? String ?? "No release notes provided."
                let htmlUrlStr = json["html_url"] as? String
                let releaseHtmlURL = htmlUrlStr.flatMap { URL(string: $0) }

                var zipURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                           let download = asset["browser_download_url"] as? String,
                           let assetURL = URL(string: download) {
                            zipURL = assetURL
                            break
                        }
                    }
                }
                return ReleaseInfo(
                    version: releaseVer,
                    title: title,
                    notes: notes,
                    releaseURL: releaseHtmlURL,
                    downloadURL: zipURL ?? URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/\(tagName)/APIBar-app.zip")
                )
            }
        }

        // Strategy 2: GitHub Releases Atom Feed (resilient to GitHub REST API 403 rate limits)
        if let feedURL = URL(string: Self.fallbackFeedEndpoint) {
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

                        let cleanVer = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                        let htmlURL = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/tag/\(tag)")
                        let downloadURL = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/\(tag)/APIBar-app.zip")
                        return ReleaseInfo(
                            version: cleanVer,
                            title: title,
                            notes: notes.isEmpty ? "No release notes provided." : notes,
                            releaseURL: htmlURL,
                            downloadURL: downloadURL
                        )
                    }
                }
            }
        }

        // Strategy 3: GitHub /releases/latest web redirect
        if let latestWebURL = URL(string: Self.latestHtmlEndpoint) {
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
                        downloadURL: URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/\(tag)/APIBar-app.zip")
                    )
                }
            }
        }

        throw ConnectorError.message("Could not retrieve latest release from GitHub. Please check your internet connection or try again later.")
    }

    public func checkForUpdates(manual: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        checkError = nil
        if manual { statusMessage = "Checking for updates…" }

        defer {
            isChecking = false
            lastCheckedDate = Date()
        }

        do {
            let release = try await fetchReleaseInfo()
            let isNewer = Self.isVersion(release.version, newerThan: currentVersion)
            self.latestVersion = release.version
            self.releaseTitle = release.title
            self.releaseNotes = release.notes
            self.releaseURL = release.releaseURL
            self.downloadURL = release.downloadURL
            self.updateAvailable = isNewer

            if isNewer {
                self.statusMessage = "Update available: v\(release.version)"
                if manual {
                    showUpdateWindow()
                }
            } else {
                self.statusMessage = "You're up to date (v\(currentVersion))."
                if manual {
                    showAlert("You're Up to Date", "API Bar v\(currentVersion) is currently the latest version.")
                }
            }
        } catch {
            self.checkError = error.localizedDescription
            if manual {
                showAlert("Update Check Failed", error.localizedDescription)
            }
        }
    }

    public static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
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
        guard let downloadURL else {
            if let releaseURL { NSWorkspace.shared.open(releaseURL) }
            return
        }

        isInstalling = true
        installStatusText = "Downloading update from GitHub…"
        defer { isInstalling = false }

        do {
            let (tempZipURL, response) = try await URLSession.shared.download(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                installStatusText = "Download failed."
                if let releaseURL { NSWorkspace.shared.open(releaseURL) }
                return
            }

            installStatusText = "Extracting update archive…"
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
                installStatusText = "Archive did not contain an application bundle."
                if let releaseURL { NSWorkspace.shared.open(releaseURL) }
                return
            }

            var destURL = Bundle.main.bundleURL
            if destURL.path.contains(".build") || destURL.path.contains(".cache") || !FileManager.default.isWritableFile(atPath: destURL.path) {
                destURL = URL(fileURLWithPath: "/Applications/API Bar.app")
            }

            installStatusText = "Replacing application bundle…"
            let backupURL = destURL.deletingLastPathComponent().appendingPathComponent("APIBar-backup-\(UUID().uuidString).app")
            if FileManager.default.fileExists(atPath: destURL.path) {
                _ = try? FileManager.default.moveItem(at: destURL, to: backupURL)
            }
            try FileManager.default.copyItem(at: newAppBundle, to: destURL)
            _ = try? FileManager.default.removeItem(at: backupURL)

            installStatusText = "Relaunching API Bar…"
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-n", destURL.path]
            try relaunch.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } catch {
            installStatusText = "Installation failed: \(error.localizedDescription)"
            if let releaseURL { NSWorkspace.shared.open(releaseURL) }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage ?? BrandMark.appIconImage(size: 128)
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
                    Text("A new version of API Bar is available!")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)

                    let newVer = updater.latestVersion ?? "latest"
                    Text("API Bar \(newVer) is now available — you have \(updater.currentVersion). Would you like to download it now?")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if let title = updater.releaseTitle, !title.isEmpty {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(updater.releaseNotes ?? "No release notes available.")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(Color.primary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
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
