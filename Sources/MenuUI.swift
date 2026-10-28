import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

func providerAccentColor(_ id: String) -> Color {
    switch id {
    case "vertex":
        return Color(red: 26/255.0, green: 115/255.0, blue: 232/255.0) // Google Blue #1A73E8
    case "fireworks":
        return Color(red: 101/255.0, green: 29/255.0, blue: 255/255.0) // Fireworks Violet #651DFF
    case "crowbot":
        return Color(red: 0/255.0, green: 220/255.0, blue: 130/255.0)  // Crowbot Green #00DC82
    case "aistudio":
        return Color(red: 14/255.0, green: 165/255.0, blue: 233/255.0) // Gemini Cyan #0EA5E9
    case "cerebras":
        return Color(red: 240/255.0, green: 91/255.0, blue: 41/255.0)  // Cerebras Orange #F05B29
    case "refuseless":
        return Color(red: 200/255.0, green: 16/255.0, blue: 46/255.0)  // Crimson Red #C8102E
    case "venice":
        return Color(red: 138/255.0, green: 43/255.0, blue: 226/255.0) // Venice Purple #8A2BE2
    default:
        return Color.accentColor
    }
}

// Adapted from CodexBar's MIT-licensed MenuCardView.swift layout:
// 310pt width, 20pt horizontal inset, headline/subheadline header,
// 4pt header lines, 12pt columns, 6pt metric spacing, and a 6pt progress bar.
struct BalanceCardContent: View {
    let balance: Balance
    var status: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(balance.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(status ?? (balance.live ? "Connected · refreshes every 5 minutes" : "Not connected"))
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                        Spacer()
                        Text("API")
                            .font(.footnote)
                            .foregroundStyle(Color.primary)
                    }
                }
                Divider()
            }
            .padding(.horizontal, 20).padding(.top, 7).padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Credits")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.primary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(balance.percent < 10 ? Color.red : providerAccentColor(balance.id))
                            .frame(width: proxy.size.width * min(max(balance.percent / 100, 0), 1))
                    }
                }.frame(height: 6)
                HStack(alignment: .firstTextBaseline) {
                    Text(balance.baseline > 0 ? "\(balance.percentageLabel) left" : "Balance")
                        .font(.footnote)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text(balance.id == "crowbot" && balance.account.isEmpty
                        ? "Connect to read"
                        : (balance.id == "refuseless"
                            ? "\(Int(balance.remaining)) / \(Int(balance.baseline)) credits"
                            : (balance.baseline > 0
                                ? "\(balance.money) / \(balance.baseline.formatted(.currency(code: "USD")))"
                                : "\(balance.money)")
                          ))
                        .font(.footnote)
                        .foregroundStyle(Color.primary)
                }
                Text("Last checked: \(relativeTimeString(for: balance.updated))")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 2)
        }.frame(width: 310, alignment: .leading)
    }
}

struct OverviewCardContent: View {
    @ObservedObject var app: APIBarApp

    var connectedCount: Int {
        app.balances.filter { app.isConnected($0.id) }.count
    }

    var totalUsdRemaining: Double {
        app.balances.filter { $0.id != "refuseless" }.reduce(0.0) { $0 + $1.remaining }
    }

    var totalCreditsRemaining: Double {
        app.balances.filter { $0.id == "refuseless" }.reduce(0.0) { $0 + $1.remaining }
    }

    var totalSummaryText: String {
        let usd = totalUsdRemaining.formatted(.currency(code: "USD"))
        if totalCreditsRemaining > 0 {
            return "\(usd) + \(Int(totalCreditsRemaining)) credits"
        }
        return usd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Overview")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(connectedCount) of \(app.balances.count) connected")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("All Providers")
                            .font(.footnote)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text("Total: \(totalSummaryText)")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                    }
                }
                Divider()
            }
            .padding(.horizontal, 20).padding(.top, 7).padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(app.balances, id: \.id) { balance in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .center, spacing: 6) {
                            Image(nsImage: ProviderIcon.image(balance.id))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                            Text(balance.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Text(balance.money)
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                            Text("(\(balance.percentageLabel))")
                                .font(.footnote)
                                .foregroundStyle(Color.primary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.10))
                                Capsule().fill(balance.percent < 10 ? Color.red : providerAccentColor(balance.id))
                                    .frame(width: proxy.size.width * min(max(balance.percent / 100, 0), 1))
                            }
                        }.frame(height: 5)
                    }
                }

                Divider().padding(.top, 4)

                HStack(alignment: .firstTextBaseline) {
                    Text("Last checked: \(relativeTimeString(for: app.lastRefresh ?? .distantPast))")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Text("Refreshes every 5m")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 6)
        }
        .frame(width: 310, alignment: .leading)
    }
}

