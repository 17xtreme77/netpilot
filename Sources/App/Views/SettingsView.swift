import SwiftUI

/// 环境探测。
///
/// 一次探测要读动态存储、读租约文件、探测 pfctl 可执行位，全是同步 IO。
/// 概览页每秒都在刷新，而 `@EnvironmentObject` 一变整个 body 就会重算，
/// 所以这里做成「显式取快照」，绝不在 body 里现算。
enum EnvProbe {

    struct Snapshot: Equatable {
        var isRootless = false
        var hotspotReadable = false
        var pfAvailable = false
        var leasePathExists = false
        var leaseCount = 0
        var takenAt = Date()

        var jailbreakLabel: String {
            isRootless ? "已越狱 · rootless" : "未检测到越狱"
        }

        var leaseLabel: String {
            leasePathExists ? "\(leaseCount) 台在线" : "文件不存在"
        }
    }

    /// 无根越狱（Dopamine / palera1n rootless）把一切都挂在 /var/jb 下。
    static var isRootless: Bool {
        FileManager.default.fileExists(atPath: "/var/jb")
    }

    static func take() -> Snapshot {
        Snapshot(isRootless: isRootless,
                 hotspotReadable: HotspotMonitor.shared.read().isReadable,
                 pfAvailable: ClientBlocker.isAvailable(),
                 leasePathExists: FileManager.default.fileExists(atPath: "/var/db/dhcpd_leases"),
                 leaseCount: HotspotClients.fromDHCPLeases().count,
                 takenAt: Date())
    }
}

struct SettingsView: View {
    @EnvironmentObject private var usage: UsageStore

    @State private var planText: String = ""
    @State private var probe: EnvProbe.Snapshot?

    private var usedRatio: Double {
        guard usage.planBytes > 0 else { return 0 }
        return min(1, Double(usage.current.cellTotal) / Double(usage.planBytes))
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "设置")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    planCard
                    planEditor
                    statsSection
                    probeSection
                    maintenanceSection
                    aboutSection
                    SectionFoot(text: "NetPilot 使用私有 API，仅供自用，不可上架 App Store。")
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            syncPlanText()
            if probe == nil { probe = EnvProbe.take() }
        }
    }

    // MARK: 套餐卡片

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("每月流量上限")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                Spacer()
                Text("每月 1 日重置")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(usage.planBytes > 0 ? Fmt.bytesParts(usage.planBytes).0 : "—")
                    .font(Theme.num(34, .semibold))
                    .tracking(-1.2)
                    .foregroundStyle(Theme.text)
                Text(usage.planBytes > 0 ? Fmt.bytesParts(usage.planBytes).1 : "")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text2)
            }
            .padding(.top, 10)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Theme.mint.opacity(0.8), Theme.mint],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(0, geo.size.width * usedRatio))
                }
            }
            .frame(height: 6)
            .padding(.top, 16)

            HStack {
                Text("已用 \(Fmt.bytes(usage.current.cellTotal))")
                Spacer()
                Text(usage.planBytes > 0 ? "剩余 \(Fmt.bytes(usage.remainingBytes))" : "未设置")
            }
            .font(Theme.num(11, .regular))
            .foregroundStyle(Theme.text3)
            .padding(.top, 9)
        }
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 0.8)
        )
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }

    private var planEditor: some View {
        Card {
            HStack(spacing: 12) {
                Text("套餐额度")
                    .font(Theme.body)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                TextField("30", text: $planText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .font(Theme.num(15, .regular))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: 110)
                Text("GB")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text2)
                Button("保存") { savePlan() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.mint.opacity(0.14)))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.rowHeight)
        }
    }

    // MARK: 统计

    private var statsSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "统计")
            Card {
                VStack(spacing: 0) {
                    KeyValueRow(title: "采样间隔", value: "1 秒")
                    RowDivider()
                    KeyValueRow(title: "保留历史", value: "\(usage.history.count) 个月 / \(usage.daily.count) 天")
                    RowDivider()
                    KeyValueRow(title: "今日移动数据", value: Fmt.bytes(usage.recentDays(1).first?.cell ?? 0))
                }
            }
        }
    }

    // MARK: 环境自检

    private var probeSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "环境自检")

            if let snapshot = probe {
                Card {
                    VStack(spacing: 0) {
                        probeRow("越狱环境", snapshot.jailbreakLabel, ok: snapshot.isRootless)
                        RowDivider()
                        probeRow("热点状态接口", snapshot.hotspotReadable ? "可读" : "不可读",
                                 ok: snapshot.hotspotReadable)
                        RowDivider()
                        probeRow("pf 防火墙", snapshot.pfAvailable ? "可用" : "不可用",
                                 ok: snapshot.pfAvailable)
                        RowDivider()
                        probeRow("DHCP 租约", snapshot.leaseLabel, ok: snapshot.leasePathExists)
                        RowDivider()
                        ActionRow(icon: "arrow.triangle.2.circlepath", title: "重新自检",
                                  tint: Theme.mint) {
                            probe = EnvProbe.take()
                        }
                    }
                }
            } else {
                Card {
                    HStack {
                        Text("正在自检…")
                            .font(Theme.body)
                            .foregroundStyle(Theme.text3)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: Theme.rowHeight)
                }
            }

            SectionFoot(text: "任一项为红，说明对应功能在你这台机器上走不通，需要换实现路径（见 README 的降级方案）。")
        }
    }

    private func probeRow(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                StatusDot(ok: ok)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.rowHeight)
    }

    // MARK: 维护

    private var maintenanceSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "维护")
            Card {
                VStack(spacing: 0) {
                    ActionRow(icon: "trash", title: "重置本月统计", tint: Theme.red) {
                        usage.resetCurrentMonth()
                    }
                    RowDivider()
                    ActionRow(icon: "arrow.clockwise", title: "刷新界面数据") {
                        usage.sample()
                    }
                }
            }
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "关于")
            Card {
                VStack(spacing: 0) {
                    KeyValueRow(title: "版本", value: "0.2.0 (2)")
                    RowDivider()
                    KeyValueRow(title: "构建方式", value: "TrollStore / 越狱")
                    RowDivider()
                    KeyValueRow(title: "部署目标", value: "iOS 16.0+")
                    RowDivider()
                    KeyValueRow(title: "机型", value: "iPhone 14 Pro")
                }
            }
        }
    }

    // MARK: - 动作

    private func savePlan() {
        let normalized = planText.replacingOccurrences(of: ",", with: ".")
        guard let gb = Double(normalized), gb > 0 else {
            usage.setPlan(bytes: 0)
            return
        }
        usage.setPlan(bytes: UInt64(gb * 1024 * 1024 * 1024))
        syncPlanText()
    }

    private func syncPlanText() {
        guard usage.planBytes > 0 else {
            planText = ""
            return
        }
        let gb = Double(usage.planBytes) / 1024 / 1024 / 1024
        planText = gb == gb.rounded() ? String(Int(gb)) : String(format: "%.1f", gb)
    }
}
