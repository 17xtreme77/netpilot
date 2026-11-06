import Foundation
import Combine

/// 一个自然月 / 一年的流量累计。
struct UsageBucket: Codable, Identifiable, Equatable {
    var key: String          // "2026-11" 或 "2026"
    var cellIn: UInt64 = 0
    var cellOut: UInt64 = 0
    var wifiIn: UInt64 = 0
    var wifiOut: UInt64 = 0

    var id: String { key }
    var cellTotal: UInt64 { cellIn &+ cellOut }
    var wifiTotal: UInt64 { wifiIn &+ wifiOut }
}

/// 单日累计，用于概览页的趋势柱状图。
struct DailyBucket: Codable, Identifiable, Equatable {
    var day: String          // "2026-11-06"
    var cell: UInt64 = 0     // 移动数据上下行合计
    var wifi: UInt64 = 0

    var id: String { day }
    var total: UInt64 { cell &+ wifi }
}

/// 流量累加器。
///
/// 核心难点：`getifaddrs` 给的是「开机以来」的绝对值，重启会归零。
/// 策略：
/// 1. 首次运行只记基线，不把装机前的历史流量算进来
/// 2. 每次采样取增量累加到当月
/// 3. 发现当前值小于上次值 → 判定为重启，把当前值整体计入
/// 4. 跨月自动归档上一月
@MainActor
final class UsageStore: ObservableObject {

    @Published private(set) var current: UsageBucket
    @Published private(set) var history: [UsageBucket]
    /// 最近若干天的用量，最多保留 60 天。
    @Published private(set) var daily: [DailyBucket]
    @Published private(set) var isCellularActive: Bool = false
    @Published private(set) var planBytes: UInt64 = 0

    /// 实时速率（字节/秒），用于概览页的速率显示
    @Published private(set) var downRate: Double = 0
    @Published private(set) var upRate: Double = 0

