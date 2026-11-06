import SwiftUI

/// 设计令牌。
///
/// 所有颜色、字号、间距都从这里取，不在视图里写死字面量。
/// 深色是这个 App 的唯一形态（网络工具的常态使用场景是夜间/常驻），
/// 所以不做双主题，直接锁 `preferredColorScheme(.dark)`。
enum Theme {

    // MARK: - 背景与容器

    /// 页面底色，比纯黑略偏蓝，避免 OLED 上「卡片浮在虚空」的观感。
    static let bg      = Color(hex: 0x080B11)
    /// 卡片底。
    static let card    = Color(hex: 0x141A22)
    /// 标签栏底。
    static let bar     = Color(hex: 0x0C1015)
    /// 发丝线。
    static let line    = Color.white.opacity(0.075)
    /// 略强一点的描边，用在英雄卡上。
    static let line2   = Color.white.opacity(0.12)

    // MARK: - 文字

    static let text    = Color(hex: 0xF3F6FA)
    static let text2   = Color(hex: 0x8C96A5)
    static let text3   = Color(hex: 0x5A6473)

    // MARK: - 语义色

    /// 唯一强调色：只表示「通路 / 正常 / 可用」。
    static let mint    = Color(hex: 0x2EE6A8)
    /// 代理域专用，避免两个绿色开关分不清。
    static let blue    = Color(hex: 0x5AA2FF)
    /// 预警。
    static let amber   = Color(hex: 0xFFB020)
    /// 危险与拦截。
    static let red     = Color(hex: 0xFF4A3D)

    // MARK: - 度量

    static let cardRadius: CGFloat = 16
    static let heroRadius: CGFloat = 20
    static let gutter: CGFloat = 16
    static let rowHeight: CGFloat = 48

    // MARK: - 字体

    /// 页面大标题。
    static let title   = Font.system(size: 33, weight: .bold)
    /// 卡片主标题。
    static let subhead = Font.system(size: 15, weight: .semibold)
    /// 正文。
    static let body    = Font.system(size: 15, weight: .regular)
    /// 表头 / 小标签。
    static let caption = Font.system(size: 12, weight: .semibold)
    /// 页脚说明。
    static let foot    = Font.system(size: 11.5, weight: .regular)

    /// 等宽数字字体。速率每秒刷新，不做等宽会整行抖动。
    static func num(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - 数值格式化

enum Fmt {

    /// 拆成「数值 + 单位」两段，方便排版时单位用小字号。
    static func bytesParts(_ value: UInt64) -> (String, String) {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var i = 0
        while v >= 1024, i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return ("\(value)", "B") }
        let digits = v >= 100 ? 1 : 2
        return (String(format: "%.\(digits)f", v), units[i])
    }

    static func bytes(_ value: UInt64) -> String {
        let parts = bytesParts(value)
        return "\(parts.0) \(parts.1)"
    }

    /// 字节/秒 → 可读速率。
    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < 1024 { return String(format: "%.0f B/s", v) }
        if v < 1024 * 1024 { return String(format: "%.0f KB/s", v / 1024) }
        return String(format: "%.2f MB/s", v / 1024 / 1024)
    }
}
