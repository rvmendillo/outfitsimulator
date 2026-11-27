import OutfitKit
import SwiftUI
import UIKit

/// OutfitSim visual identity: warm coral-to-raspberry gradient, cream canvas,
/// deep plum ink, serif display type.
enum Brand {
    static let appName = "OutfitSim"
    static let tagline = "Your closet, on you."

    static let coral = Color(red: 1.0, green: 0.353, blue: 0.306)        // #FF5A4E
    static let raspberry = Color(red: 0.839, green: 0.169, blue: 0.478)  // #D62B7A
    static let tangerine = Color(red: 1.0, green: 0.478, blue: 0.271)    // #FF7A45
    static let lilac = Color(red: 0.725, green: 0.655, blue: 1.0)        // #B9A7FF
    static let sage = Color(red: 0.42, green: 0.62, blue: 0.45)

    static let ink = Color(uiColor: dynamic(light: 0x17131F, dark: 0xF7F3EE))
    static let secondaryInk = Color(uiColor: dynamic(light: 0x6E6577, dark: 0xB9B0C2))
    /// Page background.
    static let canvas = Color(uiColor: dynamic(light: 0xF7F3EE, dark: 0x17131F))
    /// Raised surfaces.
    static let card = Color(uiColor: dynamic(light: 0xFFFFFF, dark: 0x241F2E))
    static let blush = Color(uiColor: dynamic(light: 0xFFE6DE, dark: 0x3B2631))
    static let hairline = Color(uiColor: dynamic(light: 0xE7DFD6, dark: 0x3A3346))

    static let gradient = LinearGradient(colors: [tangerine, coral, raspberry], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let cornerRadius: CGFloat = 20

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(_ rgb: SRGBColor) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }
}

extension SRGBColor {
    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 0
            ui.getWhite(&white, alpha: &a)
            r = white; g = white; b = white
        }
        self.init(r: Double(r), g: Double(g), b: Double(b))
    }
}

// MARK: - Logo

/// The OutfitSim hanger, drawn from the same geometry as the app icon.
struct HangerShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 1024 * rect.width, y: rect.minY + y / 1024 * rect.height)
        }
        var path = Path()
        // Hook
        path.move(to: p(512, 452))
        path.addCurve(to: p(566, 372), control1: p(512, 412), control2: p(548, 398))
        path.addCurve(to: p(528, 286), control1: p(586, 343), control2: p(572, 296))
        path.addCurve(to: p(456, 338), control1: p(488, 277), control2: p(456, 302))
        // Body
        path.move(to: p(512, 452))
        path.addLine(to: p(222, 664))
        path.addCurve(to: p(242, 720), control1: p(196, 683), control2: p(210, 720))
        path.addLine(to: p(782, 720))
        path.addCurve(to: p(802, 664), control1: p(814, 720), control2: p(828, 683))
        path.closeSubpath()
        return path
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 1024 * rect.width, y: rect.minY + y / 1024 * rect.height)
        }
        var path = Path()
        path.move(to: p(752, 250))
        path.addCurve(to: p(826, 324), control1: p(760, 300), control2: p(776, 316))
        path.addCurve(to: p(752, 398), control1: p(776, 332), control2: p(760, 348))
        path.addCurve(to: p(678, 324), control1: p(744, 348), control2: p(728, 332))
        path.addCurve(to: p(752, 250), control1: p(728, 316), control2: p(744, 300))
        path.closeSubpath()
        return path
    }
}

/// Logo mark: hanger + sparkle.
struct LogoMark: View {
    var size: CGFloat = 64
    var color: Color = .white

    var body: some View {
        ZStack {
            HangerShape()
                .stroke(color, style: StrokeStyle(lineWidth: size * 54 / 1024, lineCap: .round, lineJoin: .round))
            SparkleShape().fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The app icon as a view (gradient tile + mark).
struct AppIconTile: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Brand.gradient)
            LogoMark(size: size, color: Color(red: 1, green: 0.965, blue: 0.933))
        }
        .frame(width: size, height: size)
        .shadow(color: Brand.coral.opacity(0.35), radius: size * 0.12, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            Text("Outfit").font(Brand.display(size, weight: .bold)).foregroundStyle(Brand.ink)
            Text("Sim").font(Brand.display(size, weight: .bold)).foregroundStyle(Brand.gradient)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.appName)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(Brand.gradient))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Brand.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(Brand.card))
            .overlay(Capsule().strokeBorder(Brand.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var brandPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var brandSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Small components

/// SF Symbol for a category, falling back when the OS lacks the symbol.
struct CategoryIcon: View {
    let category: GarmentCategory

    var body: some View {
        Image(systemName: Self.symbol(for: category))
    }

    static func symbol(for category: GarmentCategory) -> String {
        UIImage(systemName: category.symbolName) != nil ? category.symbolName : GarmentCategory.fallbackSymbolName
    }
}

struct Chip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.caption.weight(.semibold)) }
            Text(title).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(isSelected ? Color.white : Brand.ink)
        .background(Capsule().fill(isSelected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.card)))
        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Brand.hairline, lineWidth: 1))
    }
}

/// Light checkerboard shown behind transparent cut-outs.
struct Checkerboard: View {
    var squareSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let light = Color(uiColor: Brand.dynamic(light: 0xFFFFFF, dark: 0x2B2535))
            let dark = Color(uiColor: Brand.dynamic(light: 0xF0EBE5, dark: 0x332C3E))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            let cols = Int(size.width / squareSize) + 1, rows = Int(size.height / squareSize) + 1
            var path = Path()
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 1 {
                    path.addRect(CGRect(x: CGFloat(c) * squareSize, y: CGFloat(r) * squareSize, width: squareSize, height: squareSize))
                }
            }
            context.fill(path, with: .color(dark))
        }
        .accessibilityHidden(true)
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous).fill(Brand.card))
            .overlay(RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous).strokeBorder(Brand.hairline, lineWidth: 1))
    }
}

extension View {
    func brandCard() -> some View { modifier(CardModifier()) }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Brand.display(22)).foregroundStyle(Brand.ink)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Brand.secondaryInk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Branded empty state.
struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var actionIdentifier: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            AppIconTile(size: 84)
            Text(title).font(Brand.display(26)).foregroundStyle(Brand.ink).multilineTextAlignment(.center)
            Text(message).font(.body).foregroundStyle(Brand.secondaryInk).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.brandPrimary)
                    .frame(maxWidth: 280)
                    .accessibilityIdentifier(actionIdentifier ?? "emptyState.action")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
