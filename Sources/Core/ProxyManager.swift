import Foundation
import NetworkExtension
import Combine

/// 代理隧道的启停管理。
///
/// 这里只做 NetworkExtension 的生命周期管理，**不含代理内核**。
/// 内核（sing-box / Xray）接入点在 `PacketTunnelProvider` 里标注。
@MainActor
final class ProxyManager: ObservableObject {

    enum Status {
        case notConfigured
        case disconnected
        case connecting
        case connected
        case error(String)

        var label: String {
            switch self {
            case .notConfigured: return "未配置"
            case .disconnected:  return "已断开"
            case .connecting:    return "连接中"
            case .connected:     return "已连接"
            case .error(let message): return "错误：\(message)"
            }
        }
    }

    @Published private(set) var status: Status = .notConfigured
    @Published var serverAddress: String = ""
    @Published var serverPort: Int = 1080
    @Published var proxyMode: String = "rule"    // rule / global / direct

    private var manager: NETunnelProviderManager?

    private let tunnelBundleID = "com.benteng.netpilot.tunnel"

    // MARK: - 生命周期

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existing = managers.first(where: { config in
                (config.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == tunnelBundleID
            }) {
                manager = existing
                readSettings(from: existing)
                refreshStatus()
            } else {
                status = .notConfigured
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// 首次配置：把 provider 注册进系统。
    func configure() async {
        let manager = self.manager ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = serverAddress.isEmpty ? "本地代理" : serverAddress
        // 传给 PacketTunnelProvider 的启动参数
        proto.providerConfiguration = [
            "server": serverAddress,
            "port": serverPort,
            "mode": proxyMode
        ]
        manager.protocolConfiguration = proto
        manager.localizedDescription = "网络助手代理"
        manager.isEnabled = true

        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            self.manager = manager
            refreshStatus()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - 启停

    func setEnabled(_ enabled: Bool) async {
        if manager == nil {
            await configure()
        }
        guard let manager else {
            status = .error("无法创建隧道配置")
            return
        }

        do {
            if enabled {
                status = .connecting
                try manager.connection.startVPNTunnel()
            } else {
                manager.connection.stopVPNTunnel()
                status = .disconnected
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// 轮询系统返回的隧道状态。
    func refreshStatus() {
        guard let manager else {
            status = .notConfigured
            return
        }
        switch manager.connection.status {
        case .connected:            status = .connected
        case .connecting,
             .reasserting:          status = .connecting
        case .disconnecting:        status = .connecting
        case .disconnected:         status = .disconnected
        case .invalid:              status = .error("配置无效")
        @unknown default:           status = .disconnected
        }
    }

    private func readSettings(from manager: NETunnelProviderManager) {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
        serverAddress = proto.serverAddress ?? ""
        if let config = proto.providerConfiguration {
            serverPort = (config["port"] as? Int) ?? 1080
            proxyMode = (config["mode"] as? String) ?? "rule"
        }
    }
}
