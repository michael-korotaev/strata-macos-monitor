import AppKit
import StrataMonitorKit

/// Draws the menu bar item: an SF Symbol plus a monospaced tok/s number.
///
/// The menu bar cannot render a SwiftUI hierarchy, so the symbol and the digits
/// are composed into a single image, like other NSStatusItem apps do.
enum StatusImageRenderer {
    private struct Piece {
        var image: NSImage?
        var text: NSAttributedString?
        var size: NSSize
    }

    static func render(
        tint: StatusTint,
        symbol: String,
        tps: Double?,
        format: MenubarFormat
    ) -> NSImage? {
        let color: NSColor = switch tint {
        case .active: .systemGreen
        case .busy: .systemYellow
        case .idle: .secondaryLabelColor
        case .offline: .systemRed
        }

        let height: CGFloat = 16
        var pieces: [Piece] = []

        if format != .numberOnly, let image = symbolImage(named: symbol, color: color) {
            pieces.append(Piece(image: image, text: nil, size: image.size))
        }

        if format != .iconOnly, let tps {
            let text = NSAttributedString(
                string: String(format: "%.0f", tps),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: color
                ]
            )
            // Measure the width of the actual string: otherwise "150" is clipped to the width of "0".
            pieces.append(Piece(image: nil, text: text, size: text.size()))
        }

        guard !pieces.isEmpty else { return nil }
        return compose(pieces, color: color, height: height)
    }

    /// SF Symbol in the wanted colour: palette (a template fill is not drawn into a canvas at all).
    private static func symbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        image.isTemplate = false
        return image
    }

    private static func compose(_ pieces: [Piece], color: NSColor, height: CGFloat) -> NSImage {
        let gap: CGFloat = 3
        let width = pieces.reduce(CGFloat(0)) { $0 + $1.size.width } + gap * CGFloat(max(pieces.count - 1, 0))

        let canvas = NSImage(size: NSSize(width: max(width, 1), height: height))
        canvas.lockFocus()
        var x: CGFloat = 0
        for piece in pieces {
            if let text = piece.text {
                let rect = NSRect(x: x, y: (height - piece.size.height) / 2, width: piece.size.width, height: piece.size.height)
                text.draw(in: rect)
            } else if let image = piece.image {
                let rect = NSRect(x: x, y: (height - piece.size.height) / 2, width: piece.size.width, height: piece.size.height)
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            x += piece.size.width + gap
        }
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }
}
