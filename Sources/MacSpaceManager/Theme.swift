import SwiftUI
import SpaceCore

/// A bright, high-contrast color with the label color that stays readable on top of it.
struct Swatch: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Relative luminance (WCAG) used to decide between dark and light labels.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Picks whichever of black/white has the higher contrast ratio.
    var label: Color {
        let contrastWithWhite = 1.05 / (luminance + 0.05)
        let contrastWithBlack = (luminance + 0.05) / 0.05
        return contrastWithBlack > contrastWithWhite ? Color.black.opacity(0.85) : .white
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: min(1, red + 0.08), green: min(1, green + 0.08), blue: min(1, blue + 0.08)), color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum Palette {
    // Bright system-style hues.
    static let blue = Swatch(red: 0.04, green: 0.52, blue: 1.00)
    static let orange = Swatch(red: 1.00, green: 0.58, blue: 0.00)
    static let pink = Swatch(red: 1.00, green: 0.18, blue: 0.47)
    static let purple = Swatch(red: 0.69, green: 0.32, blue: 0.87)
    static let yellow = Swatch(red: 1.00, green: 0.80, blue: 0.00)
    static let teal = Swatch(red: 0.19, green: 0.69, blue: 0.78)
    static let red = Swatch(red: 1.00, green: 0.27, blue: 0.23)
    static let indigo = Swatch(red: 0.35, green: 0.34, blue: 0.84)
    static let green = Swatch(red: 0.20, green: 0.78, blue: 0.35)
    static let mint = Swatch(red: 0.00, green: 0.78, blue: 0.75)
    static let cyan = Swatch(red: 0.20, green: 0.68, blue: 0.90)
    static let gray = Swatch(red: 0.56, green: 0.56, blue: 0.58)
    static let free = Swatch(red: 0.86, green: 0.88, blue: 0.91)

    /// Rotation used for treemap tiles.
    static let tiles: [Swatch] = [blue, orange, pink, green, purple, yellow, teal, red, indigo, mint, cyan]

    static func swatch(for category: UsageCategory) -> Swatch {
        switch category {
        case .applications: return blue
        case .documents: return orange
        case .media: return pink
        case .developer: return purple
        case .cachesAndLogs: return yellow
        case .mailAndMessages: return teal
        case .trash: return red
        case .other: return indigo
        case .system: return gray
        case .free: return free
        }
    }

    static func color(for safety: CleanupSafety) -> Color {
        safety == .safe ? green.color : orange.color
    }
}

extension View {
    /// Liquid Glass surface on macOS 26+, translucent material on earlier releases.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        #else
        self.background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        #endif
    }

    /// Standard padded card used across the app.
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding).glassSurface()
    }
}

extension Int64 {
    var formattedBytes: String { ByteFormat.string(self) }
}
