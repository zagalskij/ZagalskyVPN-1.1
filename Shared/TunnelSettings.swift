import Foundation
import WireGuardKit

enum TunnelSettings {
    static let defaultName = "Мой сервер"
    static let maximumConfigurationSize = 256 * 1024

    static func parse(_ input: String, name: String) throws -> TunnelConfiguration {
        guard input.utf8.count <= maximumConfigurationSize else {
            throw TunnelIssue.configurationTooLarge
        }

        let text = input.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        if text.lowercased().hasPrefix("vpn://") {
            throw TunnelIssue.requiresFileExport
        }

        let configuration: TunnelConfiguration
        do {
            configuration = try TunnelConfiguration(fromWgQuickConfig: text, called: name)
        } catch {
            throw TunnelIssue.invalidConfiguration
        }
        guard configuration.peers.contains(where: { $0.endpoint != nil }) else {
            throw TunnelIssue.missingEndpoint
        }
        return configuration
    }
}

enum TunnelIssue: Int, LocalizedError, CustomNSError {
    case invalidConfiguration = 1
    case configurationTooLarge
    case requiresFileExport
    case missingEndpoint
    case keychain
    case profileRequired
    case profileWhileConnected
    case operationInProgress
    case endpointResolution
    case startup
    case missingExtension

    static var errorDomain: String { "com.zagalsky.vpn.tunnel-error" }
    var errorCode: Int { rawValue }

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Не удалось прочитать конфигурацию. Вставьте полный текст файла AmneziaWG с разделами [Interface] и [Peer]."
        case .configurationTooLarge:
            return "Файл конфигурации слишком большой. Максимальный размер — 256 КБ."
        case .requiresFileExport:
            return "Для этого профиля экспортируйте из AmneziaVPN конфигурацию в формате AmneziaWG (.conf)."
        case .missingEndpoint:
            return "В конфигурации отсутствует адрес сервера. Проверьте поле Endpoint в разделе [Peer]."
        case .keychain:
            return "Не удалось получить доступ к конфигурации в Связке ключей. Разблокируйте iPhone и повторите попытку."
        case .profileRequired:
            return "Сначала добавьте конфигурацию AmneziaWG."
        case .profileWhileConnected:
            return "Отключите VPN, чтобы изменить или удалить профиль."
        case .operationInProgress:
            return "Дождитесь завершения текущей операции."
        case .endpointResolution:
            return "Не удалось определить адрес сервера. Проверьте поле Endpoint и подключение к интернету."
        case .startup:
            return "iOS не удалось запустить VPN-туннель. Проверьте конфигурацию AmneziaWG и доступность сервера."
        case .missingExtension:
            return "В сборке приложения отсутствует расширение VPN."
        }
    }

    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: localizedDescriptionText]
    }

    static func message(for error: Error) -> String {
        let systemError = error as NSError
        if systemError.domain == errorDomain, let issue = Self(rawValue: systemError.code) {
            return issue.localizedDescriptionText
        }
        return "Не удалось выполнить операцию VPN. Проверьте, что приложению разрешено добавлять VPN-конфигурации в настройках iOS."
    }

    private var localizedDescriptionText: String {
        errorDescription ?? "Произошла ошибка VPN."
    }
}
