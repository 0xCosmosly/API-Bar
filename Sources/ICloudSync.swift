import Foundation
import AppKit

struct ICloudSettings: Codable, Equatable {
    var sortMode: String?
    var mergeIcons: Bool?
    var mergedProvider: String?
    var removedProviders: [String]?
    var lastModified: Date
    var deviceName: String

    init(
        sortMode: String? = nil,
        mergeIcons: Bool? = nil,
        mergedProvider: String? = nil,
        removedProviders: [String]? = nil,
        lastModified: Date = Date(),
        deviceName: String = Host.current().localizedName ?? "Mac"
    ) {
        self.sortMode = sortMode
        self.mergeIcons = mergeIcons
        self.mergedProvider = mergedProvider
        self.removedProviders = removedProviders
        self.lastModified = lastModified
        self.deviceName = deviceName
    }
}

struct ICloudManifest: Codable, Equatable {
    var version: Int
    var lastModified: Date
    var deviceId: String
    var deviceName: String
    var providerCount: Int
    var hasOpenCode: Bool?
    var hasPi: Bool?
    var hasOmp: Bool?
    var appBuildTimestamp: Double?

    init(version: Int = 1, lastModified: Date = Date(), deviceId: String, deviceName: String, providerCount: Int, hasOpenCode: Bool? = nil, hasPi: Bool? = nil, hasOmp: Bool? = nil, appBuildTimestamp: Double? = nil) {
        self.version = version
        self.lastModified = lastModified
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.providerCount = providerCount
        self.hasOpenCode = hasOpenCode
        self.hasPi = hasPi
        self.hasOmp = hasOmp
        self.appBuildTimestamp = appBuildTimestamp
    }
}

public enum CloudSyncPhase: String, Equatable, Codable, Sendable {
    case pulling = "pulling"
    case pushing = "pushing"
    case full = "syncing"
}

public enum CloudSyncState: Equatable, Sendable {
    case unavailable(reason: String)
    case disabled
    case idle(lastSync: Date?)
    case syncing(phase: CloudSyncPhase)
    case failed(error: String, lastSync: Date?)

    public var telemetryName: String {
        switch self {
        case .unavailable: return "unavailable"
        case .disabled: return "disabled"
        case .idle: return "idle"
        case .syncing: return "syncing"
        case .failed: return "failed"
        }
    }

    public var statusBadge: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .disabled: return "Off"
        case .syncing: return "Syncing…"
        case .idle, .failed: return "Active"
        }
    }
}

@MainActor
final class ICloudSync: ObservableObject {
    static let shared = ICloudSync()

    static let enabledKey = "ICloudSyncEnabled"
    static let openCodeEnabledKey = "ICloudSyncOpenCodeEnabled"
    static let openCodeCredentialsEnabledKey = "ICloudSyncOpenCodeCredentialsEnabled"
    static let piEnabledKey = "ICloudSyncPiEnabled"
    static let piCredentialsEnabledKey = "ICloudSyncPiCredentialsEnabled"
    static let ompEnabledKey = "ICloudSyncOmpEnabled"
    static let ompCredentialsEnabledKey = "ICloudSyncOmpCredentialsEnabled"
    static let lastSyncKey = "ICloudSyncLastDate"
    static let deviceIdKey = "APIBarDeviceUUID"

    @Published public private(set) var state: CloudSyncState = .disabled
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var isAvailable: Bool = false
    @Published var isEnabled: Bool = false
    @Published var isOpenCodeSyncEnabled: Bool = false
    @Published var isOpenCodeCredentialsSyncEnabled: Bool = true
    @Published var isPiSyncEnabled: Bool = false
    @Published var isPiCredentialsSyncEnabled: Bool = true
    @Published var isOmpSyncEnabled: Bool = false
    @Published var isOmpCredentialsSyncEnabled: Bool = true
    @Published private(set) var lastSyncDate: Date? = nil
    @Published private(set) var statusMessage: String = "Disabled"
    @Published private(set) var lastError: String? = nil

    public func transition(to newState: CloudSyncState) {
        self.state = newState
        switch newState {
        case .unavailable(let reason):
            self.isAvailable = false
            self.isSyncing = false
            self.statusMessage = reason
        case .disabled:
            self.isSyncing = false
            self.statusMessage = "iCloud Sync is turned off"
        case .idle(let date):
            self.isSyncing = false
            self.lastSyncDate = date
            self.lastError = nil
            if let date {
                self.statusMessage = "Last synced \(relativeTimeString(for: date))"
            } else {
                self.statusMessage = "Ready to sync"
            }
        case .syncing:
            self.isSyncing = true
            self.statusMessage = "Syncing with iCloud…"
        case .failed(let error, let lastDate):
            self.isSyncing = false
            self.lastError = error
            self.lastSyncDate = lastDate
            self.statusMessage = "Sync error: \(error)"
        }
    }

    public var telemetryRepresentation: [String: Any] {
        var dict: [String: Any] = [
            "state": state.telemetryName,
            "isEnabled": isEnabled,
            "isAvailable": isAvailable,
            "isSyncing": isSyncing,
            "statusBadge": statusBadge,
            "statusMessage": statusMessage
        ]
        if let lastSyncDate { dict["lastSync"] = lastSyncDate.timeIntervalSince1970 }
        if let lastError { dict["lastError"] = lastError }
        return dict
    }

    private weak var app: APIBarApp?
    private var pushDebounceTask: Task<Void, Never>?
    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitorFD: Int32 = -1
    private var openCodeMonitorSource: DispatchSourceFileSystemObject?
    private var openCodeMonitorFD: Int32 = -1
    private var piMonitorSource: DispatchSourceFileSystemObject?
    private var piMonitorFD: Int32 = -1
    private var ompMonitorSource: DispatchSourceFileSystemObject?
    private var ompMonitorFD: Int32 = -1
    private var isPerformingSync: Bool = false
    private var lastPushedDate: Date = .distantPast

