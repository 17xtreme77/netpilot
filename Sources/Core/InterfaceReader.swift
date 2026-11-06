import Foundation
import Darwin

/// 网卡字节计数器快照。
///
/// 数据来自 `getifaddrs` 返回的 `if_data`，是内核维护的**网卡累计字节数**：
/// - 统计范围是整个系统，无法按 App 拆分
/// - 设备重启后归零
/// - 接口名 `en*` 为 Wi-Fi / 有线，`pdp_ip*` 为蜂窝
struct InterfaceCounters: Equatable {
    var wifiIn: UInt64 = 0
    var wifiOut: UInt64 = 0
    var cellIn: UInt64 = 0
    var cellOut: UInt64 = 0

    var wifiTotal: UInt64 { wifiIn &+ wifiOut }
    var cellTotal: UInt64 { cellIn &+ cellOut }

    static let zero = InterfaceCounters()
}

enum InterfaceReader {

    /// 读取当前所有网卡的累计字节数。
    static func snapshot() -> InterfaceCounters {
        var result = InterfaceCounters.zero

        var listPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&listPointer) == 0, let first = listPointer else {
            return result
        }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }

            let name = String(cString: ifa.pointee.ifa_name)

            // 只有带 ifa_data 的条目才有流量信息（AF_LINK 类型）
            guard let raw = ifa.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee

            if name.hasPrefix("en") {
                result.wifiIn  &+= UInt64(data.ifi_ibytes)
                result.wifiOut &+= UInt64(data.ifi_obytes)
            } else if name.hasPrefix("pdp_ip") {
                // iPhone 上 pdp_ip0/1/2 可能同时存在（双卡），全部累加
                result.cellIn  &+= UInt64(data.ifi_ibytes)
                result.cellOut &+= UInt64(data.ifi_obytes)
            }
        }

        return result
    }

    /// 当前活跃的网络接口名列表，用于判断是否在热点桥接状态。
    static func activeInterfaceNames() -> [String] {
        var names: [String] = []
        var listPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&listPointer) == 0, let first = listPointer else { return names }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// 是否存在「真正在工作」的热点桥接接口。
    ///
    /// ⚠️ 不能用「有没有 bridge 接口」来判断：iOS / macOS 上 `bridge0` 是常驻的
    /// （AirDrop、Continuity、系统内部桥接都用它），Mac 上还会有 bridge100/101。
    /// 本地实测 macOS 15.6 默认就带 bridge0、bridge100、bridge101 三个。
    ///
    /// 可靠特征：个人热点的桥接接口一定持有 `172.20.10.1/28` 这个固定网关地址。
    static func hasHotspotBridge() -> Bool {
        var listPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&listPointer) == 0, let first = listPointer else { return false }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }

            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("bridge"), let addr = ifa.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }

            let ip = String(cString: host)
            if ip.hasPrefix("172.20.10.") { return true }
        }
        return false
    }
}

extension UInt64 {
    /// 格式化为 1.2 GB / 340 MB 这类可读文本。
    var byteString: String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(self)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 { return "\(self) B" }
        return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, units[index])
    }
}
