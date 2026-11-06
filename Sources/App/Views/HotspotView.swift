import SwiftUI

// MARK: - 状态模型

@MainActor
final class HotspotModel: ObservableObject {
    @Published var state = HotspotState()
    @Published var clients: [HotspotClient] = []
    @Published var blockedMACs: Set<String> = []
    @Published var message: String?
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let blockKey = "netpilot.hotspot.blocked"
    private var timer: Timer?

    init() {
        if let saved = defaults.array(forKey: blockKey) as? [String] {
            blockedMACs = Set(saved)
        }
    }

    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        state = HotspotMonitor.shared.read()
        var list = HotspotClients.list()
        for index in list.indices {
            list[index].isBlocked = blockedMACs.contains(list[index].mac)
        }
        clients = list
    }

    func setEnabled(_ enabled: Bool) {
        isBusy = true
        let outcome = HotspotController.setEnabled(enabled)
        isBusy = false
        switch outcome {
        case .success:
            message = nil
            refresh()
        case .failed(let reason):
            message = "开启失败：\(reason)"
        case .needsManual(let reason):
            message = reason
            HotspotController.openSystemHotspotSettings()
        }
    }

    func toggleBlock(_ client: HotspotClient) {
        if blockedMACs.contains(client.mac) {
            blockedMACs.remove(client.mac)
        } else {
            blockedMACs.insert(client.mac)
        }
        defaults.set(Array(blockedMACs), forKey: blockKey)
        pushRules()
        refresh()
    }

    /// 把「被拉黑的 MAC」翻译成「这些 MAC 当前的 IP」，再下发给 pf。
    private func pushRules() {
        let ips = clients.filter { blockedMACs.contains($0.mac) }.map(\.ip)
        let result = ClientBlocker.apply(blockedIPs: ips)
        if !result.isSuccess {
            message = "规则下发失败：\(result.output)"
        }
    }

    func clearRules() {
        ClientBlocker.clearAll()
        blockedMACs.removeAll()
        defaults.set([], forKey: blockKey)
        message = nil
        refresh()
    }
}

// MARK: - 页面

struct HotspotView: View {
    @EnvironmentObject private var usage: UsageStore
    @StateObject private var model = HotspotModel()

