// The theme catalog (ADK-328): every color the window draws, as one value.

import Foundation

/// An sRGB color with an alpha.
public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }
}

public struct Theme: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case light
        case dark
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let background: ThemeColor
    public let text: ThemeColor
    public let lineNumber: ThemeColor
    public let lineNumberActive: ThemeColor
    public let result: ThemeColor
    public let error: ThemeColor
    public let caret: ThemeColor
    public let activeLine: ThemeColor
    public let sidebar: ThemeColor
    public let sidebarSelection: ThemeColor
    public let secondaryText: ThemeColor
    public let tertiaryText: ThemeColor

    public static let defaultLight = Theme(
        id: "default-light",
        name: "Default",
        kind: .light,
        background: ThemeColor(hex: 0xFFFFFF),
        text: ThemeColor(hex: 0x1D1D1F),
        lineNumber: ThemeColor(hex: 0xC7C7CC),
        lineNumberActive: ThemeColor(hex: 0x8E8E93),
        result: ThemeColor(hex: 0x0062CC),
        error: ThemeColor(hex: 0xD70015),
        caret: ThemeColor(hex: 0x007AFF),
        activeLine: ThemeColor(hex: 0x000000, alpha: 0.05),
        sidebar: ThemeColor(hex: 0xF2F2F4),
        sidebarSelection: ThemeColor(hex: 0xE1E1E5),
        secondaryText: ThemeColor(hex: 0x636368),
        tertiaryText: ThemeColor(hex: 0x8E8E93)
    )

    public static let defaultDark = Theme(
        id: "default-dark",
        name: "Default",
        kind: .dark,
        background: ThemeColor(hex: 0x1E1E1E),
        text: ThemeColor(hex: 0xF5F5F7),
        lineNumber: ThemeColor(hex: 0x505055),
        lineNumberActive: ThemeColor(hex: 0x8E8E93),
        result: ThemeColor(hex: 0x4DA3FF),
        error: ThemeColor(hex: 0xFF453A),
        caret: ThemeColor(hex: 0x0A84FF),
        activeLine: ThemeColor(hex: 0xFFFFFF, alpha: 0.06),
        sidebar: ThemeColor(hex: 0x232326),
        sidebarSelection: ThemeColor(hex: 0x303033),
        secondaryText: ThemeColor(hex: 0xA1A1A6),
        tertiaryText: ThemeColor(hex: 0x7C7C82)
    )

    public static let catalog = [defaultLight, defaultDark]
}
