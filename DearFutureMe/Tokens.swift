import SwiftUI

// MARK: - Design Tokens
//
// Single source of truth for every design value in the app.
// Never hard-code a colour, size, spacing, or radius in a view — reference a token.
//
// STRUCTURE MIRRORS THE CHROME / CANVAS SPLIT (PRD §4.1):
//   Chrome  — timeline, nav, settings, dialogs. Quiet, spare, adapts to dark mode.
//   Canvas  — the postcard itself. Textured, layered, IDENTICAL in light and dark.
//
// Dark mode darkens the DESK, not the PAPER. The postcard stays bright cream in
// both appearances; only the surrounding chrome goes deep brown. Physically this
// is a scrapbook on a desk at night. It needs zero extra assets, and it makes the
// card a glowing object of attention.

enum Tokens {

    // MARK: Palette

    enum Color {

        // Canvas — FIXED. Never adapts. The paper is the paper.
        static let paperCream  = SwiftUI.Color(hex: 0xF3E4C9)
        static let paperTan    = SwiftUI.Color(hex: 0xBFA28C)
        static let paperTaupe  = SwiftUI.Color(hex: 0xA98B76)
        static let accentSage  = SwiftUI.Color(hex: 0xBABF94)

        /// All text, on every surface. Contrast vs. the palette:
        /// cream 12.19:1 · sage 7.98:1 · tan 6.38:1 · taupe 4.83:1 — all pass WCAG AA.
        /// NEVER use a surface colour for text; they fail against each other
        /// (taupe on cream is only 2.52:1).
        static let inkEspresso = SwiftUI.Color(hex: 0x2B241E)

        // Chrome — ADAPTS. The desk around the card.
        static let chromeBackground = SwiftUI.Color(light: 0xFAF3E7, dark: 0x1A1512)
        static let chromeSurface    = SwiftUI.Color(light: 0xFFFFFF, dark: 0x241D19)
        static let chromeText       = SwiftUI.Color(light: 0x2B241E, dark: 0xF0E6D6)
        static let chromeTextMuted  = SwiftUI.Color(light: 0x6B5D50, dark: 0xA1917F)
        static let chromeDivider    = SwiftUI.Color(light: 0xE0D2BC, dark: 0x3A302A)
        static let chromeAccent     = SwiftUI.Color(light: 0xA98B76, dark: 0xBFA28C)

        /// Destructive actions only.
        static let danger = SwiftUI.Color(light: 0x9B4A3C, dark: 0xC96A58)
    }

    // MARK: Typography
    //
    // Chrome uses Bodoni Moda — Dynamic Type still works through `relativeTo:`.
    // Canvas uses character faces, sized UP: handwriting and display faces have
    // smaller x-heights, so 20pt handwriting reads like 16pt system.
    //
    // Leading on canvas is looser than chrome. Grain texture competes with tight
    // lines, and paper wants air.

    enum Font {

        /// TODO: replace with real families once licensed (PRD §4.6).
        /// Prefer SIL OFL (Google Fonts) to avoid redistribution issues.
        /// `.custom` silently falls back to system if the font isn't installed,
        /// so these are safe placeholders — the app builds and runs today.
        enum Family {
            static let chrome      = "BodoniModa9pt-Regular"
            static let display     = "Georgia"          // card titles
            static let typewriter  = "American Typewriter"
            static let handwriting = "Bradley Hand"
        }

        // Chrome
        static let screenTitle  = SwiftUI.Font.custom(Family.chrome, size: 28, relativeTo: .title).weight(.semibold)
        static let sectionLabel = SwiftUI.Font.custom(Family.chrome, size: 13, relativeTo: .subheadline).weight(.medium)
        static let headline     = SwiftUI.Font.custom(Family.chrome, size: 17, relativeTo: .headline).weight(.semibold)
        static let subheadline  = SwiftUI.Font.custom(Family.chrome, size: 15, relativeTo: .subheadline)
        static let body         = SwiftUI.Font.custom(Family.chrome, size: 17, relativeTo: .body)
        static let footnote     = SwiftUI.Font.custom(Family.chrome, size: 13, relativeTo: .footnote)
        static let caption      = SwiftUI.Font.custom(Family.chrome, size: 13, relativeTo: .caption)
        static let caption2     = SwiftUI.Font.custom(Family.chrome, size: 11, relativeTo: .caption2)
        static let button       = SwiftUI.Font.custom(Family.chrome, size: 16, relativeTo: .body).weight(.medium)

        // Canvas — `relativeTo:` keeps Dynamic Type working with custom faces
        static let cardTitle   = SwiftUI.Font.custom(Family.display,     size: 24, relativeTo: .title2)
        static let cardBody    = SwiftUI.Font.custom(Family.typewriter,  size: 16, relativeTo: .body)
        static let handwriting = SwiftUI.Font.custom(Family.handwriting, size: 20, relativeTo: .body)
        static let stamp       = SwiftUI.Font.custom(Family.typewriter,  size: 11, relativeTo: .caption2)