    private var todayCell: UInt64 {
        usage.recentDays(1).first?.cell ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "热点") { model.refresh() }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    banners
                    deviceSection
                    maintenanceSection
                    SectionFoot(text: "拦截通过 pf 在热点网桥上阻断该 IP 的全部出入流量。设备重新获取 IP 后 5 秒内自动同步规则。")
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: 英雄卡

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "personalhotspot")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(model.state.isEnabled ? Theme.mint : Theme.text3)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(model.state.isEnabled ? Theme.mint.opacity(0.16) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(model.state.isEnabled ? Theme.mint.opacity(0.25) : Theme.line,
                                          lineWidth: 0.8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("个人热点")
                        .font(Theme.subhead)
                        .foregroundStyle(Theme.text)
                    Text(stateText)
                        .font(.system(size: 12))
                        .foregroundStyle(model.state.isEnabled ? Theme.mint : Theme.text3)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                MintSwitch(isOn: model.state.isEnabled) {
                    model.setEnabled(!model.state.isEnabled)
                }
                .disabled(model.isBusy)
            }

            HStack(spacing: 10) {
                statItem(label: "在线设备", value: "\(model.state.connectedCount)",
                        unit: model.state.maxCount > 0 ? "/\(model.state.maxCount)" : "")
                statItem(label: "今日移动数据", value: Fmt.bytesParts(todayCell).0,
                         unit: Fmt.bytesParts(todayCell).1)
            }
            .padding(.top, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.8)
            }
            .padding(.top, 18)
        }
        .padding(20)
        .background {
            ZStack {
                LinearGradient(colors: model.state.isEnabled
                               ? [Theme.mint.opacity(0.13), Color(hex: 0x131A21), Color(hex: 0x11161C)]
                               : [Color(hex: 0x171D24), Color(hex: 0x131820), Color(hex: 0x11161C)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                if model.state.isEnabled {
                    RadialGradient(colors: [Theme.mint.opacity(0.13), .clear],
                                   center: .bottom, startRadius: 0, endRadius: 200)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                .strokeBorder(model.state.isEnabled ? Theme.mint.opacity(0.22) : Theme.line2, lineWidth: 0.8)
        )
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }

    private var stateText: String {
        if model.isBusy { return "正在切换…" }
        guard model.state.isReadable else { return "状态接口不可读（需越狱权限）" }
        if model.state.isEnabled {
            return "已开启 · \(model.state.connectedCount) 台设备连接"
        }
        return "已关闭"
    }

    private func statItem(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.num(17, .semibold))
                    .foregroundStyle(Theme.text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 提示

    @ViewBuilder
    private var banners: some View {
        if let message = model.message {
            AlertBanner(level: .warning,
                        icon: "exclamationmark.triangle.fill",
                        title: message,
                        detail: nil)
        }

        if !model.state.isReadable {
            AlertBanner(level: .info,
                        icon: "info.circle.fill",
                        title: "iOS 不允许第三方 App 直接开关热点",
                        detail: "将依次尝试动态存储写入 → root helper，均失败时跳转系统设置页。")
        }
    }

    // MARK: 设备

    private var deviceSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "已连接设备")

            if model.clients.isEmpty {
                EmptyStateView(icon: model.state.isEnabled ? "wifi.slash" : "personalhotspot",
                               title: "暂无连接设备",
                               detail: model.state.isEnabled
                               ? "读取失败通常是缺少越狱权限，无法访问 DHCP 租约。"
                               : "开启热点后，接入的设备会出现在这里，可单独拦截其上网。")
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(model.clients) { client in
                            if client.id != model.clients.first?.id { RowDivider() }
                            DeviceRow(client: client) {
                                model.toggleBlock(client)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 维护

    private var maintenanceSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "维护")
            Card {
                VStack(spacing: 0) {
                    ActionRow(icon: "trash", title: "清空全部拦截规则", tint: Theme.red) {
                        model.clearRules()
                    }
                    RowDivider()
                    ActionRow(icon: "terminal", title: "查看当前 pf 规则") {
                        let dump = ClientBlocker.dumpRules()
                        model.message = dump.isEmpty ? "pf 未返回任何规则。" : dump
                    }
                }
            }
        }
    }
}

// MARK: - 设备行

struct DeviceRow: View {
    var client: HotspotClient
    var onToggle: () -> Void

    private var icon: String {
        if client.isBlocked { return "wifi.slash" }
        let name = client.name.lowercased()
        if name.contains("mac") || name.contains("book") { return "laptopcomputer" }
        if name.contains("ipad") || name.contains("pad") { return "ipad" }
        if name.contains("iphone") { return "iphone" }
        return "desktopcomputer"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(client.isBlocked ? Theme.red : Theme.text2)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(client.isBlocked ? Theme.red.opacity(0.09) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(client.isBlocked ? Theme.red.opacity(0.22) : Theme.line, lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(client.isBlocked ? Theme.text3 : Theme.text)
                    .strikethrough(client.isBlocked, color: Theme.red.opacity(0.5))
                    .lineLimit(1)

                Text(metaText)
                    .font(Theme.num(11, .regular))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onToggle) {
                Text(client.isBlocked ? "解除" : "拉黑")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(client.isBlocked ? Color(hex: 0xFF9A93) : Theme.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(client.isBlocked ? Theme.red.opacity(0.16) : Theme.red.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(client.isBlocked ? Color.clear : Theme.red.opacity(0.42), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 62)
    }

    private var metaText: String {
        client.mac.isEmpty ? client.ip : "\(client.ip) · \(client.mac)"
    }
}
