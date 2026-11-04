import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

func providerAccentColor(_ id: String) -> Color {
    switch id {
    case "vertex", "aistudio":
        return Color(red: 26/255.0, green: 115/255.0, blue: 232/255.0) // Google Blue #1A73E8
    case "fireworks":
        return Color(red: 212/255.0, green: 100/255.0, blue: 0/255.0)   // Deep Orange #D46400
    case "crowbot":
        return Color(red: 13/255.0, green: 115/255.0, blue: 60/255.0)  // Deep Emerald #0D733C
    case "cerebras":
        return Color(red: 220/255.0, green: 50/255.0, blue: 30/255.0)  // Cerebras Red-Orange #DC321E
    case "refuseless":
        return Color(red: 200/255.0, green: 16/255.0, blue: 46/255.0)  // Crimson Red #C8102E
    case "venice":
        return Color(red: 123/255.0, green: 31/255.0, blue: 162/255.0) // Venice Purple #7B1FA2
    case "lutheos":
        return Color(red: 173/255.0, green: 79/255.0, blue: 44/255.0)  // Lutheos Terracotta #AD4F2C
    default:
        return Color.accentColor
    }
}

func percentageColor(for percent: Double) -> Color {
    if percent >= 80 {
        return Color.green
    } else if percent >= 20 {
        return Color(NSColor.secondaryLabelColor)
    } else if percent >= 10 {
        return Color(nsColor: percentageYellowNSColor)
    } else {
        return Color.red
    }
}

// MARK: - Paper Design System Components

struct PaperProviderBadge: View {
    let id: String
    let name: String
    var size: CGFloat = 24
    var cornerRadius: CGFloat = 6

    var monogram: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    var accent: Color {
        providerAccentColor(id)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color(red: 209/255.0, green: 209/255.0, blue: 214/255.0), lineWidth: 0.8)

            if ProviderIcon.hasMask(for: id) {
                Image(nsImage: ProviderIcon.image(id))
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(accent)
                    .frame(width: size * 0.65, height: size * 0.65)
            } else {
                Text(monogram)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
    }
}

struct PaperCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

struct PaperWhiteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(isEnabled ? 0.15 : 0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .contentShape(Rectangle())
    }
}

struct PaperPillButtonStyle: ButtonStyle {
    var tintColor: Color = .accentColor
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(tintColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(tintColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(tintColor.opacity(0.24), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .contentShape(Rectangle())
    }
}

struct PaperProminentButtonStyle: ButtonStyle {
    var tintColor: Color = .accentColor
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isEnabled ? tintColor : Color(NSColor.separatorColor).opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isEnabled ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .contentShape(Rectangle())
    }
}

// Adapted from CodexBar's MIT-licensed MenuCardView.swift layout:
// 340pt width, 20pt horizontal inset, headline/subheadline header,
// 4pt header lines, 12pt columns, 6pt metric spacing, and a 7pt progress bar.
struct BalanceCardContent: View {
    let balance: Balance
    var status: String? = nil

