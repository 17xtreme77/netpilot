import NetworkExtension
import os.log

/// 透明代理隧道的 Provider。
///
/// 当前状态：**隧道骨架已完整，内核未接入**。
/// `readPackets` 循环拿到的是原始 IP 包，接入内核的位置在 `handle(packet:)`。
///
/// 接入 sing-box / Xray 的一般做法：
/// 1. 把内核编译成 XCFramework（或用官方提供的 `Libbox` / `Xray-core` xcframework）
/// 2. 在 `startTunnel` 里启动内核的 TUN 服务，让它直接接管 `packetFlow`
///    而不是自己读包——sing-box 的 `Libbox` 提供 `startPacketTunnel`，
///    内部会调用 provider 的 `packetFlow`，性能远好于手动转发
/// 3. `NEPacketTunnelNetworkSettings` 的地址段要和内核配置里的一致（默认 172.19.0.1/30）
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.benteng.netpilot.tunnel", category: "tunnel")
    private var isRunning = false

    // TODO: 接入内核后替换成 Libbox / Xray 的实例
    // private var boxService: LibboxBoxService?

    override func startTunnel(options: [String: NSObject]?,
                             completionHandler: @escaping (Error?) -> Void) {
        let proto = protocolConfiguration as? NETunnelProviderProtocol
        let server = proto?.providerConfiguration?["server"] as? String ?? ""
        let port = proto?.providerConfiguration?["port"] as? Int ?? 1080
        let mode = proto?.providerConfiguration?["mode"] as? String ?? "rule"

        os_log("启动隧道 server=%{public}@:%d mode=%{public}@",
               log: log, type: .info, server, port, mode)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            // 排除内网，避免局域网设备失联
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.20.10.0", subnetMask: "255.255.255.240")
        ]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["198.18.0.2"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        settings.mtu = 1500

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(error)
                return
            }
            if let error {
                os_log("设置隧道失败: %{public}@", log: self.log, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }

            // TODO: 在这里启动内核
            // let box = LibboxNewService(...)
            // box.start()

            self.isRunning = true
            self.startReadingPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        isRunning = false
        // TODO: 停止内核
        os_log("隧道停止 reason=%d", log: log, type: .info, reason.rawValue)
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        // App 侧发消息过来问运行状态 / 切换节点
        if let text = String(data: messageData, encoding: .utf8) {
            os_log("收到 App 消息: %{public}@", log: log, type: .debug, text)
        }
        completionHandler(messageData)
    }

    // MARK: - 包处理

    private func startReadingPackets() {
        guard isRunning else { return }

        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, self.isRunning else { return }

            for (index, packet) in packets.enumerated() {
                let proto = index < protocols.count ? protocols[index] : NSNumber(value: AF_INET)
                self.handle(packet: packet, protocolFamily: proto.int32Value)
            }

            // 继续读下一批
            self.startReadingPackets()
        }
    }

    /// 单个 IP 包的处理入口。
    ///
    /// 当前实现只做计数和丢弃（避免流量泄漏到隧道外）。
    /// 接入内核后，这里应该是「把包塞给内核的 TUN 队列」。
    private func handle(packet: Data, protocolFamily: Int32) {
        // TODO: 交给内核处理
        // box.writePacket(packet, protocolFamily)

        // 未接入内核时直接丢弃，否则会造成黑洞 + 电量消耗
        _ = packet.count
    }
}
