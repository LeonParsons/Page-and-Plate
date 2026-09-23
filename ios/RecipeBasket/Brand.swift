import SwiftUI
import UIKit

/// The one place the app's identity lives: name, tagline, palette, display face and the mark.
/// Before this existed the colours and the name were copy-pasted into `SplashView` and `WelcomeView`.
enum Brand {
    // `nonisolated` so copy can be read off the main actor too (the Reminders store builds its own messages).
    nonisolated static let name = "Page & Plate"
    nonisolated static let tagline = "Cook from the books you own."

    // MARK: Colour

    /// The accent, and the app's tint (mirrored in `Assets.xcassets/AccentColor.colorset`).
    /// Chosen for contrast, not just hue: 5.6:1 on paper and 6.0:1 under white, so it can set text
    /// *and* carry white on top. The old #ED5C33 managed 3.2:1 and could only ever tint a shape.
    static let tomato = Color(light: 0xB23A1B, dark: 0xF2775A)

    /// Secondary accent, for staple tags and other quiet marks.
    static let ochre = Color(light: 0x8A5D18, dark: 0xD9A441)

    /// Full-bleed brand surfaces: the splash and the welcome header.
    static let paper = Color(light: 0xFAF7F0, dark: 0x1A1713)

    /// Behind a `List` or `Form`, in place of iOS's `systemGroupedBackground` — which is #F2F2F7, whose
    /// *blue* channel is the highest, so every screen read cool and generic next to the warm brand surfaces.
    /// Applied through `.paperBackground()`.
    ///
    /// Light is `paper` exactly. Dark is darker than `paper`, because rows keep the system's
    /// `secondarySystemGroupedBackground` (#1C1C1E) — on #1A1713 the cards are nearly invisible, and stock iOS
    /// separates them by sitting that fill on near-black. The split mirrors Apple's own
    /// `systemBackground` / `systemGroupedBackground` distinction.
    static let groupedPaper = Color(light: 0xFAF7F0, dark: 0x0E0C0A)

    /// Ink on `paper`.
    static let ink = Color(light: 0x23201B, dark: 0xF2EDE4)

    /// Secondary ink on `paper`. 6.9:1 light, 6.8:1 dark — passes as body text, not just as a caption.
    static let inkSecondary = Color(light: 0x5C554A, dark: 0xA79E90)

    /// A hairline on `paper`.
    static let rule = Color(light: 0xE6DED0, dark: 0x332E27)

    // MARK: Type

    /// The display face. Fraunces when the file is bundled, otherwise SF Serif, which is on-device and
    /// close enough in feel that the app is never waiting on an asset to look right.
    private static let displayFamily = "Fraunces"

    static var hasDisplayFont: Bool {
        UIFont(name: displayFamily, size: 12) != nil
    }

    /// Scales with Dynamic Type via `relativeTo`.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        hasDisplayFont
            ? .custom(displayFamily, size: size, relativeTo: style)
            : .system(size: size, weight: .bold, design: .serif)
    }
}

/// The app mark: a plate seen from above, holding an open book. Drawn rather than shipped as an asset so it
/// takes the current foreground colour and stays sharp at every size.
struct BrandMark: View {
    var size: CGFloat
    var lineWidth: CGFloat = 4.5

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 100
            let stroke = lineWidth * s

            func scaled(_ path: Path) -> Path {
                path.applying(CGAffineTransform(scaleX: s, y: s))
            }

            let rim = Path(ellipseIn: CGRect(x: 8, y: 8, width: 84, height: 84))
            context.stroke(scaled(rim), with: .style(.foreground), lineWidth: stroke * 0.9)

            // The well is the faintest line; it is the first thing to go at Spotlight size.
            let well = Path(ellipseIn: CGRect(x: 19, y: 19, width: 62, height: 62))
            context.drawLayer { layer in
                layer.opacity = 0.45
                layer.stroke(scaled(well), with: .style(.foreground), lineWidth: stroke * 0.5)
            }

            var pages = Path()
            for direction in [CGFloat(-1), 1] {
                let x = { (offset: CGFloat) in 50 + offset * direction }
                pages.move(to: CGPoint(x: 50, y: 41))
                pages.addCurve(
                    to: CGPoint(x: x(25), y: 36.5),
                    control1: CGPoint(x: x(7), y: 36),
                    control2: CGPoint(x: x(17), y: 35)
                )
                pages.addLine(to: CGPoint(x: x(25), y: 61))
                pages.addCurve(
                    to: CGPoint(x: 50, y: 65),
                    control1: CGPoint(x: x(17), y: 59.5),
                    control2: CGPoint(x: x(7), y: 60.5)
                )
            }
            context.stroke(
                scaled(pages),
                with: .style(.foreground),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
            )

            var gutter = Path()
            gutter.move(to: CGPoint(x: 50, y: 41))
            gutter.addLine(to: CGPoint(x: 50, y: 65))
            context.stroke(
                scaled(gutter),
                with: .style(.foreground),
                style: StrokeStyle(lineWidth: stroke * 0.65, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Puts a `List` or `Form` on the brand's paper ground with warm card fills, in place of iOS's cool
    /// `systemGroupedBackground`. Every grouped screen in the app uses this, so they all match; leaving one
    /// out is what makes the difference visible.
    /// Rows keep their own system fill, which adapts on its own; only the ground behind them changes.
    /// (`.listRowBackground` here would be silently ignored — on a `List` it does not reach the rows.)
    func paperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Brand.groupedPaper)
    }
}

extension Color {
    /// A light/dark pair from two hex values, so a brand colour is one line rather than a colour set.
    ///
    /// `nonisolated` is load-bearing, not tidiness. This target defaults to `MainActor` isolation, so without
    /// it the dynamic-provider closure below is main-actor isolated — and UIKit resolves it on whatever thread
    /// asks for the colour, including SwiftUI's `AsyncRenderer`. Swift 6 traps on the isolation check and the
    /// app dies with `EXC_BREAKPOINT` inside `dispatch_assert_queue`, nowhere near this line.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

#Preview {
    VStack(spacing: 24) {
        BrandMark(size: 120)
            .foregroundStyle(Brand.tomato)
        Text(Brand.name)
            .font(Brand.display(40))
            .foregroundStyle(Brand.ink)
        Text(Brand.tagline)
            .foregroundStyle(Brand.inkSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.paper)
}