    var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: Self.deviceIdKey) {
            return id
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: Self.deviceIdKey)
        return fresh
    }

    var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    var statusBadge: String {
        state.statusBadge
    }

    var baseDirectoryURL: URL? {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_ICLOUD_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        if let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return ubiquity.appendingPathComponent("Documents/API Bar", isDirectory: true)
        }
        let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/API Bar", isDirectory: true)
        return cloudDocs
    }

    var balancesURL: URL? {
        baseDirectoryURL?.appendingPathComponent("balances.json")
    }

    var settingsURL: URL? {
        baseDirectoryURL?.appendingPathComponent("settings.json")
    }

    var manifestURL: URL? {
        baseDirectoryURL?.appendingPathComponent("manifest.json")
    }

    var vaultDirectoryURL: URL? {
        baseDirectoryURL?.appendingPathComponent("vault", isDirectory: true)
    }

    var localOpenCodeURL: URL {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_OPENCODE_FILE"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/opencode.json")
    }

    var cloudOpenCodeURL: URL? {
        baseDirectoryURL?.appendingPathComponent("opencode.json")
    }

    var localOpenCodeCredentialsURL: URL? {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_OPENCODE_CREDENTIALS_FILE"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return nil
    }

    var cloudOpenCodeCredentialsURL: URL? {
        vaultDirectoryURL?.appendingPathComponent("opencode-credentials.json")
    }

    var localPiDirectoryURL: URL {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_PI_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        if let custom = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent", isDirectory: true)
    }

    var cloudPiDirectoryURL: URL? {
        baseDirectoryURL?.appendingPathComponent("pi", isDirectory: true)
    }

    var cloudPiCredentialsURL: URL? {
        vaultDirectoryURL?.appendingPathComponent("pi-auth.json")
    }

    var localOmpDirectoryURL: URL {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_OMP_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        if let custom = ProcessInfo.processInfo.environment["OMP_AGENT_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omp/agent", isDirectory: true)
    }

    var cloudOmpDirectoryURL: URL? {
        baseDirectoryURL?.appendingPathComponent("omp", isDirectory: true)
    }

    var localOmpCredentialsURL: URL? {
        if let custom = ProcessInfo.processInfo.environment["APIBAR_OMP_CREDENTIALS_FILE"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return nil
    }

    var cloudOmpCredentialsURL: URL? {
        vaultDirectoryURL?.appendingPathComponent("omp-credentials.json")
    }

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.isOpenCodeSyncEnabled = UserDefaults.standard.bool(forKey: Self.openCodeEnabledKey)
        if UserDefaults.standard.object(forKey: Self.openCodeCredentialsEnabledKey) == nil {
            self.isOpenCodeCredentialsSyncEnabled = true
        } else {
            self.isOpenCodeCredentialsSyncEnabled = UserDefaults.standard.bool(forKey: Self.openCodeCredentialsEnabledKey)
        }
        self.isPiSyncEnabled = UserDefaults.standard.bool(forKey: Self.piEnabledKey)
        if UserDefaults.standard.object(forKey: Self.piCredentialsEnabledKey) == nil {
            self.isPiCredentialsSyncEnabled = true
        } else {
            self.isPiCredentialsSyncEnabled = UserDefaults.standard.bool(forKey: Self.piCredentialsEnabledKey)
        }
        self.isOmpSyncEnabled = UserDefaults.standard.bool(forKey: Self.ompEnabledKey)
        if UserDefaults.standard.object(forKey: Self.ompCredentialsEnabledKey) == nil {
            self.isOmpCredentialsSyncEnabled = true
        } else {
            self.isOmpCredentialsSyncEnabled = UserDefaults.standard.bool(forKey: Self.ompCredentialsEnabledKey)
        }
        if let ts = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date {
            self.lastSyncDate = ts
        }
        _ = checkAvailability()
        updateStatusMessage()
    }

    func attach(app: APIBarApp) {
        self.app = app
        _ = checkAvailability()
        if isEnabled {
            startMonitoring()
            if isOpenCodeSyncEnabled {
                startOpenCodeMonitoring()
            }
            if isPiSyncEnabled {
                startPiMonitoring()
            }
            if isOmpSyncEnabled {
                startOmpMonitoring()
            }
            Task { await syncNow() }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            _ = checkAvailability()
            startMonitoring()
            if isOpenCodeSyncEnabled {
                startOpenCodeMonitoring()
            }
            if isPiSyncEnabled {
                startPiMonitoring()
            }
            if isOmpSyncEnabled {
                startOmpMonitoring()
            }
            Task { await syncNow() }
        } else {
            stopMonitoring()
            stopOpenCodeMonitoring()
            stopPiMonitoring()
            stopOmpMonitoring()
            updateStatusMessage()
        }
    }

    func setOpenCodeSyncEnabled(_ enabled: Bool) {
        guard isOpenCodeSyncEnabled != enabled else { return }
        isOpenCodeSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.openCodeEnabledKey)
        if enabled && isEnabled {
            startOpenCodeMonitoring()
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Pull cloud state first so a newly enabled client never overwrites cloud config
                let pulled = await self.pullAndMerge()
                let pushed = await self.pushLocalState()
                if pulled || pushed {
                    self.updateStatusMessage()
                }
            }
        } else {
            stopOpenCodeMonitoring()
        }
    }

    func setOpenCodeCredentialsSyncEnabled(_ enabled: Bool) {
        guard isOpenCodeCredentialsSyncEnabled != enabled else { return }
        isOpenCodeCredentialsSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.openCodeCredentialsEnabledKey)
        if enabled && isEnabled && isOpenCodeSyncEnabled {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let pulled = await self.pullAndMerge()
                let pushed = await self.pushLocalState()
                if pulled || pushed {
                    self.updateStatusMessage()
                }
            }
        }
    }

    func setPiSyncEnabled(_ enabled: Bool) {
        guard isPiSyncEnabled != enabled else { return }
        isPiSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.piEnabledKey)
        if enabled && isEnabled {
            startPiMonitoring()
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Pull cloud state first so a newly enabled client never overwrites cloud config
                let pulled = await self.pullAndMerge()
                let pushed = await self.pushLocalState()
                if pulled || pushed {
                    self.updateStatusMessage()
                }
            }
        } else {
            stopPiMonitoring()
        }
    }

    func setPiCredentialsSyncEnabled(_ enabled: Bool) {
        guard isPiCredentialsSyncEnabled != enabled else { return }
        isPiCredentialsSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.piCredentialsEnabledKey)
        if enabled && isEnabled && isPiSyncEnabled {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let pulled = await self.pullAndMerge()
                let pushed = await self.pushLocalState()
                if pulled || pushed {
                    self.updateStatusMessage()
                }
            }
        }
    }

    func setOmpSyncEnabled(_ enabled: Bool) {
        guard isOmpSyncEnabled != enabled else { return }
        isOmpSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.ompEnabledKey)
        if enabled && isEnabled {
            startOmpMonitoring()
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Pull cloud state first so a newly enabled client never overwrites cloud config
                let pulled = await self.pullAndMerge()
                let pushed = await self.pushLocalState()
                if pulled || pushed {
                    self.updateStatusMessage()
                }
            }
        } else {
            stopOmpMonitoring()
        }
    }

    func setOmpCredentialsSyncEnabled(_ enabled: Bool) {
        guard isOmpCredentialsSyncEnabled != enabled else { return }
        isOmpCredentialsSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.ompCredentialsEnabledKey)
        if enabled && isEnabled && isOmpSyncEnabled {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let pulled = await self.pullAndMerge()
                let pushed = await self.pushLocalState()
                if pulled || pushed {
                    self.updateStatusMessage()
                }
            }
        }
    }

    private func findOmpBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") where !dir.isEmpty {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("omp").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        let candidates = [
            home.appendingPathComponent(".local/bin/omp").path,
            "/usr/local/bin/omp",
            "/opt/homebrew/bin/omp",
            home.appendingPathComponent(".bun/bin/omp").path,
            home.appendingPathComponent(".cargo/bin/omp").path,
            home.appendingPathComponent(".omp/bin/omp").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func exportOmpCredentials() -> Data? {
        if let testURL = localOmpCredentialsURL {
            return try? Data(contentsOf: testURL)
        }
        let authURL = localOmpDirectoryURL.appendingPathComponent("auth.json")
        if FileManager.default.fileExists(atPath: authURL.path) {
            return try? Data(contentsOf: authURL)
        }
        return nil
    }

    @discardableResult
    func importOmpCredentials(data: Data) -> Bool {
        let destURL = localOmpCredentialsURL ?? localOmpDirectoryURL.appendingPathComponent("auth.json")
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destURL.path)
            return true
        } catch {
            return false
        }
    }

    private func findOpenCodeBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") where !dir.isEmpty {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("opencode").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        let candidates = [
            home.appendingPathComponent(".opencode/bin/opencode").path,
            home.appendingPathComponent(".local/bin/opencode").path,
            "/usr/local/bin/opencode",
            "/opt/homebrew/bin/opencode",
            home.appendingPathComponent(".bun/bin/opencode").path,
            home.appendingPathComponent(".cargo/bin/opencode").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func exportOpenCodeCredentials() -> Data? {
        if let testURL = localOpenCodeCredentialsURL {
            return try? Data(contentsOf: testURL)
        }
        guard let bin = findOpenCodeBinary() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["auth", "export"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if !data.isEmpty && (try? JSONSerialization.jsonObject(with: data)) != nil {
                    return data
                }
            }
        } catch {}
        return nil
    }

    @discardableResult
    func importOpenCodeCredentials(data: Data) -> Bool {
        if let testURL = localOpenCodeCredentialsURL {
            do {
                try data.write(to: testURL, options: .atomic)
                return true
            } catch {
                return false
            }
        }
        guard let bin = findOpenCodeBinary() else { return false }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("apibar_auth_\(UUID().uuidString).json")
        do {
            try data.write(to: tempURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["auth", "import", tempURL.path]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    func checkAvailability() -> Bool {
        if ProcessInfo.processInfo.environment["APIBAR_ICLOUD_DIR"] != nil {
            isAvailable = true
            return true
        }
        if FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil {
            isAvailable = true
            return true
        }
        let cloudDocsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let available = FileManager.default.fileExists(atPath: cloudDocsRoot.path)
        isAvailable = available
        return available
    }

    func updateStatusMessage() {
        if !isAvailable {
            transition(to: .unavailable(reason: "iCloud Drive is not available on this Mac"))
        } else if !isEnabled {
            transition(to: .disabled)
        } else if isPerformingSync {
            transition(to: .syncing(phase: .full))
        } else if let date = lastSyncDate {
            transition(to: .idle(lastSync: date))
        } else {
            transition(to: .idle(lastSync: nil))
        }
    }

    func schedulePush() {
        guard isEnabled, !isPerformingSync else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            guard let self = self, self.isEnabled, !self.isPerformingSync else { return }
            self.isPerformingSync = true
            self.transition(to: .syncing(phase: .pushing))
            defer {
                self.isPerformingSync = false
                self.updateStatusMessage()
            }
            await self.pushLocalState()
        }
    }

    func syncNow() async {
        guard !isPerformingSync else { return }
        isPerformingSync = true
        transition(to: .syncing(phase: .full))
        defer {
            isPerformingSync = false
            updateStatusMessage()
        }

        guard checkAvailability() else {
            transition(to: .unavailable(reason: "iCloud Drive is not available on this Mac"))
            return
        }

        _ = await pullAndMerge()
        _ = await pushLocalState()
        let now = Date()
        lastSyncDate = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
    }

    @discardableResult
    func pullAndMerge() async -> Bool {
        guard let base = baseDirectoryURL, let app = app else { return false }
        guard checkAvailability() else { return false }
        guard FileManager.default.fileExists(atPath: base.path) else { return false }

        var didChangeLocally = false

        // 0. Check for remote build update push
        if let manifestURL = manifestURL,
           let data = try? Data(contentsOf: manifestURL),
           let remoteManifest = try? JSONDecoder().decode(ICloudManifest.self, from: data),
           remoteManifest.deviceId != self.deviceId,
           let remoteBuild = remoteManifest.appBuildTimestamp {
            let lastInstall = (UserDefaults.standard.object(forKey: "APIBarLastUpdateInstallTime") as? Date) ?? .distantPast
            let localTS = max(AppUpdater.localBuildDate.timeIntervalSince1970, lastInstall.timeIntervalSince1970)
            if remoteBuild > localTS + 60 {
                Task { @MainActor in
                    await AppUpdater.shared.checkForUpdates(manual: false, forceSilentInstall: true)
                }
            }
        }

        // 1. Pull settings
        if let settingsURL = settingsURL,
           let data = try? Data(contentsOf: settingsURL),
           let remoteSettings = try? JSONDecoder().decode(ICloudSettings.self, from: data) {

            let localSettingsTS = (UserDefaults.standard.object(forKey: "APIBarSettingsModified") as? Date) ?? .distantPast
            if remoteSettings.lastModified > localSettingsTS {
                if let remoteRemoved = remoteSettings.removedProviders {
                    let localRemoved = UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? []
                    let activeIDs = Set(app.balances.map(\.id))
                    let combined = Array(Set(localRemoved).union(remoteRemoved)).filter { !activeIDs.contains($0) }
                    if combined.sorted() != localRemoved.sorted() {
                        UserDefaults.standard.set(combined, forKey: "RemovedProviders")
                    }
                }
                if let modeStr = remoteSettings.sortMode, let mode = ProviderSortMode(rawValue: modeStr), mode != app.sortMode {
                    app.sortMode = mode
                    UserDefaults.standard.set(mode.rawValue, forKey: "ProviderSortMode")
                    didChangeLocally = true
                }
                if let merge = remoteSettings.mergeIcons, merge != app.mergeIcons {
                    app.mergeIcons = merge
                    UserDefaults.standard.set(merge, forKey: "MergeProviderIcons")
                    app.configureStatusItems()
                    didChangeLocally = true
                }
                if let merged = remoteSettings.mergedProvider, merged != app.mergedProvider {
                    app.mergedProvider = merged
                    UserDefaults.standard.set(merged, forKey: "MergedProvider")
                    didChangeLocally = true
                }
                UserDefaults.standard.set(remoteSettings.lastModified, forKey: "APIBarSettingsModified")
            }
        }

        // 2. Pull balances
        if let balancesURL = balancesURL,
           let data = try? Data(contentsOf: balancesURL),
           let remoteBalances = try? JSONDecoder().decode([Balance].self, from: data) {

            var current = app.balances
            let removedSet = Set(UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? [])

            for remote in remoteBalances {
                if let localIdx = current.firstIndex(where: { $0.id == remote.id }) {
                    // A prepaid balance reference cannot be thousands of times the
                    // remaining balance. An early Unaligned build stored its
                    // micro-dollar balance as the reference, and re-adopting that
                    // from the cloud would undo the local repair on every pull.
                    let implausibleUnaligned = remote.id == "unaligned" && remote.baseline > 1_000 && remote.remaining < 1_000
                        && remote.baseline > remote.remaining * 1_000
                    // An earlier build or an un-updated client spuriously inflated Heimdallm's
                    // baseline to $10.00+ on credit hold releases. If a remote sync pushes an
                    // inflated baseline while remaining is <= $5.00, or if this Mac already has
                    // an authoritative baseline from the live API, reject the remote inflation.
                    let implausibleHeimdallm = remote.id == "heimdallm" && (
                        (remote.baseline > 5.0 && remote.remaining <= 5.0) ||
                        (current[localIdx].baseline > 0 && remote.baseline > current[localIdx].baseline && (app.isConnected("heimdallm") || current[localIdx].live))
                    )
                    let implausibleBaseline = implausibleUnaligned || implausibleHeimdallm
                    if remote.baseline > 0 && remote.baseline != current[localIdx].baseline && !implausibleBaseline {
                        if remote.updated >= current[localIdx].updated || current[localIdx].baseline == 0 {
                            current[localIdx].baseline = max(remote.baseline, current[localIdx].remaining)
                            didChangeLocally = true
                        }
                    }
                    if remote.dynamicEndpoint != nil {
                        if current[localIdx].dynamicEndpoint != remote.dynamicEndpoint ||
                           current[localIdx].dynamicJsonPath != remote.dynamicJsonPath ||
                           current[localIdx].dynamicCookieDomain != remote.dynamicCookieDomain {
                            current[localIdx].dynamicEndpoint = remote.dynamicEndpoint
                            current[localIdx].dynamicJsonPath = remote.dynamicJsonPath
                            current[localIdx].dynamicCookieDomain = remote.dynamicCookieDomain
                            didChangeLocally = true
                        }
                    }
                    if let auth = remote.dynamicAuthHeader, !auth.isEmpty, current[localIdx].dynamicAuthHeader != auth {
                        current[localIdx].dynamicAuthHeader = auth
                        current[localIdx].live = true
                        app.providerStatus[remote.id] = "Connected · refreshes every 5 min"
                        didChangeLocally = true
                    }
                    if remote.updated > current[localIdx].updated {
                        current[localIdx].remaining = remote.remaining
                        current[localIdx].updated = remote.updated
                        current[localIdx].account = remote.account
                        current[localIdx].expires = remote.expires
                        current[localIdx].live = remote.live || current[localIdx].live
                        didChangeLocally = true
                    }
                } else if !removedSet.contains(remote.id) {
                    current.append(remote)
                    if app.isConnected(remote.id) || (remote.dynamicAuthHeader != nil && !remote.dynamicAuthHeader!.isEmpty) {
                        app.providerStatus[remote.id] = "Connected · refreshes every 5 min"
                    } else {
                        app.providerStatus[remote.id] = "Connect in Settings"
                    }
                    didChangeLocally = true
                }
            }

            if didChangeLocally {
                app.balances = current
                app.save()
                app.applySorting()
                app.reapplyOrder()
                app.updateTitles()
            }
        }

        // 3. Pull vault sessions
        if let cloudVault = vaultDirectoryURL, FileManager.default.fileExists(atPath: cloudVault.path) {
            let localVault = KeychainVault.vaultDir
            if let files = try? FileManager.default.contentsOfDirectory(atPath: cloudVault.path) {
                for file in files where file.hasSuffix(".dat") && !file.contains("brave_safe_storage_key") {
                    let remoteFile = cloudVault.appendingPathComponent(file)
                    let localFile = localVault.appendingPathComponent(file)
                    let provider = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent

                    let shouldCopy: Bool
                    if !FileManager.default.fileExists(atPath: localFile.path) {
                        shouldCopy = true
                    } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: remoteFile.path),
                              let localAttrs = try? FileManager.default.attributesOfItem(atPath: localFile.path),
                              let remoteDate = remoteAttrs[.modificationDate] as? Date,
                              let localDate = localAttrs[.modificationDate] as? Date,
                              remoteDate > localDate {
                        shouldCopy = true
                    } else {
                        shouldCopy = false
                    }

                    if shouldCopy, let data = try? Data(contentsOf: remoteFile), !data.isEmpty {
                        try? FileManager.default.createDirectory(at: localVault, withIntermediateDirectories: true)
                        try? data.write(to: localFile, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localFile.path)
                        try? KeychainVault.save(data, account: provider, interactive: false)
                        if app.balances.contains(where: { $0.id == provider }) {
                            app.providerStatus[provider] = "Connected · refreshes every 5 min"
                        }
                    }
                }
            }
        }

        // 4. Pull OpenCode configuration
        if isOpenCodeSyncEnabled,
           let cloudOpenCode = cloudOpenCodeURL,
           FileManager.default.fileExists(atPath: cloudOpenCode.path) {
            let localOpenCode = localOpenCodeURL
            let shouldCopy: Bool
            if !FileManager.default.fileExists(atPath: localOpenCode.path) {
                shouldCopy = true
            } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: cloudOpenCode.path),
                      let localAttrs = try? FileManager.default.attributesOfItem(atPath: localOpenCode.path),
                      let remoteDate = remoteAttrs[.modificationDate] as? Date,
                      let localDate = localAttrs[.modificationDate] as? Date {
                let remoteSize = (remoteAttrs[.size] as? NSNumber)?.int64Value ?? 0
                let localSize = (localAttrs[.size] as? NSNumber)?.int64Value ?? 0
                shouldCopy = remoteDate > localDate || remoteSize > (localSize + 100)
            } else {
                shouldCopy = false
            }

            if shouldCopy, let data = try? Data(contentsOf: cloudOpenCode), !data.isEmpty {
                let localData = try? Data(contentsOf: localOpenCode)
                if localData != data {
                    let configDir = localOpenCode.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: localOpenCode.path) {
                        let backupURL = configDir.appendingPathComponent("opencode.json.bak")
                        try? FileManager.default.removeItem(at: backupURL)
                        try? FileManager.default.copyItem(at: localOpenCode, to: backupURL)
                    }
                    try? data.write(to: localOpenCode, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localOpenCode.path)
                    didChangeLocally = true
                }
            }
        }

        // 4b. Pull OpenCode credentials
        if isOpenCodeSyncEnabled && isOpenCodeCredentialsSyncEnabled,
           let cloudCreds = cloudOpenCodeCredentialsURL,
           FileManager.default.fileExists(atPath: cloudCreds.path) {
            if let data = try? Data(contentsOf: cloudCreds), !data.isEmpty {
                if importOpenCodeCredentials(data: data) {
                    didChangeLocally = true
                }
            }
        }

        // 5. Pull Pi configuration
        if isPiSyncEnabled,
           let cloudPi = cloudPiDirectoryURL,
           FileManager.default.fileExists(atPath: cloudPi.path) {
            let localPi = localPiDirectoryURL
            let configFiles = ["models.json", "settings.json", "mcp.json"]
            for file in configFiles {
                let remoteFile = cloudPi.appendingPathComponent(file)
                guard FileManager.default.fileExists(atPath: remoteFile.path) else { continue }
                let localFile = localPi.appendingPathComponent(file)

                let shouldCopy: Bool
                if !FileManager.default.fileExists(atPath: localFile.path) {
                    shouldCopy = true
                } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: remoteFile.path),
                          let localAttrs = try? FileManager.default.attributesOfItem(atPath: localFile.path),
                          let remoteDate = remoteAttrs[.modificationDate] as? Date,
                          let localDate = localAttrs[.modificationDate] as? Date {
                    shouldCopy = remoteDate > localDate
                } else {
                    shouldCopy = false
                }

                if shouldCopy, let data = try? Data(contentsOf: remoteFile), !data.isEmpty {
                    let localData = try? Data(contentsOf: localFile)
                    if localData != data {
                        try? FileManager.default.createDirectory(at: localPi, withIntermediateDirectories: true)
                        if FileManager.default.fileExists(atPath: localFile.path) {
                            let backupURL = localPi.appendingPathComponent("\(file).bak")
                            try? FileManager.default.removeItem(at: backupURL)
                            try? FileManager.default.copyItem(at: localFile, to: backupURL)
                        }
                        try? data.write(to: localFile, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localFile.path)
                        didChangeLocally = true
                    }
                }
            }
        }

        // 5b. Pull Pi credentials
        if isPiSyncEnabled && isPiCredentialsSyncEnabled,
           let cloudAuth = cloudPiCredentialsURL,
           FileManager.default.fileExists(atPath: cloudAuth.path) {
            let localPi = localPiDirectoryURL
            let localAuth = localPi.appendingPathComponent("auth.json")

            let shouldCopy: Bool
            if !FileManager.default.fileExists(atPath: localAuth.path) {
                shouldCopy = true
            } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: cloudAuth.path),
                      let localAttrs = try? FileManager.default.attributesOfItem(atPath: localAuth.path),
                      let remoteDate = remoteAttrs[.modificationDate] as? Date,
                      let localDate = localAttrs[.modificationDate] as? Date {
                shouldCopy = remoteDate > localDate
            } else {
                shouldCopy = false
            }

            if shouldCopy, let data = try? Data(contentsOf: cloudAuth), !data.isEmpty {
                let localData = try? Data(contentsOf: localAuth)
                if localData != data {
                    try? FileManager.default.createDirectory(at: localPi, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: localAuth.path) {
                        let backupURL = localPi.appendingPathComponent("auth.json.bak")
                        try? FileManager.default.removeItem(at: backupURL)
                        try? FileManager.default.copyItem(at: localAuth, to: backupURL)
                    }
                    try? data.write(to: localAuth, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localAuth.path)
                    didChangeLocally = true
                }
            }
        }

        // 6. Pull OMP configuration
        if isOmpSyncEnabled,
           let cloudOmp = cloudOmpDirectoryURL,
           FileManager.default.fileExists(atPath: cloudOmp.path) {
            let localOmp = localOmpDirectoryURL
            let configFiles = ["models.yml", "config.yml", "models.json", "settings.json", "mcp.json"]
            for file in configFiles {
                let remoteFile = cloudOmp.appendingPathComponent(file)
                guard FileManager.default.fileExists(atPath: remoteFile.path) else { continue }
                let localFile = localOmp.appendingPathComponent(file)

                let shouldCopy: Bool
                if !FileManager.default.fileExists(atPath: localFile.path) {
                    shouldCopy = true
                } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: remoteFile.path),
                          let localAttrs = try? FileManager.default.attributesOfItem(atPath: localFile.path),
                          let remoteDate = remoteAttrs[.modificationDate] as? Date,
                          let localDate = localAttrs[.modificationDate] as? Date {
                    shouldCopy = remoteDate > localDate
                } else {
                    shouldCopy = false
                }

                if shouldCopy, let data = try? Data(contentsOf: remoteFile), !data.isEmpty {
                    let localData = try? Data(contentsOf: localFile)
                    if localData != data {
                        try? FileManager.default.createDirectory(at: localOmp, withIntermediateDirectories: true)
                        if FileManager.default.fileExists(atPath: localFile.path) {
                            let backupURL = localOmp.appendingPathComponent("\(file).bak")
                            try? FileManager.default.removeItem(at: backupURL)
                            try? FileManager.default.copyItem(at: localFile, to: backupURL)
                        }
                        try? data.write(to: localFile, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localFile.path)
                        didChangeLocally = true
                    }
                }
            }
        }

        // 6b. Pull OMP credentials
        if isOmpSyncEnabled && isOmpCredentialsSyncEnabled,
           let cloudCreds = cloudOmpCredentialsURL,
           FileManager.default.fileExists(atPath: cloudCreds.path) {
            if let data = try? Data(contentsOf: cloudCreds), !data.isEmpty {
                if importOmpCredentials(data: data) {
                    didChangeLocally = true
                }
            }
        }

        if didChangeLocally {
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
        }

        return didChangeLocally
    }

    @discardableResult
    func pushLocalState() async -> Bool {
        guard isEnabled, let base = baseDirectoryURL, let app = app else { return false }
        guard checkAvailability() else { return false }

        var didTransferAny = false

        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)

            // 1. Write balances.json
            if let balancesURL = balancesURL {
                let data = try JSONEncoder().encode(app.balances)
                let existing = try? Data(contentsOf: balancesURL)
                if existing != data {
                    try data.write(to: balancesURL, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: balancesURL.path)
                    didTransferAny = true
                }
            }

            // 2. Write settings.json
            if let settingsURL = settingsURL {
                let settings = ICloudSettings(
                    sortMode: app.sortMode.rawValue,
                    mergeIcons: app.mergeIcons,
                    mergedProvider: app.mergedProvider,
                    removedProviders: UserDefaults.standard.stringArray(forKey: "RemovedProviders") ?? [],
                    lastModified: Date(),
                    deviceName: deviceName
                )
                let data = try JSONEncoder().encode(settings)
                let existing = try? Data(contentsOf: settingsURL)
                if existing != data {
                    try data.write(to: settingsURL, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
                    didTransferAny = true
                }
            }

            // 3. Write vault sessions
            if let cloudVault = vaultDirectoryURL {
                try FileManager.default.createDirectory(at: cloudVault, withIntermediateDirectories: true)
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cloudVault.path)

                let localVault = KeychainVault.vaultDir
                if let files = try? FileManager.default.contentsOfDirectory(atPath: localVault.path) {
                    for file in files where file.hasSuffix(".dat") && !file.contains("brave_safe_storage_key") {
                        let localFile = localVault.appendingPathComponent(file)
                        let cloudFile = cloudVault.appendingPathComponent(file)
                        if let data = try? Data(contentsOf: localFile), !data.isEmpty {
                            let cloudData = try? Data(contentsOf: cloudFile)
                            if cloudData != data {
                                try? data.write(to: cloudFile, options: .atomic)
                                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cloudFile.path)
                                didTransferAny = true
                            }
                        }
                    }
                }
            }

            // 4. Write OpenCode configuration
            if isOpenCodeSyncEnabled,
               let cloudOpenCode = cloudOpenCodeURL,
               FileManager.default.fileExists(atPath: localOpenCodeURL.path) {
                let shouldPush: Bool
                if !FileManager.default.fileExists(atPath: cloudOpenCode.path) {
                    shouldPush = true
                } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: cloudOpenCode.path),
                           let localAttrs = try? FileManager.default.attributesOfItem(atPath: localOpenCodeURL.path),
                           let remoteDate = remoteAttrs[.modificationDate] as? Date,
                           let localDate = localAttrs[.modificationDate] as? Date {
                    shouldPush = localDate > remoteDate
                } else {
                    shouldPush = false
                }

                if shouldPush, let data = try? Data(contentsOf: localOpenCodeURL), !data.isEmpty {
                    let cloudData = try? Data(contentsOf: cloudOpenCode)
                    if cloudData != data {
                        try data.write(to: cloudOpenCode, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cloudOpenCode.path)
                        didTransferAny = true
                    }
                }
            }

            // 4b. Write OpenCode credentials if enabled
            if isOpenCodeSyncEnabled && isOpenCodeCredentialsSyncEnabled,
               let cloudCreds = cloudOpenCodeCredentialsURL {
                if let data = exportOpenCodeCredentials(), !data.isEmpty {
                    let cloudData = try? Data(contentsOf: cloudCreds)
                    if cloudData != data {
                        try data.write(to: cloudCreds, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cloudCreds.path)
                        didTransferAny = true
                    }
                }
            }

            // 5. Write Pi configuration
            if isPiSyncEnabled, let cloudPi = cloudPiDirectoryURL {
                let localPi = localPiDirectoryURL
                let configFiles = ["models.json", "settings.json", "mcp.json"]
                var createdCloudDir = false

                for file in configFiles {
                    let localFile = localPi.appendingPathComponent(file)
                    guard FileManager.default.fileExists(atPath: localFile.path) else { continue }
                    let cloudFile = cloudPi.appendingPathComponent(file)

                    let shouldPush: Bool
                    if !FileManager.default.fileExists(atPath: cloudFile.path) {
                        shouldPush = true
                    } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: cloudFile.path),
                               let localAttrs = try? FileManager.default.attributesOfItem(atPath: localFile.path),
                               let remoteDate = remoteAttrs[.modificationDate] as? Date,
                               let localDate = localAttrs[.modificationDate] as? Date {
                        shouldPush = localDate > remoteDate
                    } else {
                        shouldPush = false
                    }

                    if shouldPush, let data = try? Data(contentsOf: localFile), !data.isEmpty {
                        if !createdCloudDir {
                            try? FileManager.default.createDirectory(at: cloudPi, withIntermediateDirectories: true)
                            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cloudPi.path)
                            createdCloudDir = true
                        }
                        let cloudData = try? Data(contentsOf: cloudFile)
                        if cloudData != data {
                            try? data.write(to: cloudFile, options: .atomic)
                            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cloudFile.path)
                            didTransferAny = true
                        }
                    }
                }
            }

            // 5b. Write Pi credentials if enabled
            if isPiSyncEnabled && isPiCredentialsSyncEnabled,
               let cloudAuth = cloudPiCredentialsURL {
                let localAuth = localPiDirectoryURL.appendingPathComponent("auth.json")
                if FileManager.default.fileExists(atPath: localAuth.path),
                   let data = try? Data(contentsOf: localAuth), !data.isEmpty {
                    let cloudData = try? Data(contentsOf: cloudAuth)
                    if cloudData != data {
                        try? data.write(to: cloudAuth, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cloudAuth.path)
                        didTransferAny = true
                    }
                }
            }

            // 6. Write OMP configuration
            if isOmpSyncEnabled, let cloudOmp = cloudOmpDirectoryURL {
                let localOmp = localOmpDirectoryURL
                let configFiles = ["models.yml", "config.yml", "models.json", "settings.json", "mcp.json"]
                var createdCloudDir = false

                for file in configFiles {
                    let localFile = localOmp.appendingPathComponent(file)
                    guard FileManager.default.fileExists(atPath: localFile.path) else { continue }
                    let cloudFile = cloudOmp.appendingPathComponent(file)

                    let shouldPush: Bool
                    if !FileManager.default.fileExists(atPath: cloudFile.path) {
                        shouldPush = true
                    } else if let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: cloudFile.path),
                               let localAttrs = try? FileManager.default.attributesOfItem(atPath: localFile.path),
                               let remoteDate = remoteAttrs[.modificationDate] as? Date,
                               let localDate = localAttrs[.modificationDate] as? Date {
                        shouldPush = localDate > remoteDate
                    } else {
                        shouldPush = false
                    }

                    if shouldPush, let data = try? Data(contentsOf: localFile), !data.isEmpty {
                        if !createdCloudDir {
                            try? FileManager.default.createDirectory(at: cloudOmp, withIntermediateDirectories: true)
                            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cloudOmp.path)
                            createdCloudDir = true
                        }
                        let cloudData = try? Data(contentsOf: cloudFile)
                        if cloudData != data {
                            try? data.write(to: cloudFile, options: .atomic)
                            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cloudFile.path)
                            didTransferAny = true
                        }
                    }
                }
            }

            // 6b. Write OMP credentials if enabled
            if isOmpSyncEnabled && isOmpCredentialsSyncEnabled,
               let cloudCreds = cloudOmpCredentialsURL {
                if let data = exportOmpCredentials(), !data.isEmpty {
                    let cloudData = try? Data(contentsOf: cloudCreds)
                    if cloudData != data {
                        try? data.write(to: cloudCreds, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cloudCreds.path)
                        didTransferAny = true
                    }
                }
            }

            // 7. Write manifest.json
            let pushTime = Date()
            lastPushedDate = pushTime
            if let manifestURL = manifestURL {
                let manifest = ICloudManifest(
                    version: 1,
                    lastModified: pushTime,
                    deviceId: deviceId,
                    deviceName: deviceName,
                    providerCount: app.balances.count,
                    hasOpenCode: isOpenCodeSyncEnabled && FileManager.default.fileExists(atPath: localOpenCodeURL.path),
                    hasPi: isPiSyncEnabled && (
                        FileManager.default.fileExists(atPath: localPiDirectoryURL.appendingPathComponent("models.json").path) ||
                        FileManager.default.fileExists(atPath: localPiDirectoryURL.appendingPathComponent("settings.json").path)
                    ),
                    hasOmp: isOmpSyncEnabled && (
                        FileManager.default.fileExists(atPath: localOmpDirectoryURL.appendingPathComponent("models.yml").path) ||
                        FileManager.default.fileExists(atPath: localOmpDirectoryURL.appendingPathComponent("config.yml").path) ||
                        FileManager.default.fileExists(atPath: localOmpDirectoryURL.appendingPathComponent("models.json").path)
                    ),
                    appBuildTimestamp: AppUpdater.localBuildDate.timeIntervalSince1970
                )
                let data = try JSONEncoder().encode(manifest)
                try data.write(to: manifestURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
            }

            if didTransferAny {
                lastSyncDate = pushTime
                UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
            }
            updateStatusMessage()
            lastError = nil
            return didTransferAny
        } catch {
            transition(to: .failed(error: error.localizedDescription, lastSync: lastSyncDate))
            return false
        }
    }

    func startMonitoring() {
        stopMonitoring()
        guard let base = baseDirectoryURL else { return }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let fd = open(base.path, O_EVTONLY)
        guard fd >= 0 else { return }
        monitorFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isEnabled, !self.isPerformingSync else { return }
                guard let manifestURL = self.manifestURL,
                      let data = try? Data(contentsOf: manifestURL),
                      let remoteManifest = try? JSONDecoder().decode(ICloudManifest.self, from: data) else {
                    return
                }
                guard remoteManifest.deviceId != self.deviceId else { return }

                if let remoteBuild = remoteManifest.appBuildTimestamp {
                    let lastInstall = (UserDefaults.standard.object(forKey: "APIBarLastUpdateInstallTime") as? Date) ?? .distantPast
                    let localTS = max(AppUpdater.localBuildDate.timeIntervalSince1970, lastInstall.timeIntervalSince1970)
                    if remoteBuild > localTS + 60 {
                        Task { @MainActor in
                            await AppUpdater.shared.checkForUpdates(manual: false, forceSilentInstall: true)
                        }
                    }
                }
                await self.pullAndMerge()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        monitorSource = source
        source.resume()
    }

    func stopMonitoring() {
        if let source = monitorSource {
            source.cancel()
            monitorSource = nil
        }
        if monitorFD >= 0 {
            close(monitorFD)
            monitorFD = -1
        }
    }

    func startOpenCodeMonitoring() {
        stopOpenCodeMonitoring()
        guard isEnabled && isOpenCodeSyncEnabled else { return }
        let url = localOpenCodeURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        openCodeMonitorFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isEnabled, self.isOpenCodeSyncEnabled, !self.isPerformingSync else { return }
                self.schedulePush()
                self.startOpenCodeMonitoring()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        openCodeMonitorSource = source
        source.resume()
    }

    func stopOpenCodeMonitoring() {
        if let source = openCodeMonitorSource {
            source.cancel()
            openCodeMonitorSource = nil
        }
        if openCodeMonitorFD >= 0 {
            close(openCodeMonitorFD)
            openCodeMonitorFD = -1
        }
    }

    func startPiMonitoring() {
        stopPiMonitoring()
        guard isEnabled && isPiSyncEnabled else { return }
        let dir = localPiDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        piMonitorFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isEnabled, self.isPiSyncEnabled, !self.isPerformingSync else { return }
                self.schedulePush()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        piMonitorSource = source
        source.resume()
    }

    func stopPiMonitoring() {
        if let source = piMonitorSource {
            source.cancel()
            piMonitorSource = nil
        }
        if piMonitorFD >= 0 {
            close(piMonitorFD)
            piMonitorFD = -1
        }
    }

    func startOmpMonitoring() {
        stopOmpMonitoring()
        guard isEnabled && isOmpSyncEnabled else { return }
        let dir = localOmpDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        ompMonitorFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isEnabled, self.isOmpSyncEnabled, !self.isPerformingSync else { return }
                self.schedulePush()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        ompMonitorSource = source
        source.resume()
    }

    func stopOmpMonitoring() {
        if let source = ompMonitorSource {
            source.cancel()
            ompMonitorSource = nil
        }
        if ompMonitorFD >= 0 {
            close(ompMonitorFD)
            ompMonitorFD = -1
        }
    }
}
