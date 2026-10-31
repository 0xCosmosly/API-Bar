import Foundation
import AppKit
import SwiftUI

@MainActor
public final class AppUpdater: ObservableObject {
    public static let shared = AppUpdater()

    public static let repoOwner = "0xCosmosly"
    public static let repoName = "api-bar"
    public static let latestReleaseEndpoint = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.7"
    }

    public init() {}

    public func checkForUpdates(manual: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        checkError = nil
        if manual { statusMessage = "Checking for updates…" }

        defer {
            isChecking = false
            lastCheckedDate = Date()
        }

        guard let url = URL(string: Self.latestReleaseEndpoint) else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("APIBar-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                if manual { showAlert("Update Check Failed", "Could not connect to GitHub to check for updates.") }
                return
            }

            if http.statusCode == 404 {
                // No releases published yet on this repository
                self.updateAvailable = false
                self.statusMessage = "You're running v\(currentVersion). No new releases are available."
                if manual {
                    showAlert("You're Up to Date", "API Bar v\(currentVersion) is currently the latest version.")
                }
                return
            }

            guard http.statusCode == 200 else {
                if manual { showAlert("Update Check Failed", "GitHub returned status HTTP \(http.statusCode).") }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                if manual { showAlert("Update Check Failed", "Could not parse release details from GitHub.") }
                return
            }

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

            let isNewer = Self.isVersion(releaseVer, newerThan: currentVersion)
            self.latestVersion = releaseVer
            self.releaseTitle = title
            self.releaseNotes = notes
            self.releaseURL = releaseHtmlURL
            self.downloadURL = zipURL
            self.updateAvailable = isNewer

            if isNewer {
                self.statusMessage = "Update available: v\(releaseVer)"
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
