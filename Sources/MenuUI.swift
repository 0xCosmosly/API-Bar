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

struct ManageProvidersSheet: View {
    @ObservedObject var app: APIBarApp
    @Environment(\.dismiss) private var dismiss

    var allSelected: Bool {
        Balance.initial.allSatisfy { initB in app.balances.contains(where: { $0.id == initB.id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Providers to Add")
                        .font(.headline)
                    Text("Choose which natively supported providers to monitor in API Bar.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .controlSize(.small)
            }

            Divider()

            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(Balance.initial, id: \.id) { provider in
                        let isSelected = app.balances.contains(where: { $0.id == provider.id })
                        Button {
                            if isSelected {
                                app.removeProvider(id: provider.id)
                            } else {
                                app.addProvider(provider)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 16))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                                Image(nsImage: ProviderIcon.image(provider.id))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.primary)
                                    Text(providerSubtitle(for: provider.id))
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
            }
            .frame(height: 270)

            Divider()

            HStack {
                Text("\(app.balances.filter { b in Balance.initial.contains(where: { $0.id == b.id }) }.count) of \(Balance.initial.count) native providers selected")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(20)
        .frame(width: 440, height: 420)
    }

    private func toggleSelectAll() {
        if allSelected {
            for provider in Balance.initial {
                app.removeProvider(id: provider.id)
            }
        } else {
            for provider in Balance.initial {
                if !app.balances.contains(where: { $0.id == provider.id }) {
                    app.addProvider(provider)
                }
            }
        }
    }

    private func providerSubtitle(for id: String) -> String {
        switch id {
        case "vertex": return "Google Cloud Vertex AI & Billing Credits"
        case "fireworks": return "Fireworks AI Serverless Inference Balance"
        case "cerebras": return "Cerebras Inference Platform Credits"
        case "aistudio": return "Google AI Studio Developer Quota"
        case "crowbot": return "Crowbot Chat & API Credits"
        case "refuseless": return "Refuseless DeepSeek Credits"
        default: return "API Balance & Credit Monitor"
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var app: APIBarApp
    let onFinish: () -> Void
    @State private var step = 0
    @State private var login = SMAppService.mainApp.status == .enabled

    var allSelected: Bool {
        Balance.initial.allSatisfy { initB in app.balances.contains(where: { $0.id == initB.id }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: BrandMark.appIconImage(size: 44))
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to API Bar")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Live API credit balances right in your menu bar.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                if step == 0 {
                    welcomeStep
                } else if step == 1 {
                    providersStep
                } else if step == 2 {
                    braveStep
                } else {
                    preferencesStep
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack {
                if step > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
                    }
                    .controlSize(.large)
                }
                Spacer()
                if step < 3 {
                    Button("Continue") {
                        withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Finish Setup") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 540, height: 600)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Track Your Usage, Automatically")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "chart.bar.xaxis", title: "Live Credit Gauges", description: "Monitor remaining balance and automatic 100% baseline usage across Vertex AI, Fireworks, Cerebras, Google AI Studio, Refuseless, and Crowbot.")
                featureRow(icon: "shield.checkered", title: "Zero API Key Hassle", description: "API Bar securely reads authenticated sessions from Brave Browser directly on your device. No credentials ever leave your Mac.")
                featureRow(icon: "menubar.rectangle", title: "Flexible Menu Bar Display", description: "View all providers in a single compact merged gauge or separate icons for each provider.")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    private var providersStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Providers to Monitor")
                        .font(.headline)
                    Text("Choose which natively supported providers to track in API Bar.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .controlSize(.small)
            }

            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(Balance.initial, id: \.id) { provider in
                        let isSelected = app.balances.contains(where: { $0.id == provider.id })
                        Button {
                            if isSelected {
                                app.removeProvider(id: provider.id)
                            } else {
                                app.addProvider(provider)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 16))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                                Image(nsImage: ProviderIcon.image(provider.id))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.primary)
                                    Text(providerSubtitle(for: provider.id))
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)

            HStack {
                Text("\(app.balances.filter { b in Balance.initial.contains(where: { $0.id == b.id }) }.count) of \(Balance.initial.count) native providers selected")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
        }
    }

    private var braveStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect Your Brave Browser")
                .font(.headline)
            Text("Select your Brave profile and connect your active provider sessions in one click.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Brave Profile")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(app.braveProfileStatus)
                            .font(.caption)
                            .foregroundStyle(app.isBraveAccessBlocked ? Color.orange : Color.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.selectedBraveProfileID },
                        set: { app.selectBraveProfile(id: $0) }
                    )) {
                        ForEach(app.availableBraveProfiles) { profile in
                            Text(profile.displayName).tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                if app.isBraveAccessBlocked {
                    HStack {
                        Text("Access is blocked by macOS permission.")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                        Spacer()
                        Button("Grant Access…") { app.chooseBraveProfile() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }

                Divider()

                HStack {
                    Button {
                        app.connectAll()
                    } label: {
                        HStack(spacing: 6) {
                            if !app.inFlight.isEmpty {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Connect All from Brave")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!app.inFlight.isEmpty)

                    Spacer()

                    let connectedCount = app.balances.filter { app.isConnected($0.id) }.count
                    Text("\(connectedCount) of \(app.balances.count) connected")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(app.balances, id: \.id) { balance in
                        HStack(spacing: 10) {
                            Image(nsImage: ProviderIcon.image(balance.id))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            Text(balance.name)
                                .font(.subheadline)
                            Spacer()
                            if app.isConnected(balance.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                                Text(balance.baseline > 0 ? "100%: \(balance.id == "refuseless" ? "\(Int(balance.baseline)) credits" : balance.baseline.formatted(.currency(code: "USD")))" : "Connected")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            } else {
                                Text("Not connected")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                    }
                }
            }
            .frame(maxHeight: 140)
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure Preferences")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Start at Login", isOn: Binding(get: { login }, set: { _ in
                    app.toggleLogin(); login = SMAppService.mainApp.status == .enabled
                }))
                .font(.subheadline)

                Divider()

                Toggle("Merge provider icons into a single menu bar item", isOn: Binding(get: { app.mergeIcons }, set: { app.setMergeIcons($0) }))
                .font(.subheadline)
                Text("Keeps your menu bar clean by displaying one compact status icon.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sort Providers")
                            .font(.subheadline)
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
                        .frame(width: 240)
                    }
                    Text("Total Amount is selected by default to highlight your highest-balance providers.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            Text("You can change these options anytime from Settings in the menu bar.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            for provider in Balance.initial {
                app.removeProvider(id: provider.id)
            }
        } else {
            for provider in Balance.initial {
                if !app.balances.contains(where: { $0.id == provider.id }) {
                    app.addProvider(provider)
                }
            }
        }
    }

    private func providerSubtitle(for id: String) -> String {
        switch id {
        case "vertex": return "Google Cloud Vertex AI & Billing Credits"
        case "fireworks": return "Fireworks AI Serverless Inference Balance"
        case "cerebras": return "Cerebras Inference Platform Credits"
        case "aistudio": return "Google AI Studio Developer Quota"
        case "crowbot": return "Crowbot Chat & API Credits"
        case "refuseless": return "Refuseless DeepSeek Credits"
        default: return "API Balance & Credit Monitor"
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsPane: View {
    @ObservedObject var app: APIBarApp
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var draggedBalance: Balance?
    @State private var showAFMPanel = true
    @State private var showManageProvidersSheet = false
    @State private var selectedKnownProviderID: String = "venice"
    @State private var providerNameInput = ""
    @State private var afmSuccessMessage: String? = nil
    @State private var afmInput = ""
    @State private var isAnalyzingAFM = false
    @State private var afmError: String? = nil
    @State private var afmDraft: AFMDetectedDraft? = nil
    @State private var showRawInput = false

    var allNativeSelected: Bool {
        Balance.initial.allSatisfy { initB in app.balances.contains(where: { $0.id == initB.id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Header
            HStack {
                HStack(spacing: 10) {
                    Image(nsImage: BrandMark.appIconImage(size: 32)).resizable().frame(width: 32, height: 32)
                    Text("API Bar").font(.title2).fontWeight(.semibold).foregroundStyle(Color.primary)
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(.footnote).foregroundStyle(Color.secondary)
                }
                Spacer()
                Button {
                    app.showOnboarding()
                } label: {
                    Label("Welcome Tour…", systemImage: "sparkles")
                }
                .controlSize(.small)
            }

            // MARK: - Preferences Card
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Start at Login", isOn: Binding(get: { login }, set: { _ in
                    app.toggleLogin(); login = SMAppService.mainApp.status == .enabled
                }))
                .foregroundStyle(Color.primary)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Merge provider icons", isOn: Binding(get: { app.mergeIcons }, set: { app.setMergeIcons($0) }))
                        .foregroundStyle(Color.primary)
                    Text("Use one menu-bar item and switch providers inside its menu.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sort Providers")
                            .font(.subheadline)
                            .fontWeight(.medium)
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
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            // MARK: - Brave Browser Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Brave Browser Session")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if app.isBraveAccessBlocked {
                        Text("Action Required")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    } else {
                        Text("Connected")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }

                if app.isBraveAccessBlocked {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.orange)
                            Text("Brave profile access is blocked by macOS.")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        Text("Grant folder access or Full Disk Access so API Bar can read your session cookies.")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        HStack(spacing: 8) {
                            Button("Grant Folder Access…") { app.chooseBraveProfile() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button("Full Disk Access…") { app.openFullDiskAccessSettings() }
                                .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Profile")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.primary)
                        Text(app.braveProfileStatus)
                            .font(.caption)
                            .foregroundStyle(app.isBraveAccessBlocked ? Color.orange : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.selectedBraveProfileID },
                        set: { app.selectBraveProfile(id: $0) }
                    )) {
                        ForEach(app.availableBraveProfiles) { profile in
                            Text(profile.displayName).tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                Divider()

                HStack {
                    Button("Choose Brave Profile…") { app.chooseBraveProfile() }
                        .controlSize(.small)
                    Spacer()
                    Button {
                        app.connectAll()
                    } label: {
                        HStack(spacing: 6) {
                            if !app.inFlight.isEmpty {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Connect All from Brave")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!app.inFlight.isEmpty || app.balances.allSatisfy { app.isConnected($0.id) })
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            Divider()

            // MARK: - Providers Header (Pinned)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitored Providers (\(app.balances.count))")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("Drag ≡ to reorder. 100% baseline updates automatically from payments.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()

                Button(allNativeSelected ? "Deselect All" : "Select All") {
                    if allNativeSelected {
                        for b in Balance.initial { app.removeProvider(id: b.id) }
                    } else {
                        for b in Balance.initial {
                            if !app.balances.contains(where: { $0.id == b.id }) {
                                app.addProvider(b)
                            }
                        }
                    }
                }
                .controlSize(.small)

                Button {
                    showManageProvidersSheet = true
                } label: {
                    Label("Select Providers…", systemImage: "checklist")
                }
                .controlSize(.small)
            }

            // MARK: - Scrollable Provider List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    if app.balances.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.secondary)
                            Text("No providers added yet.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                            Button("Select Providers to Add…") {
                                showManageProvidersSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
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
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor).opacity(0.6)))
                            .contentShape(Rectangle())
                            .onDrag {
                                self.draggedBalance = balance
                                return NSItemProvider(object: balance.id as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: ProviderDropDelegate(item: balance, app: app, draggedItem: $draggedBalance))
                        }
                    }

                    // AFM / Custom Provider Section
                    Divider().padding(.vertical, 4)

                    DisclosureGroup(isExpanded: $showAFMPanel) {
                        VStack(alignment: .leading, spacing: 10) {
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
                            .padding(.top, 2)

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
                        .padding(.top, 6)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.subheadline)
                            Text("Add Custom / Unsupported Provider (Apple Local AI)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showManageProvidersSheet) {
            ManageProvidersSheet(app: app)
                .frame(width: 480, height: 420)
                .padding(20)
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
