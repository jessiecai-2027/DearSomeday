//
//  PostcardStyle.swift
//  DearSomeday
//
//  Shared postcard canvas style tokens. Composer and display must resolve the
//  same persisted ids the same way, otherwise the stored design is not really
//  the source of truth.
//

import SwiftUI
import UIKit

enum PostcardCanvasMetrics {
    static let aspectRatio = CardTemplate.canvasAspectRatio
    static let maxWidth: CGFloat = 340
    static let photoBarrierWidth: CGFloat = 5
}

struct PostcardPhotoBarriers: View {
    let template: CardTemplate

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    for slot in template.slots {
                        if slot.y > 0.0001 {
                            path.move(to: CGPoint(
                                x: CGFloat(slot.x) * proxy.size.width,
                                y: CGFloat(slot.y) * proxy.size.height
                            ))
                            path.addLine(to: CGPoint(
                                x: CGFloat(slot.x + slot.width) * proxy.size.width,
                                y: CGFloat(slot.y) * proxy.size.height
                            ))
                        }

                        if slot.x > 0.0001 {
                            path.move(to: CGPoint(
                                x: CGFloat(slot.x) * proxy.size.width,
                                y: CGFloat(slot.y) * proxy.size.height
                            ))
                            path.addLine(to: CGPoint(
                                x: CGFloat(slot.x) * proxy.size.width,
                                y: CGFloat(slot.y + slot.height) * proxy.size.height
                            ))
                        }
                    }
                }
                .stroke(
                    .white,
                    style: StrokeStyle(
                        lineWidth: PostcardCanvasMetrics.photoBarrierWidth,
                        lineCap: .butt,
                        lineJoin: .miter
                    )
                )

                Rectangle()
                    .strokeBorder(.white, lineWidth: PostcardCanvasMetrics.photoBarrierWidth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum PostcardBackLayout {
    /// The printed dotted square in `PostcardBack`, normalised to the full
    /// postcard canvas. Text exclusion and stamp rendering share this geometry.
    static let normalizedStampFrame = CGRect(
        x: 0.706,
        y: 0.064,
        width: 0.183,
        height: 0.119
    )

    static func stampFrame(in canvasSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedStampFrame.minX * canvasSize.width,
            y: normalizedStampFrame.minY * canvasSize.height,
            width: normalizedStampFrame.width * canvasSize.width,
            height: normalizedStampFrame.height * canvasSize.height
        )
    }
}

enum PostcardBackFont: String, CaseIterable, Identifiable {
    case caveat
    case dancingScript
    case ebGaramond
    case josefinSans

    static let defaultFont: PostcardBackFont = .caveat
    static let normalPointSize: CGFloat = 17
    static let minimumLockedPointSize: CGFloat = 12
    static let minimumLegacyPointSize: CGFloat = 8

    var id: String { rawValue }

    var name: String {
        switch self {
        case .caveat: return "Caveat"
        case .dancingScript: return "Dancing Script"
        case .ebGaramond: return "EB Garamond"
        case .josefinSans: return "Josefin Sans"
        }
    }

    private var fontName: String {
        switch self {
        case .caveat: return "Caveat-Regular"
        case .dancingScript: return "DancingScript-Regular"
        case .ebGaramond: return "EBGaramond-Regular"
        case .josefinSans: return "JosefinSans-Regular"
        }
    }

    var bodyFont: Font {
        font(pointSize: Self.normalPointSize)
    }

    var uiBodyFont: UIFont {
        let baseFont = uiFont(pointSize: Self.normalPointSize)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
    }

    func font(pointSize: CGFloat) -> Font {
        .custom(fontName, size: pointSize)
    }

    func uiFont(pointSize: CGFloat) -> UIFont {
        UIFont(name: fontName, size: pointSize) ?? .systemFont(ofSize: pointSize)
    }

    var previewFont: Font {
        .custom(fontName, size: 19, relativeTo: .body)
    }

    static func resolved(id: String?) -> PostcardBackFont {
        guard let id, let font = allCases.first(where: { $0.id == id }) else {
            return defaultFont
        }
        return font
    }
}

enum PostcardBackTextColor: String, CaseIterable, Identifiable {
    case espresso
    case taupe
    case sage
    case clay
    case mist
    case black

    static let defaultColor: PostcardBackTextColor = .espresso

    var id: String { rawValue }

    var name: String {
        switch self {
        case .espresso: return "Espresso"
        case .taupe: return "Taupe"
        case .sage: return "Sage"
        case .clay: return "Clay"
        case .mist: return "Mist"
        case .black: return "Black"
        }
    }

    var hex: String {
        switch self {
        case .espresso: return "#2B241E"
        case .taupe: return "#A98B76"
        case .sage: return "#6F754F"
        case .clay: return "#A46150"
        case .mist: return "#536FA3"
        case .black: return "#111111"
        }
    }

    static func resolvedHex(_ value: String?) -> String {
        guard let value, let normalized = Color.normalizedHexColor(value) else {
            return defaultColor.hex
        }
        return normalized
    }
}

extension Color {
    init(hex: String) {
        let normalized = Self.normalizedHexColor(hex) ?? PostcardBackTextColor.defaultColor.hex
        let raw = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    static func normalizedHexColor(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(raw.uppercased())"
    }

    var hexString: String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
