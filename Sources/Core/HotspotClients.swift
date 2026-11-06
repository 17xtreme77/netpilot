import Foundation

/// 一个连在热点上的客户端设备。
struct HotspotClient: Identifiable, Equatable {
    var id: String { mac.isEmpty ? ip : mac }
    var ip: String
    var mac: String
    var name: String
    var isBlocked: Bool = false

    var displayName: String {
        if !name.isEmpty { return name }
        if !mac.isEmpty { return mac }
        return ip
    }
}

/// 枚举热点上已连接的设备。
///
/// 两条数据源，按可靠性排序：
/// 1. `/var/db/dhcpd_leases`：bootpd 分配 DHCP 租约时写入，含主机名 + MAC + IP。
///    JAILBREAK: 需要读系统盘权限（no-sandbox）。
/// 2. `arp -a`：ARP 表里当前活跃的设备，拿不到主机名，但更实时。
///
/// 两个都读不到时返回空数组，UI 应提示「需要越狱权限」。
enum HotspotClients {

    // MARK: - DHCP 租约

    static func fromDHCPLeases() -> [HotspotClient] {
        let paths = [
            "/var/db/dhcpd_leases",
            "/private/var/db/dhcpd_leases",
            "/var/db/dhcpd/dhcpd.leases"
        ]

        for path in paths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8),
                  !content.isEmpty else { continue }
            let parsed = parseLeases(content)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    /// 解析 bootpd 的租约文件，格式是一串花括号块：
    /// ```
    /// {
    ///     Name=MacBook-Pro
    ///     IPAddress=172.20.10.2
    ///     HWAddress=aa:bb:cc:dd:ee:ff
    ///     Lease=3600
    /// }
    /// ```
    static func parseLeases(_ content: String) -> [HotspotClient] {
        var clients: [HotspotClient] = []
        var current: [String: String] = [:]
        var depth = 0

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("{") {
                depth += 1
                current = [:]
                continue
            }

            if line.hasPrefix("}") {
                depth = max(0, depth - 1)
                if let ip = current["IPAddress"], !ip.isEmpty {
                    clients.append(HotspotClient(
                        ip: ip,
                        mac: (current["HWAddress"] ?? "").lowercased(),
                        name: current["Name"] ?? ""
                    ))
                }
                current = [:]
                continue
            }

            if let eq = line.firstIndex(of: "=") {
                let key = String(line[line.startIndex..<eq])
                let value = String(line[line.index(after: eq)...])
                current[key] = value
            }
        }

        return clients.sorted { lhs, rhs in
            ipSortKey(lhs.ip) < ipSortKey(rhs.ip)
        }
    }

    // MARK: - ARP 表

    static func fromARP() -> [HotspotClient] {
        let result = Shell.run(Shell.resolve("/usr/sbin/arp"), ["-a", "-n"])
        guard result.isSuccess else { return [] }

        var clients: [HotspotClient] = []
        for line in result.output.components(separatedBy: .newlines) {
            // 形如：? (172.20.10.2) at aa:bb:cc:dd:ee:ff on bridge100 ifscope [ethernet]
            guard line.contains("bridge"), line.contains(" at ") else { continue }
            guard let openParen = line.firstIndex(of: "("),
                  let closeParen = line.firstIndex(of: ")"),
                  openParen < closeParen else { continue }

            let ip = String(line[line.index(after: openParen)..<closeParen])

            let afterAt = line.components(separatedBy: " at ")
            guard afterAt.count > 1 else { continue }
            let mac = afterAt[1].components(separatedBy: " ").first ?? ""
            guard mac.contains(":") else { continue }

            // ARP 里主机名是 "?" 或 "(name)"
            var name = ""
            if let range = line.range(of: " (") , line.hasPrefix("?") {
                if let end = line.range(of: ")") , range.upperBound < end.lowerBound {
                    name = String(line[range.upperBound..<end.lowerBound])
                }
            }

            clients.append(HotspotClient(ip: ip, mac: mac.lowercased(), name: name))
        }
        return clients
    }

    /// 合并两个来源：以 DHCP 租约为准（有主机名），用 ARP 补全 IP 归属。
    static func list() -> [HotspotClient] {
        let leases = fromDHCPLeases()
        let arp = fromARP()

        guard !leases.isEmpty else { return arp }
        guard !arp.isEmpty else { return leases }

        var merged = leases
        for entry in arp {
            if let index = merged.firstIndex(where: { $0.ip == entry.ip }) {
                if merged[index].mac.isEmpty { merged[index].mac = entry.mac }
            } else if !merged.contains(where: { $0.mac == entry.mac && !entry.mac.isEmpty }) {
                merged.append(entry)
            }
        }
        return merged
    }

    // MARK: - 工具

    private static func ipSortKey(_ ip: String) -> UInt32 {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return .max }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }
}