    var displayStatus: String {
        if let status, !status.isEmpty {
            return status
                .replacingOccurrences(of: "Connected · refreshes every 5 minutes", with: "Connected · refreshes every 5 min")
                .replacingOccurrences(of: "Connected · refreshes every 5m", with: "Connected · refreshes every 5 min")
                .replacingOccurrences(of: "refreshes every 5 minutes", with: "refreshes every 5 min")
                .replacingOccurrences(of: "refreshes every 5m", with: "refreshes every 5 min")
        }
        return balance.live ? "Connected · refreshes every 5 min" : "Not connected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                PaperProviderBadge(id: balance.id, name: balance.name, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(balance.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(balance.live ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(displayStatus)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if balance.baseline > 0 {
                    let tint = percentageColor(for: balance.percent)
                    Text(balance.percentageLabel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(balance.percent >= 80 || balance.percent < 20 ? 0.14 : 0.08)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()

            // Metric Hero
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(balance.money)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    if balance.baseline > 0 {
                        Text("of \(balance.baseline.formatted(.currency(code: "USD")))")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(providerAccentColor(balance.id))
                            .frame(width: proxy.size.width * min(max(balance.percent / 100, 0), 1))
                    }
                }
                .frame(height: 7)

                if let pacing = balance.pacingMessage {
                    Text(pacing)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)

            Divider()

            // Footer
            HStack(alignment: .center, spacing: 6) {
                Text("Last checked: \(relativeTimeString(for: balance.updated))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .layoutPriority(0)
                Spacer(minLength: 6)
                if !balance.account.isEmpty {
                    Text(balance.account)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(width: 365, alignment: .leading)
    }
}

struct OverviewCardContent: View {
    @ObservedObject var app: APIBarApp

    var connectedCount: Int {
        app.balances.filter { app.isConnected($0.id) }.count
    }

    var totalUsdRemaining: Double {
        app.balances.reduce(0.0) { $0 + $1.remaining }
    }

    var totalBaseline: Double {
        app.balances.reduce(0.0) { $0 + $1.baseline }
    }

    var totalPercent: Double {
        guard totalBaseline > 0 else { return 0 }
        return (totalUsdRemaining / totalBaseline) * 100
    }

    var totalSummaryText: String {
        totalUsdRemaining.formatted(.currency(code: "USD"))
    }

    var aggregatePercentText: String {
        guard totalBaseline > 0 else { return "—" }
        if totalPercent > 0 && totalPercent < 1 { return "<1%" }
        return "\(Int(floor(totalPercent)))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hero Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(totalSummaryText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("remaining")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if totalBaseline > 0 {
                        let tint = percentageColor(for: totalPercent)
                        Text(aggregatePercentText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(tint.opacity(totalPercent >= 80 || totalPercent < 20 ? 0.14 : 0.08)))
                    }
                }
                HStack {
                    Text("\(connectedCount) of \(app.balances.count) connected · All active providers")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()

            // Provider Rows
            VStack(alignment: .leading, spacing: 8) {
                ForEach(app.balances, id: \.id) { balance in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 8) {
                            PaperProviderBadge(id: balance.id, name: balance.name, size: 22)

                            Text(balance.name)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Color.primary)

                            Spacer()

                            Text(balance.money)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Color.primary)

                            let tint = percentageColor(for: balance.percent)
                            Text(balance.percentageLabel)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                                .frame(minWidth: 34, alignment: .trailing)
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill(providerAccentColor(balance.id))
                                    .frame(width: proxy.size.width * min(max(balance.percent / 100, 0), 1))
                            }
                        }
                        .frame(height: 5.5)

                        if let pacing = balance.pacingMessage {
                            Text(pacing)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.03)))
                }
            }
            .padding(.horizontal, 16)

            Divider()

            // Footer
            HStack(alignment: .center) {
                Text("Last checked: \(relativeTimeString(for: app.lastRefresh ?? .distantPast))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Text("Refreshes every 5 min")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(width: 365, alignment: .leading)
    }
}

