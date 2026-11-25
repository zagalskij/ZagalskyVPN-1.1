import Combine
import Foundation
import NetworkExtension

struct VPNProfile {
    let name: String
    let configuration: String
    let endpoint: String?
}

@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var profile: VPNProfile?
    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    var connectedAt: Date? { manager?.connection.connectedDate }

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var askedToDisconnect = false
    private var waitingForConnection = false

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NETunnelProviderSession else { return }
            Task { @MainActor in
                self?.connectionStatusChanged(connection)
            }
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let bundleIdentifier = try tunnelBundleIdentifier()
            let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation { continuation in
                NETunnelProviderManager.loadAllFromPreferences { managers, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: managers ?? [])
                    }
                }
            }
            let savedManager = managers.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleIdentifier
            }
            manager = savedManager
            status = savedManager?.connection.status ?? .disconnected
            profile = nil
            if let savedManager,
               let tunnelProtocol = savedManager.protocolConfiguration as? NETunnelProviderProtocol,
               let reference = tunnelProtocol.passwordReference {
                profile = VPNProfile(
                    name: savedManager.localizedDescription ?? TunnelSettings.defaultName,
                    configuration: try ConfigurationKeychain.read(reference),
                    endpoint: tunnelProtocol.serverAddress
                )
            }
        } catch {
            errorMessage = TunnelIssue.message(for: error)
        }
    }

    func saveProfile(name: String, configuration: String) async throws {
        try beginOperation()
        defer { isBusy = false }
        try ensureDisconnected()

        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileName = title.isEmpty ? TunnelSettings.defaultName : title
        let parsed = try TunnelSettings.parse(configuration, name: profileName)
        let endpoint = parsed.peers.compactMap { $0.endpoint?.stringRepresentation }.first
        let bundleIdentifier = try tunnelBundleIdentifier()
        let savedManager = manager ?? NETunnelProviderManager()
        let previousProtocol = savedManager.protocolConfiguration as? NETunnelProviderProtocol
        let previousName = savedManager.localizedDescription
        let previouslyEnabled = savedManager.isEnabled
        let reference = try ConfigurationKeychain.store(configuration)

        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = bundleIdentifier
        tunnelProtocol.serverAddress = endpoint
        tunnelProtocol.passwordReference = reference
        savedManager.localizedDescription = profileName
        savedManager.protocolConfiguration = tunnelProtocol
        savedManager.isEnabled = true

        do {
            try await savedManager.saveToPreferences()
        } catch {
            savedManager.localizedDescription = previousName
            savedManager.protocolConfiguration = previousProtocol
            savedManager.isEnabled = previouslyEnabled
            ConfigurationKeychain.remove(reference)
            throw error
        }

        manager = savedManager
        status = savedManager.connection.status
        profile = VPNProfile(name: profileName, configuration: configuration, endpoint: endpoint)
        if let previousReference = previousProtocol?.passwordReference {
            ConfigurationKeychain.remove(previousReference)
        }
    }

    func deleteProfile() async throws {
        try beginOperation()
        defer { isBusy = false }
        try ensureDisconnected()

        guard let manager else { return }
        let reference = (manager.protocolConfiguration as? NETunnelProviderProtocol)?.passwordReference
        try await manager.removeFromPreferences()
        self.manager = nil
        profile = nil
        status = .disconnected
        if let reference {
            ConfigurationKeychain.remove(reference)
        }
    }

    func connect() async throws {
        try beginOperation()
        defer { isBusy = false }
        guard let manager, profile != nil else {
            throw TunnelIssue.profileRequired
        }

        try ensureDisconnected()
        try await manager.loadFromPreferences()
        if !manager.isEnabled {
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            throw TunnelIssue.startup
        }
        askedToDisconnect = false
        try session.startTunnel(options: nil)
        let systemStatus = session.status
        waitingForConnection = systemStatus != .connected
        status = systemStatus == .disconnected || systemStatus == .invalid ? .connecting : systemStatus
    }

    func disconnect() async throws {
        try beginOperation()
        defer { isBusy = false }
        guard let session = manager?.connection as? NETunnelProviderSession else { return }

        askedToDisconnect = true
        waitingForConnection = false
        session.stopTunnel()
        status = session.status
    }

    private func beginOperation() throws {
        guard !isBusy else { throw TunnelIssue.operationInProgress }
        isBusy = true
        errorMessage = nil
    }

    private func ensureDisconnected() throws {
        let systemStatus = manager?.connection.status ?? .disconnected
        guard !waitingForConnection,
              systemStatus == .disconnected || systemStatus == .invalid else {
            throw TunnelIssue.profileWhileConnected
        }
    }

    private func tunnelBundleIdentifier() throws -> String {
        guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
            throw TunnelIssue.missingExtension
        }
        return appBundleIdentifier + ".PacketTunnel"
    }

    private func connectionStatusChanged(_ connection: NETunnelProviderSession) {
        guard manager == connection.manager else { return }

        let previousStatus = status
        status = connection.status
        if status == .connected {
            waitingForConnection = false
            errorMessage = nil
        }
        if status == .disconnected || status == .invalid {
            let failedToConnect = waitingForConnection
            waitingForConnection = false
            let unexpectedlyDisconnected = !askedToDisconnect && (failedToConnect ||
                previousStatus == .connected || previousStatus == .reasserting)
            askedToDisconnect = false
            if unexpectedlyDisconnected {
                loadDisconnectError(for: connection, failedToConnect: failedToConnect)
            }
        }
    }

    private func loadDisconnectError(for connection: NETunnelProviderSession, failedToConnect: Bool) {
        connection.fetchLastDisconnectError { [weak self] error in
            Task { @MainActor in
                guard let self, self.manager == connection.manager, !self.isBusy,
                      !self.waitingForConnection, self.status == .disconnected || self.status == .invalid else {
                    return
                }
                if let error {
                    self.errorMessage = TunnelIssue.message(for: error)
                } else if failedToConnect {
                    self.errorMessage = TunnelIssue.startup.errorDescription
                }
            }
        }
    }
}