    private var lastSnapshot: InterfaceCounters?
    private var lastSampleTime: Date?
    private var timer: Timer?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let current = "netpilot.usage.current"
        static let history = "netpilot.usage.history"
        static let daily   = "netpilot.usage.daily"
        static let plan = "netpilot.usage.planBytes"
    }

    init() {
        let monthKey = Self.monthKey(for: Date())
        if let data = defaults.data(forKey: Key.current),
           let saved = try? JSONDecoder().decode(UsageBucket.self, from: data),
           saved.key == monthKey {
            current = saved
        } else {
            current = UsageBucket(key: monthKey)
        }

        if let data = defaults.data(forKey: Key.history),
           let saved = try? JSONDecoder().decode([UsageBucket].self, from: data) {
            history = saved
        } else {
            history = []
        }

        if let data = defaults.data(forKey: Key.daily),
           let saved = try? JSONDecoder().decode([DailyBucket].self, from: data) {
            daily = saved
        } else {
            daily = []
        }

        planBytes = UInt64(defaults.double(forKey: Key.plan))

        // 建立基线
        lastSnapshot = InterfaceReader.snapshot()
        lastSampleTime = Date()
    }

    // MARK: - 采样

    func startSampling(interval: TimeInterval = 1.0) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
    }

    /// 采一次样，累加增量。
    func sample() {
        let now = Date()
        let snapshot = InterfaceReader.snapshot()
        isCellularActive = snapshot.cellTotal > 0

        if let last = lastSnapshot {
            let cellIn  = Self.delta(current: snapshot.cellIn,  previous: last.cellIn)
            let cellOut = Self.delta(current: snapshot.cellOut, previous: last.cellOut)
            let wifiIn  = Self.delta(current: snapshot.wifiIn,  previous: last.wifiIn)
            let wifiOut = Self.delta(current: snapshot.wifiOut, previous: last.wifiOut)

            rolloverIfNeeded(for: now)

            current.cellIn  &+= cellIn
            current.cellOut &+= cellOut
            current.wifiIn  &+= wifiIn
            current.wifiOut &+= wifiOut

            accumulateDaily(now: now,
                            cell: cellIn &+ cellOut,
                            wifi: wifiIn &+ wifiOut)

            if let lastTime = lastSampleTime {
                let elapsed = max(now.timeIntervalSince(lastTime), 0.001)
                downRate = Double(cellIn &+ wifiIn) / elapsed
                upRate   = Double(cellOut &+ wifiOut) / elapsed
            }
        }

        lastSnapshot = snapshot
        lastSampleTime = now
        persist()
    }

    /// 增量计算，处理计数器归零（重启）的情况。
    /// 抽成 nonisolated static 是为了能在本地单测里直接验证。
    nonisolated static func delta(current: UInt64, previous: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        // 计数器变小 = 设备重启过，把当前值当成新增
        return current
    }

    // MARK: - 按日累计

    private func accumulateDaily(now: Date, cell: UInt64, wifi: UInt64) {
        guard cell > 0 || wifi > 0 else { return }
        let key = Self.dayKey(for: now)

        if let index = daily.firstIndex(where: { $0.day == key }) {
            daily[index].cell &+= cell
            daily[index].wifi &+= wifi
        } else {
            daily.append(DailyBucket(day: key, cell: cell, wifi: wifi))
            if daily.count > 60 {
                daily.removeFirst(daily.count - 60)
            }
        }
    }

    /// 取最近 `count` 天，缺的天补 0，保证柱状图根数固定。
    func recentDays(_ count: Int) -> [DailyBucket] {
        Self.fillDays(daily, count: count, now: Date())
    }

    /// 补齐日期序列。抽成纯函数，便于在本地单测里直接验证。
    nonisolated static func fillDays(_ buckets: [DailyBucket],
                                     count: Int,
                                     now: Date) -> [DailyBucket] {
        guard count > 0 else { return [] }
        let calendar = Calendar.current
        var result: [DailyBucket] = []
        result.reserveCapacity(count)

        for offset in stride(from: count - 1, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let key = dayKey(for: date)
            result.append(buckets.first(where: { $0.day == key }) ?? DailyBucket(day: key))
        }
        return result
    }

    nonisolated static func dayKey(for date: Date) -> String {
        // 刻意不用 DateFormatter：概览页每秒重算 24 天的 key，
        // DateFormatter 的构造开销在这个频率下会拖住主线程。
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 跨月归档。
    private func rolloverIfNeeded(for date: Date) {
        let key = Self.monthKey(for: date)
        guard current.key != key else { return }

        if current.cellTotal > 0 || current.wifiTotal > 0 {
            history.append(current)
            if history.count > 24 { history.removeFirst(history.count - 24) }
        }
        current = UsageBucket(key: key)
    }

    // MARK: - 套餐

    func setPlan(bytes: UInt64) {
        planBytes = bytes
        defaults.set(Double(bytes), forKey: Key.plan)
        persist()
    }

    /// 本月剩余百分比，未设套餐返回 nil。
    var remainingRatio: Double? {
        guard planBytes > 0 else { return nil }
        let used = Double(current.cellTotal)
        return max(0, min(1, 1 - used / Double(planBytes)))
    }

    var remainingBytes: UInt64 {
        guard planBytes > current.cellTotal else { return 0 }
        return planBytes - current.cellTotal
    }

    /// 按当前用量线性外推，本月底会超套餐吗。
    var projectedOverage: UInt64 {
        guard planBytes > 0 else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return 0 }
        let day = calendar.component(.day, from: now)
        guard day > 0 else { return 0 }
        let projected = Double(current.cellTotal) / Double(day) * Double(range.count)
        let over = projected - Double(planBytes)
        return over > 0 ? UInt64(over) : 0
    }

    // MARK: - 持久化

    private func persist() {
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Key.current)
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Key.history)
        }
        if let data = try? JSONEncoder().encode(daily) {
            defaults.set(data, forKey: Key.daily)
        }
    }

    nonisolated static func monthKey(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    /// 清空本月统计（不会清网卡计数器，只是把本地记录归零）。
    func resetCurrentMonth() {
        current = UsageBucket(key: Self.monthKey(for: Date()))
        persist()
    }
}
