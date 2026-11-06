import Foundation

// 本机逻辑测试。
// 只编译不依赖 UIKit / NetworkExtension 的纯逻辑文件，验证算法正确性与编译完整性。
// 运行：./Tools/test-local.sh

var passed = 0
var failed = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        passed += 1
        print("  ✅ \(name)")
    } else {
        failed += 1
        print("  ❌ \(name)  \(detail)")
    }
}

func section(_ title: String) {
    print("\n▸ \(title)")
}

// MARK: - 1. DHCP 租约解析

section("DHCP 租约解析")

let leaseSample = """
{
\tName=MacBook-Pro
\tIPAddress=172.20.10.2
\tHWAddress=aa:bb:cc:dd:ee:02
\tHWType=1
\tIdentifier=01:aa:bb:cc:dd:ee:02
\tLease=3600
}
{
\tName=iPad
\tIPAddress=172.20.10.3
\tHWAddress=AA:BB:CC:DD:EE:03
\tHWType=1
\tLease=1800
}
{
\tIPAddress=172.20.10.9
\tHWAddress=aa:bb:cc:dd:ee:09
\tLease=900
}
"""

let parsed = HotspotClients.parseLeases(leaseSample)

check("解析出 3 台设备", parsed.count == 3, "实际 \(parsed.count)")
check("按 IP 升序排列",
      parsed.map(\.ip) == ["172.20.10.2", "172.20.10.3", "172.20.10.9"],
      "实际 \(parsed.map(\.ip))")
check("主机名正确", parsed.first?.name == "MacBook-Pro", "实际 \(String(describing: parsed.first?.name))")
check("MAC 统一小写", parsed[1].mac == "aa:bb:cc:dd:ee:03", "实际 \(parsed[1].mac)")
check("缺主机名的设备名回退到 MAC",
      parsed[2].displayName == "aa:bb:cc:dd:ee:09",
      "实际 \(parsed[2].displayName)")

check("空内容返回空数组", HotspotClients.parseLeases("").isEmpty)
check("垃圾内容不崩溃", HotspotClients.parseLeases("{{{}}\nrandom text\n=").isEmpty)

// 边界：IP 第 4 段为 10 和 9 时，字符串排序会错，数字排序才对
// 注意：bootpd 真实输出是一行一个键，解析器按此实现
let sortSample = """
{
\tIPAddress=172.20.10.10
\tHWAddress=aa:bb:cc:dd:ee:10
}
{
\tIPAddress=172.20.10.9
\tHWAddress=aa:bb:cc:dd:ee:09
}
"""
let sorted = HotspotClients.parseLeases(sortSample)
check("IP 按数值排序（10 排在 9 之后）",
      sorted.map(\.ip) == ["172.20.10.9", "172.20.10.10"],
      "实际 \(sorted.map(\.ip))")

// MARK: - 2. 流量增量算法

section("流量增量算法")

check("正常增长取差值", UsageStore.delta(current: 1000, previous: 400) == 600)
check("数值不变为 0", UsageStore.delta(current: 500, previous: 500) == 0)
check("计数器归零（重启）取当前值",
      UsageStore.delta(current: 800, previous: 999_999) == 800,
      "重启后计数器从 0 重新计数，应把当前值全算作新增")
check("首次运行 previous=0", UsageStore.delta(current: 1234, previous: 0) == 1234)

section("月份 key")
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.dateFormat = "yyyy-MM-dd"
let nov6 = formatter.date(from: "2026-11-06")!
let jan1 = formatter.date(from: "2027-01-01")!
check("2026-11-06 → 2026-11", UsageStore.monthKey(for: nov6) == "2026-11")
check("2027-01-01 → 2027-01", UsageStore.monthKey(for: jan1) == "2027-01")
check("跨年不会串月", UsageStore.monthKey(for: nov6) != UsageStore.monthKey(for: jan1))

// MARK: - 3. pf 规则生成

section("pf 规则生成")

check("空列表只生成注释头",
      !ClientBlocker.buildRules([]).contains("block drop"))
check("单 IP 生成双向规则",
      ClientBlocker.buildRules(["172.20.10.5"])
        .components(separatedBy: "block drop").count - 1 == 2)
check("规则含正确的源 IP",
      ClientBlocker.buildRules(["172.20.10.5"]).contains("from 172.20.10.5 to any"))
check("多 IP 全部写入",
      ClientBlocker.buildRules(["172.20.10.5", "172.20.10.6"])
        .components(separatedBy: "block drop").count - 1 == 4)

check("非法 IP 被过滤（256）",
      !ClientBlocker.buildRules(["256.1.1.1"]).contains("block drop"))
