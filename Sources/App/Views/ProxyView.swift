import SwiftUI

extension ProxyManager.Status {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

struct ProxyView: View {
    @EnvironmentObject private var proxy: ProxyManager
    @EnvironmentObject private var usage: UsageStore

    private var accent: Color { Theme.blue }

    private var statusColor: Color {
        if proxy.status.isConnected { return Theme.mint }
        if proxy.status.isError { return Theme.red }
        return Theme.text3
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "代理")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    metricRow
                    modeSection
                    serverSection
                    noteBanner
                    SectionFoot(text: "隧道骨架已就位，sing-box 内核尚未接入。接入点见 PacketTunnelProvider.swift 的 TODO。")
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await proxy.load() }
    }

    // MARK: 英雄卡

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(accent)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(accent.opacity(0.28), lineWidth: 0.8)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(proxy.status.label)
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(nodeText)
                        .font(Theme.num(12, .regular))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.7), radius: 4)
                    Text(proxy.status.isConnected ? "隧道" : "空闲")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(proxy.status.isConnected ? Theme.mint : Theme.text3)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(proxy.status.isConnected ? Theme.mint.opacity(0.14) : Color.white.opacity(0.05))
                )
            }

            HStack {
                Text("启用代理")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text2)
                Spacer()
                MintSwitch(isOn: proxy.status.isConnected || proxy.status.isConnecting, tint: accent) {
                    Task { await proxy.setEnabled(!(proxy.status.isConnected || proxy.status.isConnecting)) }
                }
            }
            .padding(.top, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.8)
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background {
            ZStack {
                LinearGradient(colors: [accent.opacity(0.14), Color(hex: 0x131A22), Color(hex: 0x11161C)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                RadialGradient(colors: [accent.opacity(0.12), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 0.8)
        )
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }

    private var nodeText: String {
        if proxy.status.isConnected || proxy.status.isConnecting {
            let host = proxy.serverAddress.isEmpty ? "未填写地址" : proxy.serverAddress
            return "\(host) · \(proxy.serverPort)"
        }
        return proxy.status.isError ? "配置异常，请检查" : "未建立隧道"
    }

    // MARK: 指标

    private var metricRow: some View {
        HStack(spacing: 10) {
            metric(label: "隧道状态",
                   value: proxy.status.isConnected ? "已连接" : "未连接",
                   valueColor: proxy.status.isConnected ? Theme.mint : Theme.text2)
            metric(label: "设备下行",
                   value: Fmt.bytesParts(UInt64(max(0, usage.downRate))).0,
                   unit: Fmt.bytesParts(UInt64(max(0, usage.downRate))).1 + "/s")
            metric(label: "内核", value: "未接入", valueColor: Theme.text2)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }

    private func metric(label: String, value: String, unit: String? = nil, valueColor: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.num(19, .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 0.8)
        )
    }

    // MARK: 分流模式

    private var modeSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "分流模式")
            HStack(spacing: 2) {
                ForEach(ProxyMode.allCases) { mode in
                    Button {
                        proxy.proxyMode = mode.rawValue
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(proxy.proxyMode == mode.rawValue ? Theme.text : Theme.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(proxy.proxyMode == mode.rawValue
                                          ? Color.white.opacity(0.12)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)
        }
    }

    // MARK: 服务器

    private var serverSection: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "服务器")
            Card {
                VStack(spacing: 0) {
                    fieldRow(title: "地址") {
                        TextField("example.com", text: $proxy.serverAddress)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(Theme.num(15, .regular))
                            .foregroundStyle(Theme.text)
                    }
                    RowDivider()
                    fieldRow(title: "端口") {
                        TextField("1080", value: $proxy.serverPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .font(Theme.num(15, .regular))
                            .foregroundStyle(Theme.text)
                    }
                    RowDivider()
                    ActionRow(icon: "checkmark.circle", title: "保存配置") {
                        Task { await proxy.configure() }
                    }
                }
            }
        }
    }

    private func fieldRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            content()
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.rowHeight)
    }

    @ViewBuilder
    private var noteBanner: some View {
        if proxy.status.isError {
            AlertBanner(level: .danger,
                        icon: "exclamationmark.triangle.fill",
                        title: "隧道配置异常",
                        detail: "检查 Network Extension entitlement 是否已写入，TrollStore 下 nehelper 可能拒绝加载扩展。")
        } else {
            AlertBanner(level: .info,
                        icon: "info.circle.fill",
                        title: "当前为占位实现",
                        detail: "隧道建立后暂不做转发，所有流量按直连处理。")
        }
    }
}

enum ProxyMode: String, CaseIterable, Identifiable {
    case rule, global, direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rule:   return "规则分流"
        case .global: return "全局"
        case .direct: return "直连"
        }
    }
}
