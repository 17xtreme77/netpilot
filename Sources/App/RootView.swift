import SwiftUI

struct RootView: View {
    @EnvironmentObject private var usage: UsageStore

    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("概览", systemImage: "chart.bar.fill") }

            HotspotView()
                .tabItem { Label("热点", systemImage: "personalhotspot") }

            ProxyView()
                .tabItem { Label("代理", systemImage: "shield.lefthalf.filled") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .onAppear { usage.startSampling(interval: 1.0) }
        .onDisappear { usage.stopSampling() }
    }
}

// MARK: - 概览

struct OverviewView: View {
    @EnvironmentObject private var usage: UsageStore

    private var cellUsed: UInt64 { usage.current.cellTotal }
    private var wifiUsed: UInt64 { usage.current.wifiTotal }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本月移动数据")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(cellUsed.byteString)
                            .font(.system(size: 40, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        HStack(spacing: 16) {
                            rateLabel(arrow: "arrow.down", value: usage.downRate)
                            rateLabel(arrow: "arrow.up", value: usage.upRate)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 8)

                    if let ratio = usage.remainingRatio {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: 1 - ratio)
                                .tint(ratio < 0.15 ? .red : .accentColor)
                            HStack {
                                Text("剩余 \(usage.remainingBytes.byteString)")
                                Spacer()
                                Text("已用 \(Int((1 - ratio) * 100))%")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if usage.projectedOverage > 0 {
                                Label("按当前速度，月底将超出 \(usage.projectedOverage.byteString)",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Button("设置本月套餐上限") { }
                            .font(.footnote)
                    }
                }

                Section("本月明细") {
                    usageRow("移动数据下行", usage.current.cellIn)
                    usageRow("移动数据上行", usage.current.cellOut)
                    usageRow("Wi-Fi 下行", usage.current.wifiIn)
                    usageRow("Wi-Fi 上行", usage.current.wifiOut)
                }

                if !usage.history.isEmpty {
                    Section("历史") {
                        ForEach(usage.history.reversed()) { bucket in
                            HStack {
                                Text(bucket.key)
                                Spacer()
                                Text(bucket.cellTotal.byteString)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section {
                    Text("统计为网卡累计字节差分，设备重启后从 0 重新累加。iOS 不开放按 App 分项统计，所以这里只有总量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("概览")
        }
    }

    private func rateLabel(arrow: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: arrow)
                .font(.caption2)
            Text(UInt64(value).byteString + "/s")
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private func usageRow(_ title: String, _ value: UInt64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.byteString)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - 热点

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
        refresh()
    }
}

struct HotspotView: View {
    @StateObject private var model = HotspotModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { model.state.isEnabled },
                        set: { model.setEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("个人热点")
                            Text(model.state.isEnabled
                                 ? "已开启 · \(model.state.connectedCount) 台设备连接"
                                 : "已关闭")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.isBusy)

                    Button {
                        HotspotController.openSystemHotspotSettings()
                    } label: {
                        Label("打开系统热点设置", systemImage: "arrow.up.forward.app")
                    }
                } header: {
                    Text("热点控制")
                } footer: {
                    Text("iOS 没有公开 API 开关热点。App 会依次尝试私有接口和 root helper，都失败时自动跳到系统设置页。")
                }

                if let message = model.message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    if model.clients.isEmpty {
                        ContentUnavailableView("暂无连接设备",
                                               systemImage: "wifi.slash",
                                               description: Text("热点开启后这里会列出已连接的设备。读取失败通常是因为缺少越狱权限。"))
                            .frame(height: 160)
                    } else {
                        ForEach(model.clients) { client in
                            clientRow(client)
                        }
                    }
                } header: {
                    Text("已连接设备")
                } footer: {
                    Text("拉黑会通过 pf 阻断该 IP 的全部出入流量。设备重新获取 IP 后需要重新下发，App 每 5 秒自动同步。")
                }

                Section {
                    Button("清空全部拉黑规则", role: .destructive) {
                        model.clearRules()
                    }
                    Button("查看当前 pf 规则") {
                        model.message = ClientBlocker.dumpRules()
                    }
                }
            }
            .navigationTitle("热点")
            .onAppear { model.start() }
            .onDisappear { model.stop() }
        }
    }

    private func clientRow(_ client: HotspotClient) -> some View {
        HStack(spacing: 12) {
            Image(systemName: client.isBlocked ? "wifi.slash" : "laptopcomputer")
                .foregroundStyle(client.isBlocked ? .red : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(client.displayName)
                    .font(.subheadline)
                Text("\(client.ip)\(client.mac.isEmpty ? "" : " · " + client.mac)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(client.isBlocked ? "解除" : "拉黑") {
                model.toggleBlock(client)
            }
            .buttonStyle(.bordered)
            .tint(client.isBlocked ? .accentColor : .red)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 代理

struct ProxyView: View {
    @EnvironmentObject private var proxy: ProxyManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(proxy.status.label)
                            .foregroundStyle(proxy.status.isConnected ? .green : .secondary)
                    }

                    Toggle("启用代理", isOn: Binding(
                        get: { proxy.status.isConnected || proxy.status.isConnecting },
                        set: { value in Task { await proxy.setEnabled(value) } }
                    ))
                }

                Section("服务器") {
                    TextField("地址", text: $proxy.serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Text("端口")
                        Spacer()
                        TextField("1080", value: $proxy.serverPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    Picker("模式", selection: $proxy.proxyMode) {
                        Text("规则分流").tag("rule")
                        Text("全局").tag("global")
                        Text("直连").tag("direct")
                    }
                }

                Section {
                    Button("保存配置") {
                        Task { await proxy.configure() }
                    }
                } footer: {
                    Text("隧道骨架已就位，代理内核（sing-box / Xray）尚未接入。接入点见 PacketTunnelProvider.swift 的 TODO。")
                }
            }
            .navigationTitle("代理")
            .task {
                await proxy.load()
            }
        }
    }
}

extension ProxyManager.Status {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject private var usage: UsageStore

    @State private var planGB: Double = 0

    var body: some View {
        NavigationStack {
            List {
                Section("套餐") {
                    HStack {
                        Text("每月流量上限")
                        Spacer()
                        TextField("0", value: $planGB, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                        Text("GB").foregroundStyle(.secondary)
                    }
                    Button("保存") {
                        usage.setPlan(bytes: UInt64(planGB * 1024 * 1024 * 1024))
                    }
                }

                Section("维护") {
                    Button("重置本月统计", role: .destructive) {
                        usage.resetCurrentMonth()
                    }
                    Button("检查越狱权限") {
                        // 简单自检：能否读到 hotspots 状态与 leases
                        _ = HotspotMonitor.shared.read()
                        _ = HotspotClients.list()
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    LabeledContent("构建方式", value: "TrollStore / 越狱")
                    LabeledContent("pf 可用", value: ClientBlocker.isAvailable() ? "是" : "否")
                    LabeledContent("热点接口",
                                   value: HotspotMonitor.shared.read().isReadable ? "可读" : "不可读")
                }
            }
            .navigationTitle("设置")
            .onAppear {
                planGB = Double(usage.planBytes) / 1024 / 1024 / 1024
            }
        }
    }
}