check("非法 IP 被过滤（缺段）",
      !ClientBlocker.buildRules(["1.2.3"]).contains("block drop"))
check("非法 IP 被过滤（前导零）",
      !ClientBlocker.buildRules(["01.2.3.4"]).contains("block drop"))
check("合法 IP 通过校验", ClientBlocker.isValidIPv4("172.20.10.5"))
check("空字符串不通过", !ClientBlocker.isValidIPv4(""))

// MARK: - 4. 真实网卡计数器

section("网卡计数器（真实读取本机）")

let first = InterfaceReader.snapshot()
print("  首次快照: WiFi 入 \(first.wifiIn) 出 \(first.wifiOut) / 蜂窝 入 \(first.cellIn) 出 \(first.cellOut)")

// 制造一点流量，验证计数器确实在动
let url = URL(string: "https://www.apple.com/library/test/success.html")!
let semaphore = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: url) { _, _, _ in semaphore.signal() }.resume()
_ = semaphore.wait(timeout: .now() + 8)

Thread.sleep(forTimeInterval: 0.5)
let second = InterfaceReader.snapshot()

check("WiFi 计数器单调递增",
      second.wifiIn >= first.wifiIn && second.wifiOut >= first.wifiOut,
      "第一次 \(first.wifiTotal) 第二次 \(second.wifiTotal)")

let grew = second.wifiTotal > first.wifiTotal
check("发起网络请求后计数增长", grew,
      "增量 \(second.wifiTotal - first.wifiTotal) 字节（可能因请求走缓存而不增长）")

print("  第二次快照: WiFi 入 \(second.wifiIn) 出 \(second.wifiOut)")
print("  接口列表: \(InterfaceReader.activeInterfaceNames().prefix(8).joined(separator: ", "))")

check("能列出网络接口", !InterfaceReader.activeInterfaceNames().isEmpty)
check("普通 Mac 上无热点桥接", !InterfaceReader.hasHotspotBridge())

// MARK: - 5. 字节格式化

section("字节格式化")

check("0 B", (0 as UInt64).byteString == "0 B", (0 as UInt64).byteString)
check("1024 → 1.0 KB", (1024 as UInt64).byteString == "1.0 KB", (1024 as UInt64).byteString)
check("1.5 GB", (1_610_612_736 as UInt64).byteString == "1.5 GB", (1_610_612_736 as UInt64).byteString)
check("大数不带小数位", (751_619_686_400 as UInt64).byteString == "700 GB", (751_619_686_400 as UInt64).byteString)

// MARK: - 6. 按日统计补齐

section("按日统计补齐")

let cal = Calendar.current
let fixedNow = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!

check("dayKey 格式", UsageStore.dayKey(for: fixedNow) == "2026-11-06",
      UsageStore.dayKey(for: fixedNow))

// 只给了 3 天有数据，其余应补 0
let sparse = [
    DailyBucket(day: "2026-11-02", cell: 100, wifi: 5),
    DailyBucket(day: "2026-11-04", cell: 300, wifi: 0),
    DailyBucket(day: "2026-11-06", cell: 500, wifi: 50)
]
let filled = UsageStore.fillDays(sparse, count: 5, now: fixedNow)

check("补齐后的天数正确", filled.count == 5, "实际 \(filled.count)")
check("按时间正序（最旧在前）",
      filled.map(\.day) == ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"],
      "实际 \(filled.map(\.day))")
check("最后一天是今天", filled.last?.day == "2026-11-06")
check("缺失的天补 0", filled[1].total == 0 && filled[3].total == 0)
check("已有数据不丢", filled[0].total == 105 && filled[2].total == 300 && filled[4].total == 550,
      "\(filled.map(\.total))")
check("总数不变", filled.reduce(0) { $0 + $1.total } == 955)

// 越界保护
check("count = 0 返回空", UsageStore.fillDays(sparse, count: 0, now: fixedNow).isEmpty)
check("空数据也补齐", UsageStore.fillDays([], count: 3, now: fixedNow).count == 3)

// 跨月不跳日：10 月 31 日往前推 3 天要落到 10/28
let oct31 = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
let crossMonth = UsageStore.fillDays([], count: 4, now: oct31)
check("跨月连续",
      crossMonth.map(\.day) == ["2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31"],
      "实际 \(crossMonth.map(\.day))")

// MARK: - 汇总

print("\n" + String(repeating: "─", count: 46))
print("通过 \(passed) 项，失败 \(failed) 项")
if failed > 0 {
    print("存在失败项")
    exit(1)
}
print("全部通过")
