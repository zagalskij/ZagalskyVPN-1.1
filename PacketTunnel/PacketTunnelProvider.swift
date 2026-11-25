import Foundation
import NetworkExtension
import WireGuardKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    // Upstream messages can contain configuration details, so do not persist them in system logs.
    private lazy var adapter = WireGuardAdapter(with: self) { _, _ in }

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
              let reference = protocolConfiguration.passwordReference else {
            completionHandler(TunnelIssue.profileRequired)
            return
        }

        do {
            let configuration = try ConfigurationKeychain.read(reference)
            let parsed = try TunnelSettings.parse(configuration, name: TunnelSettings.defaultName)
            adapter.start(tunnelConfiguration: parsed) { error in
                switch error {
                case nil:
                    completionHandler(nil)
                case .some(.dnsResolution):
                    completionHandler(TunnelIssue.endpointResolution)
                default:
                    completionHandler(TunnelIssue.startup)
                }
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { _ in completionHandler() }
    }
}
