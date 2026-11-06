import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var usage: UsageStore

    // MARK: - 派生值

    private var used: UInt64 { usage.current.cellTotal }
    private var usedRatio: Double {
        guard usage.planBytes > 0 else { return 0 }
        return min(1, Double(used) / Double(usage.planBytes))
    }
    private var remainingRatio: Double { usage.remainingRatio ?? 1 }
    private var isLow: Bool { usage.planBytes > 0 && remainingRatio < 0.15 }

    private var accent: Color { isLow ? Theme.red : Theme.mint }

    /// 最近 24 天，按最大值为基准归一化。
    private var dailyValues: [Double] {
        let days = usage.recentDays(24)
        let peak = max(days.map { Double($0.cell) }.max() ?? 0, 1)
        return days.map { Double($0.cell) / peak }
    }

    private var dailyBuckets: [DailyBucket] { usage.recentDays(24) }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "概览") { usage.sample() }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    banner
                    detailSection
                    historySection
                    SectionFoot(text: "统计为网卡累计字节差分。iOS 不开放按 App 分项，设备重启后从 0 重新累加。")
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: - 英雄卡

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: accent.opacity(0.7), radius: 4)
                        Text("本月移动数据")
                            .font(Theme.caption)
                            .tracking(0.4)
                            .foregroundStyle(Theme.text2)
                    }
                    .padding(.bottom, 10)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.bytesParts(used).0)
                            .font(Theme.num(46, .semibold))
                            .tracking(-1.6)
                            .foregroundStyle(Theme.text)
                        Text(Fmt.bytesParts(used).1)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.text2)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    planLine
                        .padding(.top, 9)
                }

                Spacer(minLength: 0)

                RingGauge(progress: usedRatio, color: accent)
            }

            ratesRow
                .padding(.top, 18)

            sparkSection
        }
        .padding(20)
        .background {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x182029),
                                        Color(hex: 0x12171E),
                                        Color(hex: 0x10151B)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                RadialGradient(colors: [accent.opacity(0.18), .clear],
                               center: .topTrailing,
                               startRadius: 0,
                               endRadius: 180)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                .strokeBorder(isLow ? Theme.red.opacity(0.24) : Theme.line2, lineWidth: 0.8)
        )
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var planLine: some View {
        if usage.planBytes > 0 {
            HStack(spacing: 4) {
                Text("套餐 \(Fmt.bytes(usage.planBytes)) · 剩余")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                Text(Fmt.bytes(usage.remainingBytes))
                    .font(Theme.num(12.5, .semibold))
                    .foregroundStyle(isLow ? Color(hex: 0xFF9A93) : Theme.text)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text("尚未设置套餐上限")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text3)
        }
    }

    private var ratesRow: some View {
        HStack(spacing: 10) {
            rateItem(icon: "arrow.down", value: usage.downRate, tint: Theme.mint)
            rateItem(icon: "arrow.up", value: usage.upRate, tint: Theme.blue)
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.8)
        }
    }

    private func rateItem(icon: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(Fmt.rate(value))
                .font(Theme.num(12.5, .medium))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sparkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Sparkline(values: dailyValues, accent: accent)
                .frame(height: 44)
                .padding(.top, 10)

            HStack {
                Text(dayLabel(dailyBuckets.first?.day))
                Spacer()
                Text(dayLabel(dailyBuckets.dropFirst(8).first?.day))
                Spacer()
                Text(dayLabel(dailyBuckets.dropFirst(16).first?.day))
                Spacer()
                Text("今天")
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.text3)
            .monospacedDigit()
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.8)
        }
    }

    private func dayLabel(_ day: String?) -> String {
        guard let day, day.count == 10 else { return "" }
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return "" }
        return "\(parts[1])/\(parts[2])"
    }

    // MARK: - 提示

    @ViewBuilder
    private var banner: some View {
        if usage.projectedOverage > 0 {
            AlertBanner(level: isLow ? .danger : .warning,
                        icon: "exclamationmark.triangle.fill",
                        title: "按当前速度，月底将超出 \(Fmt.bytes(usage.projectedOverage))",
                        detail: overageDetail)
        } else if usage.planBytes == 0 {
            AlertBanner(level: .info,
                        icon: "info.circle.fill",
                        title: "设置套餐上限后可查看余量与超支预测",
                        detail: "在「设置」里填每月流量额度即可。")
        }
    }

    private var overageDetail: String {
        let calendar = Calendar.current
        let day = max(calendar.component(.day, from: Date()), 1)
        let perDay = usage.current.cellTotal / UInt64(day)
        return "日均 \(Fmt.bytes(perDay)) · 距月底 \(remainingDays) 天"
    }

    private var remainingDays: Int {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: Date()) else { return 0 }
        return max(range.count - calendar.component(.day, from: Date()), 0)
    }

    // MARK: - 明细

    private var detailSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "本月明细")
            Card {
                VStack(spacing: 0) {
                    KeyValueRow(title: "移动数据 · 下行", value: Fmt.bytes(usage.current.cellIn))
                    RowDivider()
                    KeyValueRow(title: "移动数据 · 上行", value: Fmt.bytes(usage.current.cellOut))
                    RowDivider()
                    KeyValueRow(title: "Wi-Fi · 下行", value: Fmt.bytes(usage.current.wifiIn))
                    RowDivider()
                    KeyValueRow(title: "Wi-Fi · 上行", value: Fmt.bytes(usage.current.wifiOut))
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !usage.history.isEmpty {
            VStack(spacing: 0) {
                SectionLabel(text: "历史月份")
                Card {
                    VStack(spacing: 0) {
                        ForEach(usage.history.reversed()) { bucket in
                            if bucket.id != usage.history.last?.id { RowDivider() }
                            KeyValueRow(title: bucket.key,
                                        value: Fmt.bytes(bucket.cellTotal))
                        }
                    }
                }
            }
        }
    }
}
