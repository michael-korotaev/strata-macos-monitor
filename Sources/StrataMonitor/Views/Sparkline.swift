import SwiftUI

/// Chart over a sample array (null = gap).
struct Sparkline: View {
    var values: [Double?]
    var color: Color = .accentColor
    var lineWidth: CGFloat = 1.5
    /// Fill under the line.
    var filled: Bool = true

    var body: some View {
        Canvas { context, size in
            let points = values.compactMap { $0 }
            guard points.count > 1 else { return }
            let maxValue = points.max() ?? 1
            let minValue = min(points.min() ?? 0, 0)
            let span = max(maxValue - minValue, 1)
            let stepX = size.width / CGFloat(points.count - 1)

            func position(_ index: Int, _ value: Double) -> CGPoint {
                let x = CGFloat(index) * stepX
                let y = size.height * (1 - CGFloat((value - minValue) / span))
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: position(0, points[0]))
            for index in points.indices.dropFirst() {
                path.addLine(to: position(index, points[index]))
            }

            if filled {
                var area = path
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.18)))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Thin "how much is used" bar (GPU, VRAM, RAM).
struct MeterBar: View {
    var value: Double?      // 0...100
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
    }

    private var fraction: CGFloat {
        guard let value else { return 0 }
        return CGFloat(max(0, min(100, value)) / 100)
    }
}
