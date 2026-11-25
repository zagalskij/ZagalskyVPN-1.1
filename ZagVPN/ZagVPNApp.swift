import NetworkExtension
import SwiftUI

@main
@MainActor
struct ZagVPNApp: App {
    @StateObject private var vpn = VPNManager()
    @StateObject private var personalization = PersonalizationStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if personalization.profile != nil {
                    ContentView(manager: vpn, personalization: personalization)
                } else {
                    PersonalizationEditor(store: personalization, isRequired: true)
                }
            }
            .preferredColorScheme(.dark)
            .tint(VPNTheme.accent)
        }
    }
}

enum VPNTheme {
    static let background = Color(red: 0.025, green: 0.045, blue: 0.085)
    static let surface = Color(red: 0.06, green: 0.09, blue: 0.15)
    static let accent = Color(red: 0.26, green: 0.65, blue: 1)
    static let connected = Color(red: 0.36, green: 0.96, blue: 0.72)
    static let muted = Color.white.opacity(0.65)
    static let border = Color.white.opacity(0.11)
    static let warning = Color(red: 1, green: 0.65, blue: 0.58)
}

@MainActor
struct ContentView: View {
    @ObservedObject var manager: VPNManager
    @ObservedObject var personalization: PersonalizationStore
    @State private var profileEditor: ProfileEditor.Input?
    @State private var showPersonalization = false
    @State private var confirmDeletion = false
    @State private var actionError: String?

    var body: some View {
        ZStack {
            VPNTheme.background.ignoresSafeArea()
            RadialGradient(
                colors: [VPNTheme.accent.opacity(0.18), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 340
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    if let greeting = personalization.greeting {
                        Text(greeting)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityAddTraits(.isHeader)
                    }
                    connectionButton
                    connectionStatus
                    if let message = actionError ?? manager.errorMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(VPNTheme.warning)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    configurationCard
                    Text("Developed by Anatoly Zagalsky © 2026")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await manager.load() }
        .sheet(isPresented: $showPersonalization) {
            PersonalizationEditor(store: personalization, isRequired: false)
        }
        .sheet(item: $profileEditor) { input in
            ProfileEditor(input: input) { name, configuration in
                try await manager.saveProfile(name: name, configuration: configuration)
                actionError = nil
            }
        }
        .confirmationDialog(
            "Удалить конфигурацию?",
            isPresented: $confirmDeletion,
            titleVisibility: .visible
        ) {
            Button("Удалить конфигурацию", role: .destructive) {
                perform { try await manager.deleteProfile() }
            }
        } message: {
            Text("Конфигурация будет удалена с iPhone.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZagMark()
                .stroke(VPNTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 36)
                .accessibilityHidden(true)
            Text("ZAGALSKY")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .tracking(1.2)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("VPN").font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            Button {
                showPersonalization = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(VPNTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Изменить имя и дату рождения")
        }
    }

    private var connectionButton: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(accent.opacity(Double(3 - index) * 0.10), lineWidth: 1)
                    .frame(width: CGFloat(164 + index * 32), height: CGFloat(164 + index * 32))
                    .accessibilityHidden(true)
            }

            Button(action: toggleVPN) {
                VStack(spacing: 10) {
                    if manager.isBusy || manager.status == .disconnecting {
                        ProgressView().tint(accent)
                            .frame(height: 44)
                    } else {
                        Image(systemName: powerIcon)
                            .font(.system(size: 44, weight: .light))
                            .frame(height: 44)
                    }

                    Text(powerTitle)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 18)
                }
                .foregroundStyle(accent)
                .frame(width: 150, height: 150)
                .background(
                    LinearGradient(
                        colors: [accent.opacity(0.32), VPNTheme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(accent.opacity(0.85), lineWidth: 1.5))
                .contentShape(Circle())
                .shadow(color: accent.opacity(0.26), radius: 26)
            }
            .buttonStyle(.plain)
            .disabled(manager.isBusy || manager.status == .disconnecting)
        }
        .frame(height: 234)
    }

    private var connectionStatus: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            if manager.status == .connected, let start = manager.connectedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(start, style: .timer)
                        .font(.system(.largeTitle, design: .monospaced, weight: .light))
                        .monospacedDigit()
                        .accessibilityLabel(Text("Длительность подключения \(duration(at: context.date, since: start))"))
                }
            }
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Конфигурация AmneziaWG", systemImage: "shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VPNTheme.muted)
                .accessibilityAddTraits(.isHeader)

