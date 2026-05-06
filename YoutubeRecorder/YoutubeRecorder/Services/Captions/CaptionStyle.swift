import Foundation
import AppKit

/// Customizable caption style for video subtitle rendering.
struct CaptionStyle: Codable, Sendable, Equatable {
    var fontSize: CGFloat
    var fontWeight: FontWeight
    var textColor: CaptionColor
    var backgroundColor: CaptionColor
    var backgroundOpacity: CGFloat
    var position: CaptionPosition

    enum FontWeight: String, Codable, CaseIterable, Identifiable, Sendable {
        case regular = "Regular"
        case medium = "Medium"
        case semibold = "Semibold"
        case bold = "Bold"

        var id: String { rawValue }

        var ctFontWeight: CGFloat {
            switch self {
            case .regular:  return NSFont.Weight.regular.rawValue
            case .medium:   return NSFont.Weight.medium.rawValue
            case .semibold: return NSFont.Weight.semibold.rawValue
            case .bold:     return NSFont.Weight.bold.rawValue
            }
        }
    }

    enum CaptionColor: String, Codable, CaseIterable, Identifiable, Sendable {
        case white = "White"
        case yellow = "Yellow"
        case cyan = "Cyan"
        case green = "Green"
        case orange = "Orange"
        case pink = "Pink"
        case black = "Black"

        var id: String { rawValue }

        var nsColor: NSColor {
            switch self {
            case .white:  return .white
            case .yellow: return NSColor(red: 1.0, green: 0.92, blue: 0.23, alpha: 1)
            case .cyan:   return NSColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1)
            case .green:  return NSColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1)
            case .orange: return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
            case .pink:   return NSColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1)
            case .black:  return .black
            }
        }

        var icon: String {
            switch self {
            case .white:  return "circle.fill"
            case .yellow: return "circle.fill"
            case .cyan:   return "circle.fill"
            case .green:  return "circle.fill"
            case .orange: return "circle.fill"
            case .pink:   return "circle.fill"
            case .black:  return "circle.fill"
            }
        }
    }

    enum CaptionPosition: String, Codable, CaseIterable, Identifiable, Sendable {
        case top = "Top"
        case center = "Center"
        case bottom = "Bottom"

        var id: String { rawValue }

        /// Returns normalized Y position (0 = bottom, 1 = top) for the caption
        var normalizedY: CGFloat {
            switch self {
            case .top:    return 0.88
            case .center: return 0.50
            case .bottom: return 0.08
            }
        }
    }

    /// Default style: white bold text at the bottom with dark background
    static let `default` = CaptionStyle(
        fontSize: 32,
        fontWeight: .bold,
        textColor: .white,
        backgroundColor: .black,
        backgroundOpacity: 0.75,
        position: .bottom
    )
}
