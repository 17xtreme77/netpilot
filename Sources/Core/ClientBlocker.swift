import Foundation

/// 按 IP 阻断热点客户端上网。
///
/// **为什么只能靠 pf：**
/// 热点客户端的流量由系统 `natd` / IP 转发处理，不经过本 App 的进程，所以 App
/// 内部没有任何办法拦截。唯一出路是改内核包过滤规则，iOS 用的是 BSD `pf`。
///
/// JAILBREAK: 需要 root + `pfctl` 可执行 + 能创建 anchor 规则文件。
/// iOS 15+ 系统卷是 SSV 只读，**不能改 `/etc/pf.conf`**，所以这里走
/// 「单独 anchor + 通过 `-f` 传入自定义路径的规则文件」的方式，绕开系统配置。
///
/// ⚠️ 三个必须真机验证的点：
/// 1. 目标 iOS 版本上 `/sbin/pfctl` 是否存在且可执行
/// 2. `pf` 是否已启用（未启用需要 `pfctl -e`，可能被 SIP 类机制拒绝）
/// 3. 热点重连后客户端 IP 会变，规则需要跟着刷新
enum ClientBlocker {

    static let anchor = "com.benteng.netpilot"

    private static var rulesPath: String {
        let dir = "/var/mobile/Library/NetPilot"
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir,
                                                     withIntermediateDirectories: true)
        }
        return dir + "/pf.rules"
    }

    // MARK: - 对外接口

    /// 应用一组拉黑规则（传 IP 列表）。
    @discardableResult
    static func apply(blockedIPs: [String]) -> Shell.Result {
        let rules = buildRules(blockedIPs)
        do {
            try rules.write(toFile: rulesPath, atomically: true, encoding: .utf8)
        } catch {
            return Shell.Result(status: -1, output: "写入规则失败: \(error.localizedDescription)")
        }

        // 先清空旧规则，避免累积
        _ = Shell.run(Shell.resolve("/sbin/pfctl"), ["-a", anchor, "-F", "rules"])

        guard !blockedIPs.isEmpty else {
            return Shell.Result(status: 0, output: "已清空")
        }

        let result = Shell.run(Shell.resolve("/sbin/pfctl"),
                               ["-a", anchor, "-f", rulesPath])
        if !result.isSuccess {
            // 尝试启用 pf 后重试一次
            _ = Shell.run(Shell.resolve("/sbin/pfctl"), ["-e"])
            return Shell.run(Shell.resolve("/sbin/pfctl"), ["-a", anchor, "-f", rulesPath])
        }
        return result
    }

    /// 清空所有拉黑规则。
    @discardableResult
    static func clearAll() -> Shell.Result {
        apply(blockedIPs: [])
    }

    /// 打印当前 anchor 内的规则，用于自查。
    static func dumpRules() -> String {
        Shell.run(Shell.resolve("/sbin/pfctl"),
                  ["-a", anchor, "-s", "rules"]).output
    }

    /// 检查 pf 是否可用。
    static func isAvailable() -> Bool {
        let path = Shell.resolve("/sbin/pfctl")
        return FileManager.default.isExecutableFile(atPath: path)
    }

    // MARK: - 规则生成

    static func buildRules(_ ips: [String]) -> String {
        var lines = [
            "# NetPilot 客户端阻断规则",
            "# 由 App 自动生成，请勿手动修改",
            "# anchor: \(anchor)",
            ""
        ]

        for ip in ips where isValidIPv4(ip) {
            // block both directions，drop 比 reject 更彻底（对方表现为超时而非拒绝）
            lines.append("block drop quick from \(ip) to any")
            lines.append("block drop quick from any to \(ip)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func isValidIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return String(value) == part    // 排除 "01" 这类
        }
    }
}