            if let profile = manager.profile {
                Text(profile.name)
                    .font(.headline)
                if let endpoint = profile.endpoint {
                    Text(endpoint)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(VPNTheme.muted)
                        .textSelection(.enabled)
                }

                ViewThatFits {
                    HStack(spacing: 14) { editConfiguration; deleteConfiguration }
                    VStack(alignment: .leading, spacing: 0) { editConfiguration; deleteConfiguration }
                }
                .disabled(manager.isBusy || isTunnelActive)
                if isTunnelActive {
                    Text("Отключите VPN, чтобы изменить или удалить конфигурацию.")
                        .font(.footnote)
                        .foregroundStyle(VPNTheme.muted)
                }
            } else {
                Text("Вставьте текст конфигурации или откройте файл .conf.")
                    .font(.subheadline)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(VPNTheme.border).allowsHitTesting(false))
    }

    private var editConfiguration: some View {
        Button {
            editProfile()
        } label: {
            Label("Изменить", systemImage: "square.and.pencil")
                .frame(minHeight: 44)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var deleteConfiguration: some View {
        Button(role: .destructive) {
            confirmDeletion = true
        } label: {
            Label("Удалить", systemImage: "trash")
                .frame(minHeight: 44)
        }
        .tint(VPNTheme.warning)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var accent: Color {
        manager.status == .connected ? VPNTheme.connected : VPNTheme.accent
    }

    private var canDisconnect: Bool {
        switch manager.status {
        case .connecting, .connected, .reasserting: return true
        default: return false
        }
    }

    private var isTunnelActive: Bool {
        canDisconnect || manager.status == .disconnecting
    }

    private var powerIcon: String {
        if manager.status == .connected { return "checkmark.shield.fill" }
        return manager.profile == nil && !isTunnelActive ? "plus" : "power"
    }

    private var powerTitle: String {
        switch manager.status {
        case .connecting: return "Отменить"
        case .connected, .reasserting: return "Отключить"
        case .disconnecting: return "Отключение"
        default: return manager.profile == nil ? "Добавить конфигурацию" : "Подключить"
        }
    }

    private var statusText: String {
        switch manager.status {
        case .connecting: return "Запуск VPN"
        case .connected: return "VPN подключён"
        case .reasserting: return "Переподключение"
        case .disconnecting: return "Отключение VPN"
        case .invalid, .disconnected: return "VPN отключён"
        @unknown default: return "Статус недоступен"
        }
    }

    private func duration(at now: Date, since start: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func editProfile() {
        profileEditor = ProfileEditor.Input(
            name: manager.profile?.name ?? "",
            configuration: manager.profile?.configuration ?? ""
        )
    }

    private func toggleVPN() {
        if canDisconnect {
            perform { try await manager.disconnect() }
        } else if manager.profile == nil {
            editProfile()
        } else {
            perform { try await manager.connect() }
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        actionError = nil
        Task {
            do {
                try await action()
            } catch {
                actionError = TunnelIssue.message(for: error)
            }
        }
    }
}

struct ZagMark: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.addLines([
            CGPoint(x: width * 0.50, y: height * 0.03),
            CGPoint(x: width * 0.94, y: height * 0.21),
            CGPoint(x: width * 0.88, y: height * 0.64),
            CGPoint(x: width * 0.50, y: height * 0.96),
            CGPoint(x: width * 0.12, y: height * 0.64),
            CGPoint(x: width * 0.06, y: height * 0.21),
            CGPoint(x: width * 0.50, y: height * 0.03)
        ])
        path.addLines([
            CGPoint(x: width * 0.27, y: height * 0.31),
            CGPoint(x: width * 0.73, y: height * 0.31),
            CGPoint(x: width * 0.27, y: height * 0.66),
            CGPoint(x: width * 0.73, y: height * 0.66)
        ])
        return path
    }
}