@MainActor final class OverviewCard: NSView {
    init(app: APIBarApp) {
        let host = VibrantHost(rootView: OverviewCardContent(app: app))
        super.init(frame: NSRect(x: 0, y: 0, width: 310, height: 175))
        host.frame = bounds
        addSubview(host)
        let height = ceil(host.fittingSize.height)
        frame.size.height = height
        host.frame = bounds; host.autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError() }
    override var allowsVibrancy: Bool { true }
}

@MainActor final class VibrantHost<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { true }
}

@MainActor final class BalanceCard: NSView {
    init(_ balance: Balance, status: String? = nil) {
        let host = VibrantHost(rootView: BalanceCardContent(balance: balance,status:status))
        super.init(frame: NSRect(x: 0, y: 0, width: 310, height: 175))
        host.frame = bounds
        addSubview(host)
        let height = ceil(host.fittingSize.height)
        frame.size.height = height
        host.frame = bounds; host.autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError() }
    override var allowsVibrancy: Bool { true }
}

struct ProviderDropDelegate: DropDelegate {
    let item: Balance
    let app: APIBarApp
    @Binding var draggedItem: Balance?

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem.id != item.id,
              let from = app.balances.firstIndex(where: { $0.id == draggedItem.id }),
              let to = app.balances.firstIndex(where: { $0.id == item.id }),
              from != to else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            app.moveProvider(from: from, to: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}

struct SettingsPane: View {
    @ObservedObject var app: APIBarApp
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var draggedBalance: Balance?
    @State private var showAFMPanel = false
    @State private var selectedKnownProviderID: String = "venice"
    @State private var providerNameInput = ""
    @State private var afmSuccessMessage: String? = nil
    @State private var afmInput = ""
    @State private var isAnalyzingAFM = false
    @State private var afmError: String? = nil
    @State private var afmDraft: AFMDetectedDraft? = nil
    @State private var showRawInput = false
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: BrandMark.appIconImage(size: 32)).resizable().frame(width: 32, height: 32)
                Text("API Bar").font(.title2).fontWeight(.semibold).foregroundStyle(Color.primary)
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(.footnote).foregroundStyle(Color.primary)
            }
            Toggle("Start at Login", isOn: Binding(get: { login }, set: { _ in
                app.toggleLogin(); login = SMAppService.mainApp.status == .enabled
            }))
            .foregroundStyle(Color.primary)
            Toggle("Merge provider icons", isOn: Binding(get: { app.mergeIcons }, set: { app.setMergeIcons($0) }))
            .foregroundStyle(Color.primary)
            Text("Use one menu-bar item and switch providers inside its menu.")
                .font(.footnote).foregroundStyle(Color.primary)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sort Providers")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.sortMode },
                        set: { app.setSortMode($0) }
                    )) {
                        ForEach(ProviderSortMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                Text("Rearrange providers manually or sort them automatically across menus and menu-bar items.")
                    .font(.footnote)
                    .foregroundStyle(Color.primary)
            }
            Divider()
            HStack {
                Button("Choose Brave Profile…") { app.chooseBraveProfile() }
                Text(app.braveProfileStatus)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Connect All from Brave") { app.connectAll() }
                    .disabled(!app.inFlight.isEmpty || app.balances.allSatisfy { app.isConnected($0.id) })
                Spacer()
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(app.balances.enumerated()), id: \.element.id) { index, balance in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 8) {
                            // Draggable three lines handle
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                                .help("Drag to reorder \(balance.name)")

                            Image(nsImage: ProviderIcon.image(balance.id))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                            Text(balance.name)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Button("100%: \(balance.id == "refuseless" ? "\(Int(balance.baseline)) credits" : (balance.baseline > 0 ? balance.baseline.formatted(.currency(code: "USD")) : "—"))") {
                                app.setBaseline(for: index)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .help("Click to edit the 100% baseline reference for \(balance.name)")

                            Button("Connect") { app.connect(balance.id) }
                                .disabled(app.inFlight.contains(balance.id) || app.isConnected(balance.id))
                                .fixedSize(horizontal: true, vertical: false)
                            Button("Disconnect") { app.disconnect(balance.id) }
                                .disabled(app.inFlight.contains(balance.id) || !app.isConnected(balance.id))
                                .fixedSize(horizontal: true, vertical: false)

                            Button {
                                app.removeProvider(id: balance.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(balance.name)")
                        }
                        Text(app.providerStatus[balance.id] ?? "Not connected")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .padding(.leading, 30)
                            .fixedSize(horizontal: false, vertical: true)

                        if balance.dynamicEndpoint != nil {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.secondary)
                                TextField("Admin API Key (Bearer token)", text: Binding(
                                    get: { balance.dynamicAuthHeader ?? "" },
                                    set: { app.setAuthHeader($0, for: balance.id) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))

                                Button("Paste Key") {
                                    if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                                        app.setAuthHeader(clip, for: balance.id)
                                    }
                                }
                                .controlSize(.small)
                            }
                            .padding(.leading, 30)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onDrag {
                        self.draggedBalance = balance
                        return NSItemProvider(object: balance.id as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: ProviderDropDelegate(item: balance, app: app, draggedItem: $draggedBalance))
                }

                let availableToAdd = Balance.initial.filter { initB in !app.balances.contains(where: { $0.id == initB.id }) }
                if !availableToAdd.isEmpty {
                    Menu {
                        ForEach(availableToAdd, id: \.id) { provider in
                            Button(provider.name) {
                                app.addProvider(provider)
                            }
                        }
                    } label: {
                        Label("Add Built-in Provider", systemImage: "plus")
                    }
                    .fixedSize()
                }

                Text("100% reference is automatic from your last payment or grant. Click reference to customize.")
                    .font(.footnote)
                    .foregroundStyle(Color.primary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Add Provider")
                    .font(.headline)
                    .foregroundStyle(Color.primary)

                HStack(spacing: 8) {
                    Picker("", selection: $selectedKnownProviderID) {
                        ForEach(AFMProviderExtractor.verifiedProviders) { meta in
                            Text(meta.name).tag(meta.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    Button("Add") {
                        if let meta = AFMProviderExtractor.verifiedProviders.first(where: { $0.id == selectedKnownProviderID }) {
                            runAddKnownProvider(meta)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(app.balances.contains(where: { $0.id == selectedKnownProviderID }) || isAnalyzingAFM)
                }

                HStack(alignment: .center, spacing: 6) {
                    Text("Use Apple's local AI model to add an unsupported provider.")
                        .font(.footnote)
                        .foregroundStyle(Color.primary)

                    Text("alpha")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.18))
                        .foregroundStyle(Color.blue)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)

                HStack(spacing: 8) {
                    TextField("Provider name (e.g. Venice, Groq, OpenRouter…)", text: $providerNameInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            runAutoAdd()
                        }

                    Button {
                        runAutoAdd()
                    } label: {
                        if isAnalyzingAFM {
                            ProgressView().controlSize(.small)
                            Text("Detecting…")
                        } else {
                            Label("Add and open", systemImage: "arrow.up.right.square")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(providerNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzingAFM)
                }

                if let success = afmSuccessMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                        Text(success).font(.footnote).foregroundStyle(Color.primary)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                }

                if let error = afmError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
                        Text(error).font(.footnote).foregroundStyle(Color.red)
                    }
                    .padding(6)
                }

                DisclosureGroup("Advanced: Paste cURL or JSON response directly", isExpanded: $showRawInput) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $afmInput)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(height: 50)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1))

                        Button("Analyze with AFM") {
                            runRawInputAdd()
                        }
                        .disabled(afmInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzingAFM)

                        if afmDraft != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Detected Configuration")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.primary)

                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                    GridRow {
                                        Text("Name:").font(.footnote).foregroundStyle(Color.primary)
                                        TextField("Provider Name", text: Binding(
                                            get: { afmDraft?.name ?? "" },
                                            set: { afmDraft?.name = $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                    }
                                    GridRow {
                                        Text("Endpoint:").font(.footnote).foregroundStyle(Color.primary)
                                        TextField("Endpoint URL", text: Binding(
                                            get: { afmDraft?.endpoint ?? "" },
                                            set: { afmDraft?.endpoint = $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                    }
                                    GridRow {
                                        Text("JSON Key:").font(.footnote).foregroundStyle(Color.primary)
                                        TextField("JSON Path", text: Binding(
                                            get: { afmDraft?.jsonPath ?? "" },
                                            set: { afmDraft?.jsonPath = $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                    }
                                    GridRow {
                                        Text("Balance:").font(.footnote).foregroundStyle(Color.primary)
                                        HStack {
                                            TextField("Detected Balance", value: Binding(
                                                get: { afmDraft?.detectedBalance ?? 0 },
                                                set: { afmDraft?.detectedBalance = $0 }
                                            ), format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                            Text("100% Baseline:").font(.footnote).foregroundStyle(Color.primary)
                                            TextField("100% Baseline", value: Binding(
                                                get: { afmDraft?.baseline ?? 0 },
                                                set: { afmDraft?.baseline = $0 }
                                            ), format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                        }
                                    }
                                    GridRow {
                                        Text("API Key:").font(.footnote).foregroundStyle(Color.primary)
                                        TextField("Bearer Token / Key (optional)", text: Binding(
                                            get: { afmDraft?.authHeader ?? "" },
                                            set: { afmDraft?.authHeader = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                    }
                                }

                                HStack {
                                    Button("Save & Add to API Bar") {
                                        if let finalDraft = afmDraft {
                                            app.addCustomProvider(finalDraft)
                                            withAnimation {
                                                showRawInput = false
                                                afmInput = ""
                                                afmDraft = nil
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .padding(.top, 4)
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.footnote)
                .foregroundStyle(Color.primary)
            }
            }.padding(24).frame(width: 540, alignment: .leading)
        }
    }

    private func runAddKnownProvider(_ meta: KnownProviderMeta) {
        if let initial = Balance.initial.first(where: { $0.id == meta.id }) {
            app.addProvider(initial)
            self.afmSuccessMessage = "Added \(meta.name) to API Bar."
            return
        }
        isAnalyzingAFM = true
        afmError = nil
        afmSuccessMessage = nil

        Task {
            let clipboard = NSPasteboard.general.string(forType: .string)
            let (draft, dashboardURL, _) = await AFMProviderExtractor.autoAddProvider(
                named: meta.name,
                clipboardText: clipboard,
                openBrowser: true
            )
            await MainActor.run {
                app.addCustomProvider(draft)
                self.afmSuccessMessage = "Added \(draft.name)! Opened dashboard (\(dashboardURL)) in browser."
                self.isAnalyzingAFM = false
            }
        }
    }

    private func runAutoAdd() {
        let name = providerNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isAnalyzingAFM = true
        afmError = nil
        afmSuccessMessage = nil

        Task {
            let clipboard = NSPasteboard.general.string(forType: .string)
            let (draft, dashboardURL, _) = await AFMProviderExtractor.autoAddProvider(
                named: name,
                clipboardText: clipboard,
                openBrowser: true
            )
            await MainActor.run {
                app.addCustomProvider(draft)
                self.afmSuccessMessage = "Added \(draft.name)! Opened dashboard (\(dashboardURL)) in browser."
                self.isAnalyzingAFM = false
                self.providerNameInput = ""
            }
        }
    }

    private func runRawInputAdd() {
        let input = afmInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isAnalyzingAFM = true
        afmError = nil
        afmSuccessMessage = nil
        Task {
            do {
                let draft = try AFMProviderExtractor.extract(from: input)
                await MainActor.run {
                    self.afmDraft = draft
                    self.isAnalyzingAFM = false
                }
            } catch {
                await MainActor.run {
                    self.afmError = error.localizedDescription
                    self.isAnalyzingAFM = false
                }
            }
        }
    }
}
