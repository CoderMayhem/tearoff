import SwiftUI
import TearoffCore

/// How large each pad is drawn. Kept in the app target so the model stays free of layout.
extension PadSize {
    /// Visible pad width, excluding the transparent shadow margin.
    var padWidth: CGFloat {
        switch self {
        case .small: return 152
        case .medium: return 196
        case .large: return 248
        }
    }

    var headerHeight: CGFloat {
        switch self {
        case .small: return 34
        case .medium: return 42
        case .large: return 50
        }
    }

    var sheetHeight: CGFloat {
        switch self {
        case .small: return 172
        case .medium: return 218
        case .large: return 274
        }
    }

    var numeralSize: CGFloat {
        switch self {
        case .small: return 62
        case .medium: return 82
        case .large: return 106
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .small: return 9.5
        case .medium: return 11
        case .large: return 12.5
        }
    }

    var captionSize: CGFloat {
        switch self {
        case .small: return 7.5
        case .medium: return 8.5
        case .large: return 9.5
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .small: return 4.5
        case .medium: return 5.5
        case .large: return 6.5
        }
    }

    var corner: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 10
        case .large: return 12
        }
    }
}

/// Colour recipe for one paper stock. Pads keep their own colours in light and dark
/// appearance — they are objects sitting on the desktop, not chrome that should retheme.
struct PaperPalette {
    let sheet: Color
    let sheetEdge: Color      // the thin stacked edges under the top sheet
    let board: Color          // the bound header at the top of the pad
    let boardInk: Color
    let ink: Color
    let accent: Color

    static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: alpha)
    }

    static func palette(for style: PaperStyle) -> PaperPalette {
        switch style {
        case .cream:
            return PaperPalette(sheet: rgb(0xFBF7EF), sheetEdge: rgb(0xE6DECD), board: rgb(0x2E2A26),
                                boardInk: rgb(0xF3EDE1), ink: rgb(0x2A2622), accent: rgb(0xC0562B))
        case .sand:
            return PaperPalette(sheet: rgb(0xF4E9D6), sheetEdge: rgb(0xDCCDB2), board: rgb(0x4A3D2C),
                                boardInk: rgb(0xF6EEDF), ink: rgb(0x3A3125), accent: rgb(0xA9702A))
        case .sage:
            return PaperPalette(sheet: rgb(0xEBF1E9), sheetEdge: rgb(0xD1DDCD), board: rgb(0x2C3B31),
                                boardInk: rgb(0xEDF3EA), ink: rgb(0x243029), accent: rgb(0x3F7D58))
        case .sky:
            return PaperPalette(sheet: rgb(0xE9F0F7), sheetEdge: rgb(0xCEDCEA), board: rgb(0x25313E),
                                boardInk: rgb(0xEAF1F8), ink: rgb(0x1F2A35), accent: rgb(0x2E6DA4))
        case .blush:
            return PaperPalette(sheet: rgb(0xF9EBEA), sheetEdge: rgb(0xE7D1CF), board: rgb(0x3A2629),
                                boardInk: rgb(0xF9ECEA), ink: rgb(0x332326), accent: rgb(0xB44A5A))
        case .graphite:
            return PaperPalette(sheet: rgb(0x2B2C30), sheetEdge: rgb(0x1B1C1F), board: rgb(0x141518),
                                boardInk: rgb(0xE9E6DE), ink: rgb(0xEDEAE2), accent: rgb(0xE0A34A))
        }
    }
}

/// Deterministic small-integer noise so a pad's torn edge looks the same on every redraw.
struct Jitter {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFF) / Double(0xFFFF)
    }
}

/// A torn-paper edge: a shape whose top border is ragged, everything else square.
struct TornTopEdge: Shape {
    var seed: UInt64
    var depth: CGFloat = 3.5
    var step: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var jitter = Jitter(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + depth * 0.5))
        var x = rect.minX
        while x < rect.maxX {
            let nextX = min(x + step, rect.maxX)
            let y = rect.minY + CGFloat(jitter.next()) * depth
            path.addLine(to: CGPoint(x: nextX, y: y))
            x = nextX
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The ragged remains of already-torn sheets, still held by the binding.
struct TornBottomEdge: Shape {
    var seed: UInt64
    var depth: CGFloat = 4
    var step: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var jitter = Jitter(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        var x = rect.maxX
        path.addLine(to: CGPoint(x: x, y: rect.maxY - depth * 0.5))
        while x > rect.minX {
            let nextX = max(x - step, rect.minX)
            let y = rect.maxY - CGFloat(jitter.next()) * depth
            path.addLine(to: CGPoint(x: nextX, y: y))
            x = nextX
        }
        path.closeSubpath()
        return path
    }
}

extension Font {
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif).monospacedDigit()
    }
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
