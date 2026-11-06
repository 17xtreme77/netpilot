import SwiftUI

// MARK: - 卡片容器

/// 深色卡片。统一承担圆角、描边、外边距，视图里不再各自处理。
struct Card<Content: View>: View {
    var padding: CGFloat?
    @ViewBuilder var content: Content

    init(padding: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 0.8)
        )
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }
}

/// 卡片内的一条「标题 — 值」。
struct KeyValueRow: View {
    var title: String
    var value: String
    var valueColor: Color = Theme.text2

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.num(15, .regular))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.rowHeight)
    }
}

/// 图标 + 标题的可点击行。
struct ActionRow: View {
    var icon: String
    var title: String
    var tint: Color = Theme.text
    var trailing: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 20)
                    .opacity(0.85)
                Text(title)
                    .font(Theme.body)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(Theme.num(13, .regular))
                        .foregroundStyle(Theme.text3)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(height: Theme.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RowDivider: View {
    var inset: CGFloat = 16
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 0.8)
            .padding(.leading, inset)
    }
}

// MARK: - 分区标题

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Theme.caption)
            .tracking(0.7)
            .foregroundStyle(Theme.text3)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}

struct SectionFoot: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Theme.foot)
            .foregroundStyle(Theme.text3)
            .lineSpacing(2.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
    }
}

// MARK: - 页面标题

struct PageHeader: View {
    var title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            Text(title)
                .font(Theme.title)
                .tracking(-0.8)
                .foregroundStyle(Theme.text)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }
}

// MARK: - 提示条

struct AlertBanner: View {
    enum Level { case warning, danger, info }

    var level: Level = .warning
    var icon: String = "exclamationmark.triangle.fill"
    var title: String
    var detail: String?

    private var accent: Color {
        switch level {
        case .warning: return Theme.amber
        case .danger:  return Theme.red
        case .info:    return Theme.text2
        }
    }

    private var titleColor: Color {
        switch level {
        case .warning: return Color(hex: 0xFFD08A)
        case .danger:  return Color(hex: 0xFF9A93)
        case .info:    return Theme.text2
        }
    }

    private var detailColor: Color {
        switch level {
        case .warning: return Color(hex: 0xFFD08A).opacity(0.62)
        case .danger:  return Color(hex: 0xFF9A93).opacity(0.6)
        case .info:    return Theme.text3
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.foot)
                        .foregroundStyle(detailColor)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(accent.opacity(level == .info ? 0.06 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 0.8)
        )
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }
}

// MARK: - 开关

/// 薄荷绿自定义开关。系统 Toggle 在深色卡里对比度不够，且没法做发光。
struct MintSwitch: View {
    var isOn: Bool
    var tint: Color = Theme.mint
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? tint : Color.white.opacity(0.14))
                .frame(width: 51, height: 31)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 27, height: 27)
                        .shadow(color: .black.opacity(0.3), radius: 2.5, y: 1)
                        .padding(2)
                }
                .shadow(color: isOn ? tint.opacity(0.4) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Theme.text3)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .padding(.bottom, 2)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text2)

            Text(detail)
                .font(Theme.foot)
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.014))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 0.8, dash: [5, 4]))
        )
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }
}

// MARK: - 徽标

struct Badge: View {
    var text: String
    var color: Color
    var filled: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(filled ? 0.14 : 0))
            )
    }
}

/// 状态圆点。
struct StatusDot: View {
    var ok: Bool
    var body: some View {
        Circle()
            .fill(ok ? Theme.mint : Theme.red)
            .frame(width: 6, height: 6)
            .shadow(color: (ok ? Theme.mint : Theme.red).opacity(0.6), radius: 4)
    }
}
