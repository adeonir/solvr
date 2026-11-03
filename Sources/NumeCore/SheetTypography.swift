// The typography of a sheet (ADK-260): font family, size in px, and line
// height as a multiplier of the size, like CSS unitless `line-height`. The
// editor's font sizes and line metrics all derive from this one value.

import Foundation

public struct SheetTypography: Equatable, Sendable {
    public static let defaultFamily = "SF Mono"
    public static let defaultSize = 13
    public static let defaultLineHeight = 2.0
    public static let `default` = SheetTypography(
        family: defaultFamily,
        size: defaultSize,
        lineHeight: defaultLineHeight
    )

    public let family: String
    public let size: Int
    public let lineHeight: Double

    public init(family: String, size: Int, lineHeight: Double) {
        self.family = family
        self.size = size
        self.lineHeight = lineHeight
    }

    /// The size of sheet text and results, in px.
    public var textSize: Double {
        Double(size)
    }

    /// The size of headings, in px.
    public var headingSize: Double {
        Double(size)
    }

    /// The size of line numbers: 11/13 of the font size, 11 px at 13.
    public var lineNumberSize: Double {
        Double(size) * 11 / 13
    }

    /// The height of a sheet line, in px.
    public var lineHeightInPixels: Double {
        Double(size) * lineHeight
    }
}
