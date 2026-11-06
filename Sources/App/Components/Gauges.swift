import SwiftUI

/// 环形进度。环内显示百分比，不带任何装饰性渐变。
struct RingGauge: View {
    /// 0...1，表示「已用」比例。
    var progress: Double
    var color: Color = Theme.mint
    var diameter: CGFloat = 96
    var lineWidth: CGFloat = 9

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int((clamped * 100).rounded()))")
                    .font(Theme.num(19, .semibold))
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.text2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 每日用量柱状图。
///
/// 不给 `values` 补数据源之外的假设：传进来的每个值都是 0...1 的相对高度，
/// 由调用方决定归一化基准。
struct Sparkline: View {
    var values: [Double]
    var accent: Color = Theme.mint
    /// 最后一根（今天）是否用强调色突出。
    var highlightLast: Bool = true
    var barSpacing: CGFloat = 3
    var cornerRadius: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let totalSpacing = barSpacing * CGFloat(count - 1)
            let barWidth = max(2, (geo.size.width - totalSpacing) / CGFloat(count))

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<values.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill(for: index))
                        .frame(width: barWidth,
                               height: max(3, geo.size.height * min(max(values[index], 0), 1)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }

    private func fill(for index: Int) -> Color {
        guard index == values.count - 1, highlightLast else {
            return Color.white.opacity(0.13)
        }
        return accent
    }
}