@MainActor final class OverviewCard: NSView {
    init(app: APIBarApp) {
        let host = VibrantHost(rootView: OverviewCardContent(app: app))
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 185))
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
        let host = VibrantHost(rootView: BalanceCardContent(balance: balance, status: status))
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 185))
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
        !app.balances.isEmpty && Balance.initial.allSatisfy { initB in app.balances.contains(where: { $0.id == initB.id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Providers to Add")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Choose which natively supported providers to monitor in API Bar.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .buttonStyle(PaperWhiteButtonStyle())
            }

            Divider().opacity(0.6)

            ScrollView(.vertical, showsIndicators: false) {
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

                                PaperProviderBadge(id: provider.id, name: provider.name, size: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.primary)
                                    Text(providerSubtitle(for: provider.id))
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()

                                if isSelected {
                                    Text("Selected")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.025))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().opacity(0.6)

            HStack {
                Text("\(app.balances.filter { b in Balance.initial.contains(where: { $0.id == b.id }) }.count) of \(Balance.initial.count) native providers selected")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PaperProminentButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
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
        case "refuseless": return "Refuseless Balance"
        case "lutheos": return "Lutheos Private Inference Balance"
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
        !app.balances.isEmpty && Balance.initial.allSatisfy { initB in app.balances.contains(where: { $0.id == initB.id }) }
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
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
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
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack {
                if step > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                }
                Spacer()
                if step < 3 {
                    Button("Continue") {
                        withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                    }
                    .buttonStyle(PaperProminentButtonStyle())
                } else {
                    Button("Finish Setup") {
                        if login && SMAppService.mainApp.status != .enabled {
                            app.toggleLogin()
                        }
                        onFinish()
                    }
                    .buttonStyle(PaperProminentButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 22)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 540, height: 560)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Track Your Usage, Automatically")
                .font(.title3)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "chart.bar.xaxis", title: "Live Credit Gauges", description: "Monitor remaining balance and automatic 100% baseline usage across Vertex AI, Fireworks, Cerebras, Google AI Studio, Refuseless, Lutheos, and Crowbot.")
                featureRow(icon: "shield.checkered", title: "Zero API Key Hassle", description: "API Bar securely reads authenticated sessions from \(app.browserName) Browser directly on your device. No credentials ever leave your Mac.")
                featureRow(icon: "menubar.rectangle", title: "Flexible Menu Bar Display", description: "View all providers in a single compact merged gauge or separate icons for each provider.")
                featureRow(icon: "lock.shield", title: "100% Private & Local", description: "Zero telemetry or external servers. All credentials stay strictly in your local macOS Keychain.")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)

            Text("Setup takes under a minute. Next, choose which providers you want to monitor.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
    }

    private var providersStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Providers to Monitor")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Choose which natively supported providers to track in API Bar.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .buttonStyle(PaperWhiteButtonStyle())
            }

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

                            PaperProviderBadge(id: provider.id, name: provider.name, size: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text(providerSubtitle(for: provider.id))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()

                            if isSelected {
                                Text("Selected")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.025))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("\(app.balances.filter { b in Balance.initial.contains(where: { $0.id == b.id }) }.count) of \(Balance.initial.count) native providers selected")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Spacer()
                Text("Custom endpoints can be added in Settings")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    @ViewBuilder
    private var braveStepPermissionNotice: some View {
        if app.isBraveAccessBlocked {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text("\(app.browserName) session access requires macOS permission.")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text("Grant Full Disk Access or choose Folder Access Only for instant access.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                HStack(spacing: 8) {
                    Button(app.braveAccessKind == .fullDisk ? "Full Disk Access Granted ✓" : "Grant Full Disk Access") {
                        app.openFullDiskAccessSettings()
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                    .disabled(app.braveAccessKind == .fullDisk)

                    Button(app.braveAccessKind == .folder ? "Folder Access Active ✓" : "Folder Access Only") {
                        app.chooseBraveProfile()
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                    .disabled(app.braveAccessKind == .folder)

                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 4)

                    Button("Relaunch API Bar") {
                        app.relaunchApp()
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.25), lineWidth: 1))
        }
    }

    private var braveStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Your \(app.browserName) Browser")
                .font(.headline)
            Text("Select your \(app.browserName) profile and connect your active provider sessions in one click.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(app.browserName) Profile")
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

                braveStepPermissionNotice

                Divider().opacity(0.6)

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
                            Text("Connect All from \(app.browserName)")
                        }
                    }
                    .buttonStyle(PaperProminentButtonStyle())
                    .disabled(!app.inFlight.isEmpty)

                    Spacer()

                    let connectedCount = app.balances.filter { app.isConnected($0.id) }.count
                    Text("\(connectedCount) of \(app.balances.count) connected")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)

            VStack(spacing: 6) {
                ForEach(app.balances, id: \.id) { balance in
                    HStack(spacing: 10) {
                        PaperProviderBadge(id: balance.id, name: balance.name, size: 22)
                        Text(balance.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if app.isConnected(balance.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text(balance.baseline > 0 ? "100%: \(balance.baseline.formatted(.currency(code: "USD")))" : "Connected")
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
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.025)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                }
            }
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configure Preferences")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Start at Login", isOn: Binding(get: { login }, set: { _ in
                    app.toggleLogin(); login = SMAppService.mainApp.status == .enabled
                }))
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Merge provider icons into a single menu bar item", isOn: Binding(get: { app.mergeIcons }, set: { app.setMergeIcons($0) }))
                        .font(.subheadline)
                    Text("Keeps your menu bar clean by displaying one compact status icon.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { app.iCloudSyncEnabled },
                        set: { app.setICloudSyncEnabled($0) }
                    ))
                    .font(.subheadline)
                    Text("Keep your providers, custom endpoints, and baselines up to date across all your Macs.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)

                    if app.iCloudSyncEnabled {
                        VStack(alignment: .leading, spacing: 3) {
                            Toggle("Sync OpenCode Configuration (Optional)", isOn: Binding(
                                get: { app.isOpenCodeSyncEnabled },
                                set: { app.setOpenCodeSyncEnabled($0) }
                            ))
                            .font(.subheadline)

                            Text("Optional. Syncs models and providers (~/.config/opencode/opencode.json).")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)

                            if app.isOpenCodeSyncEnabled {
                                Toggle("Sync API Keys & Credentials", isOn: Binding(
                                    get: { app.isOpenCodeCredentialsSyncEnabled },
                                    set: { app.setOpenCodeCredentialsSyncEnabled($0) }
                                ))
                                .font(.caption)
                                .padding(.leading, 16)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.leading, 8)
                    }
                }

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
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))

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
        case "refuseless": return "Refuseless Balance"
        case "lutheos": return "Lutheos Private Inference Balance"
        default: return "API Balance & Credit Monitor"
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsPane: View {
    @ObservedObject var app: APIBarApp
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var icloud = ICloudSync.shared
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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
            // MARK: - Header
            HStack {
                HStack(spacing: 10) {
                    Image(nsImage: BrandMark.appIconImage(size: 32)).resizable().frame(width: 32, height: 32)
                    Text("API Bar").font(.title2).fontWeight(.bold).foregroundStyle(Color.primary)
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(.subheadline).foregroundStyle(Color.secondary)
                }
                Spacer()
                Button {
                    app.showChangelog()
                } label: {
                    Label("Changelog…", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(PaperWhiteButtonStyle())

                Button {
                    app.showOnboarding()
                } label: {
                    Label("Welcome Tour…", systemImage: "sparkles")
                }
                .buttonStyle(PaperWhiteButtonStyle())

                Button {
                    Task { await updater.checkForUpdates(manual: true) }
                } label: {
                    if updater.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(updater.updateAvailable ? "Update Available!" : "Check for Updates…", systemImage: updater.updateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(PaperWhiteButtonStyle())
                .disabled(updater.isChecking || updater.isInstalling)
            }

            if updater.updateAvailable, let ver = updater.latestVersion {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Bar v\(ver) is available!")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(updater.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Button("View Release Notes & Install…") {
                        updater.showUpdateWindow()
                    }
                    .buttonStyle(PaperProminentButtonStyle())
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
            }

            // MARK: - Preferences Card
            VStack(alignment: .leading, spacing: 14) {
                Text("Preferences")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.primary)

                Toggle("Start at Login", isOn: Binding(get: { login }, set: { _ in
                    app.toggleLogin(); login = SMAppService.mainApp.status == .enabled
                }))
                .font(.body)
                .foregroundStyle(Color.primary)

                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Merge provider icons", isOn: Binding(get: { app.mergeIcons }, set: { app.setMergeIcons($0) }))
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Text("Use one menu-bar item and switch providers inside its menu.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sort Providers")
                            .font(.body)
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
                        .frame(width: 270)
                    }
                    Text("Rearrange providers manually or sort them automatically across menus and menu-bar items.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)

            // MARK: - iCloud Sync Card
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("iCloud Sync")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if !icloud.isAvailable {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text("Unavailable")
                                .font(.system(size: 11.5, weight: .bold))
                        }
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                    } else if icloud.isEnabled {
                        HStack(spacing: 4) {
                            if icloud.isSyncing {
                                ProgressView().controlSize(.mini)
                            } else {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                            }
                            Text(icloud.isSyncing ? "Syncing…" : "Active")
                                .font(.system(size: 11.5, weight: .bold))
                        }
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                    } else {
                        Text("Off")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { icloud.isEnabled },
                        set: { app.setICloudSyncEnabled($0) }
                    ))
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .disabled(!icloud.isAvailable)

                    Text("Keep your providers, custom endpoints, baseline targets, and sessions synchronized across all your Macs via iCloud Drive.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                if icloud.isEnabled {
                    Divider().opacity(0.6)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Sync OpenCode Configuration (Optional)", isOn: Binding(
                            get: { icloud.isOpenCodeSyncEnabled },
                            set: { icloud.setOpenCodeSyncEnabled($0) }
                        ))
                        .font(.body)
                        .foregroundStyle(Color.primary)

                        Text("Optional. Syncs models and providers configured in OpenCode (~/.config/opencode/opencode.json) across devices via iCloud Drive.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)

                        if icloud.isOpenCodeSyncEnabled {
                            VStack(alignment: .leading, spacing: 3) {
                                Toggle("Sync API Keys & Credentials", isOn: Binding(
                                    get: { icloud.isOpenCodeCredentialsSyncEnabled },
                                    set: { icloud.setOpenCodeCredentialsSyncEnabled($0) }
                                ))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.primary)

                                Text("Synchronizes your OpenCode stored API keys and authentication tokens via your private iCloud vault so models connect immediately without re-authenticating.")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            .padding(.leading, 18)
                            .padding(.top, 4)
                        }
                    }

                    Divider().opacity(0.6)

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(icloud.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        Button {
                            app.syncICloudNow()
                        } label: {
                            HStack(spacing: 5) {
                                if icloud.isSyncing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("Sync Now")
                            }
                        }
                        .buttonStyle(PaperWhiteButtonStyle())
                        .disabled(icloud.isSyncing || !icloud.isAvailable)
                    }
                }

                if !icloud.isAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text("iCloud Drive is not available. Turn on iCloud Drive in macOS System Settings to synchronize across devices.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.10)))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)

            browserSessionCard

            // MARK: - Providers Card
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monitored Providers (\(app.balances.count))")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                        Text("Drag ≡ to reorder. 100% baseline updates automatically from payments.")
                            .font(.subheadline)
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
                    .buttonStyle(PaperWhiteButtonStyle())

                    Button {
                        showManageProvidersSheet = true
                    } label: {
                        Label("Select Providers…", systemImage: "checklist")
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                }

                // MARK: - Providers List
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
                            .buttonStyle(PaperProminentButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ForEach(Array(app.balances.enumerated()), id: \.element.id) { index, balance in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center, spacing: 10) {
                                    // Draggable three lines handle
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.secondary)
                                        .frame(width: 18, height: 18)
                                        .contentShape(Rectangle())
                                        .help("Drag to reorder \(balance.name)")
                                        .onDrag {
                                            self.draggedBalance = balance
                                            return NSItemProvider(object: balance.id as NSString)
                                        }

                                    PaperProviderBadge(id: balance.id, name: balance.name, size: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(balance.name)
                                            .font(.system(size: 14.5, weight: .semibold))
                                            .foregroundStyle(Color.primary)
                                        HStack(spacing: 5) {
                                            if app.isConnected(balance.id) {
                                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                            } else if app.inFlight.contains(balance.id) {
                                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                            } else {
                                                Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                                            }
                                            Text(app.providerStatus[balance.id] ?? "Not connected")
                                                .font(.system(size: 12))
                                                .foregroundStyle(app.isConnected(balance.id) ? Color.secondary : (app.inFlight.contains(balance.id) ? Color.orange : Color.secondary.opacity(0.8)))
                                        }
                                    }

                                    Spacer()

                                    Button("100%: \(balance.baseline.formatted(.currency(code: "USD")))") {
                                        app.setBaseline(for: index)
                                    }
                                    .buttonStyle(PaperPillButtonStyle(tintColor: .accentColor))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .help("Click to edit the 100% baseline reference for \(balance.name)")

                                    if app.isConnected(balance.id) {
                                        Button("Disconnect") { app.disconnect(balance.id) }
                                            .buttonStyle(PaperPillButtonStyle(tintColor: .red))
                                            .disabled(app.inFlight.contains(balance.id))
                                            .fixedSize(horizontal: true, vertical: false)
                                    } else {
                                        Button("Connect") { app.connect(balance.id) }
                                            .buttonStyle(PaperWhiteButtonStyle())
                                            .disabled(app.inFlight.contains(balance.id))
                                            .fixedSize(horizontal: true, vertical: false)
                                    }

                                    Button {
                                        app.removeProvider(id: balance.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.secondary)
                                            .frame(width: 22, height: 22)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove \(balance.name)")
                                }

                                if balance.dynamicEndpoint != nil {
                                    HStack(spacing: 8) {
                                        Image(systemName: "key.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.secondary)
                                        TextField("Admin API Key (Bearer token)", text: Binding(
                                            get: { balance.dynamicAuthHeader ?? "" },
                                            set: { app.setAuthHeader($0, for: balance.id) }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12.5, design: .monospaced))

                                        Button("Paste Key") {
                                            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                                                app.setAuthHeader(clip, for: balance.id)
                                            }
                                        }
                                        .buttonStyle(PaperWhiteButtonStyle())
                                    }
                                    .padding(.leading, 38)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.025)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                            .onDrop(of: [UTType.text], delegate: ProviderDropDelegate(item: balance, app: app, draggedItem: $draggedBalance))
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)

            // MARK: - AFM / Custom Provider Card
            VStack(alignment: .leading, spacing: 10) {
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
                            .buttonStyle(PaperWhiteButtonStyle())
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
                            .buttonStyle(PaperProminentButtonStyle())
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
                                .buttonStyle(PaperProminentButtonStyle())
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
                                            .buttonStyle(PaperProminentButtonStyle())
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
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                        Text("Add Custom / Unsupported Provider (Apple Local AI)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.primary)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)

            Divider().opacity(0.6)

            HStack {
                Text("100% reference is automatic from your last payment or grant. Click reference to customize.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showManageProvidersSheet) {
            ManageProvidersSheet(app: app)
        }
        .onAppear {
            app.refreshBraveProfiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshBraveProfiles()
        }
    }

    @ViewBuilder
    private var browserAccessBadge: some View {
        if app.isBraveAccessBlocked {
            HStack(spacing: 5) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("Action Required")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
        } else if app.braveAccessKind == .fullDisk {
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Full Disk Access")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.green.opacity(0.12)))
        } else {
            HStack(spacing: 5) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("Folder Access")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.blue)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.blue.opacity(0.12)))
        }
    }

    @ViewBuilder
    private var browserBlockedWarning: some View {
        if app.isBraveAccessBlocked {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text("\(app.browserName) session access requires macOS permission.")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                Text("If you already turned Full Disk Access ON in macOS System Settings, click Relaunch API Bar to apply. You can also use Folder Access Only for instant, permanent access without System Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                HStack(spacing: 8) {
                    Button(app.braveAccessKind == .fullDisk ? "Full Disk Access Granted ✓" : "Grant Full Disk Access") {
                        app.openFullDiskAccessSettings()
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                    .disabled(app.braveAccessKind == .fullDisk)

                    Button(app.braveAccessKind == .folder ? "Folder Access Active ✓" : "Folder Access Only") {
                        app.chooseBraveProfile()
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                    .disabled(app.braveAccessKind == .folder)

                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 4)

                    Button("Relaunch API Bar") {
                        app.relaunchApp()
                    }
                    .buttonStyle(PaperWhiteButtonStyle())
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.25), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var browserSessionActions: some View {
        let allConnected = !app.inFlight.isEmpty || app.balances.allSatisfy { app.isConnected($0.id) }
        HStack(spacing: 8) {
            Button(app.braveAccessKind == .fullDisk ? "Full Disk Access Granted ✓" : "Grant Full Disk Access") {
                app.openFullDiskAccessSettings()
            }
            .buttonStyle(PaperWhiteButtonStyle())
            .disabled(app.braveAccessKind == .fullDisk)

            Button(app.braveAccessKind == .folder ? "Folder Access Active ✓" : "Folder Access Only") {
                app.chooseBraveProfile()
            }
            .buttonStyle(PaperWhiteButtonStyle())
            .disabled(app.braveAccessKind == .folder)

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Button("Relaunch API Bar") {
                app.relaunchApp()
            }
            .buttonStyle(PaperWhiteButtonStyle())

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
                    Text("Connect All from \(app.browserName)")
                }
            }
            .buttonStyle(PaperProminentButtonStyle())
            .disabled(allConnected)
        }
    }

    @ViewBuilder
    private var browserSessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("\(app.browserName) Browser Session")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.primary)
                Spacer()
                browserAccessBadge
            }

            browserBlockedWarning

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active Profile")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                    Text(app.braveProfileStatus)
                        .font(.subheadline)
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

            Divider().opacity(0.6)

            browserSessionActions
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
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