        /// Tracking, applied via `.tracking()`.
        enum Tracking {
            static let sectionLabel: CGFloat = 0.5
            static let stamp: CGFloat = 1.0
        }

        /// Line spacing, applied via `.lineSpacing()`.
        /// Note: SwiftUI's `lineSpacing` is the gap BETWEEN lines, not total leading.
        enum LineSpacing {
            static let body: CGFloat = 7          // 17pt + 7 ≈ 24 leading
            static let cardBody: CGFloat = 8      // 16pt + 8 ≈ 24 — looser, for texture
            static let handwriting: CGFloat = 8
        }
    }

    // MARK: Spacing — base 4

    enum Space {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48

        /// Deliberately 24, not the iOS-standard 16.
        /// "Minimal chrome" is achieved mostly through whitespace — this single
        /// value does more for that feeling than any other change.
        static let screenMargin: CGFloat = 24
    }

    // MARK: Corner radii — chrome only
    //
    // Kept tighter than current iOS fashion ON PURPOSE. Paper is cut or torn,
    // not soft and blobby. Heavily rounded chrome fights the material story.
    // The CANVAS uses alpha-masked torn edges, never cornerRadius.

    enum Radius {
        static let subtle: CGFloat = 8      // buttons, controls, small cards
        static let panel:  CGFloat = 16     // sheets, dialogs
        static let pill:   CGFloat = 999
    }

    // MARK: Shadows — chrome only
    //
    // Derived from inkEspresso, NEVER black. Neutral grey shadows against a warm
    // cream palette read as dirty. This is the detail most often gotten wrong.
    //
    // Canvas shadows are PRE-BAKED into the PNG assets (PRD §4.4).
    // Never apply runtime `.shadow()` to canvas elements — deriving a shadow from
    // a complex alpha mask every frame is what drops timeline framerate.

    enum Shadow {
        struct Style {
            let color: SwiftUI.Color
            let radius: CGFloat
            let y: CGFloat
        }

        private static func warm(_ alpha: Double) -> SwiftUI.Color {
            SwiftUI.Color(hex: 0x2B241E).opacity(alpha)
        }

        static let rest    = Style(color: warm(0.06), radius: 2,  y: 1)
        static let raised  = Style(color: warm(0.10), radius: 8,  y: 2)
        static let overlay = Style(color: warm(0.16), radius: 24, y: 8)
    }

    // MARK: Canvas behaviour

    enum Canvas {
        /// Random tilt (±degrees) applied when an element is first placed.
        /// THE HIGHEST-IMPACT VALUE IN THIS FILE. It's what makes a card look
        /// arranged by hand rather than laid out by a computer. Don't set to 0.
        static let placementJitter: Double = 2.5

        /// Snap to 0/90/180/270 within this many degrees (PRD §5.2).
        static let snapThreshold: Double = 4

        /// Max decoration elements per card — performance cap (PRD §4.4).
        static let maxElements = 20

        /// Film grain. Applied ONCE at the top level, never per element.
        static let grainOpacity: Double = 0.08
        static let grainBlendMode: BlendMode = .overlay

        /// Photo aspect ratio (PRD §5.1).
        static let photoAspect: CGFloat = 4.0 / 5.0
    }

    // MARK: Motion (PRD §4.5)
    //
    // Interruptible springs only. Never `.linear` or fixed-duration `.easeInOut` —
    // they feel mechanical and can't be grabbed mid-flight.

    enum Motion {
        static let standard = Animation.snappy(duration: 0.35, extraBounce: 0.05)
        static let playful  = Animation.bouncy(duration: 0.45, extraBounce: 0.15)
        static let subtle   = Animation.smooth(duration: 0.25)
    }
}

// MARK: - Conveniences

extension View {
    /// Chrome shadow. Do NOT use on canvas elements — see Tokens.Shadow.
    func chromeShadow(_ style: Tokens.Shadow.Style) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }

    func screenMargins() -> some View {
        padding(.horizontal, Tokens.Space.screenMargin)
    }

    /// Deterministic per-element tilt. Seed with the element's UUID hash so the
    /// rotation is stable across launches instead of re-randomising every render.
    func placementJitter(seed: Int) -> some View {
        var rng = SeededRandom(seed: seed)
        let range = Tokens.Canvas.placementJitter
        let angle = Double.random(in: -range...range, using: &rng)
        return rotationEffect(.degrees(angle))
    }
}

/// Reproducible RNG so placement tilt is stable per element.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(truncatingIfNeeded: seed) &* 6364136223846793005 &+ 1 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Adaptive chrome colour. Canvas colours must NOT use this.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
