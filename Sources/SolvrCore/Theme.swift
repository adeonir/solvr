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

    /// Every theme: the Default theme of each kind first, then the others.
    public static let catalog = [defaultLight, defaultDark] + otherThemes

    /// The themes the menu offers for a kind: Default first, then the others by name.
    public static func list(for kind: Kind) -> [Theme] {
        let others = otherThemes
            .filter { $0.kind == kind }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return [kind == .light ? defaultLight : defaultDark] + others
    }

    /// The theme the window draws: the mode decides the kind (Auto follows the
    /// system appearance) and the identifier kept for that kind picks the theme.
    /// A missing, unknown, or other-kind identifier gives the Default theme.
    public static func active(mode: AppearanceMode, systemIsDark: Bool, lightID: String?, darkID: String?) -> Theme {
        let kind: Kind = switch mode {
        case .light: .light
        case .dark: .dark
        case .auto: systemIsDark ? .dark : .light
        }
        let keptID = kind == .light ? lightID : darkID
        return list(for: kind).first { $0.id == keptID } ?? (kind == .light ? defaultLight : defaultDark)
    }

    private static let otherThemes: [Theme] = [
        Theme("alucard", "Alucard", .light,
              background: 0xFFFBEB, text: 0x1F1F1F, lineNumber: 0xBCBAB3, lineNumberActive: 0x6C664B,
              result: 0x036A96, error: 0xCB3A2A, caret: 0x644AC9, activeLine: ThemeColor(hex: 0xE2DECA),
              sidebar: 0xEFEDDC, sidebarSelection: 0xCFCFDE, secondaryText: 0x6C664B, tertiaryText: 0x9A957C),
        Theme("catppuccin-latte", "Catppuccin Latte", .light,
              background: 0xEFF1F5, text: 0x4C4F69, lineNumber: 0x9CA0B0, lineNumberActive: 0x6C6F85,
              result: 0x1E66F5, error: 0xD20F39, caret: 0x1E66F5, activeLine: ThemeColor(hex: 0xCCD0DA, alpha: 0.5),
              sidebar: 0xE6E9EF, sidebarSelection: 0xCCD0DA, secondaryText: 0x6C6F85, tertiaryText: 0x9CA0B0),
        Theme("monokai-light", "Monokai Light", .light,
              background: 0xFAFAF5, text: 0x272822, lineNumber: 0xB7B5A6, lineNumberActive: 0x75715E,
              result: 0x00829F, error: 0xD6004F, caret: 0x00829F, activeLine: ThemeColor(hex: 0xECEBDD),
              sidebar: 0xF0EFE6, sidebarSelection: 0xE2E0D0, secondaryText: 0x75715E, tertiaryText: 0xA09D8A),
        Theme("one-light", "One Light", .light,
              background: 0xFAFAFA, text: 0x383A42, lineNumber: 0x9D9D9F, lineNumberActive: 0x383A42,
              result: 0x4078F2, error: 0xE45649, caret: 0x4078F2, activeLine: ThemeColor(hex: 0x383A42, alpha: 0.06),
              sidebar: 0xF0F0F1, sidebarSelection: 0xE5E5E6, secondaryText: 0x696C77, tertiaryText: 0xA0A1A7),
        Theme("rose-pine-dawn", "Rosé Pine Dawn", .light,
              background: 0xFAF4ED, text: 0x464261, lineNumber: 0x9893A5, lineNumberActive: 0x797593,
              result: 0x56949F, error: 0xB4637A, caret: 0x56949F, activeLine: ThemeColor(hex: 0xF2E9E1),
              sidebar: 0xFFFAF3, sidebarSelection: 0xF2E9E1, secondaryText: 0x797593, tertiaryText: 0x9893A5),
        Theme("tokyo-night-day", "Tokyo Night Day", .light,
              background: 0xE1E2E7, text: 0x3760BF, lineNumber: 0xA8AECB, lineNumberActive: 0x6172B0,
              result: 0x2E7DE9, error: 0xF52A65, caret: 0x2E7DE9, activeLine: ThemeColor(hex: 0xC4C8DA, alpha: 0.5),
              sidebar: 0xD0D5E3, sidebarSelection: 0xC4C8DA, secondaryText: 0x6172B0, tertiaryText: 0x848CB5),
        Theme("catppuccin-frappe", "Catppuccin Frappé", .dark,
              background: 0x303446, text: 0xC6D0F5, lineNumber: 0x737994, lineNumberActive: 0xA5ADCE,
              result: 0x8CAAEE, error: 0xE78284, caret: 0x8CAAEE, activeLine: ThemeColor(hex: 0x414559, alpha: 0.5),
              sidebar: 0x292C3C, sidebarSelection: 0x414559, secondaryText: 0xA5ADCE, tertiaryText: 0x737994),
        Theme("catppuccin-macchiato", "Catppuccin Macchiato", .dark,
              background: 0x24273A, text: 0xCAD3F5, lineNumber: 0x6E738D, lineNumberActive: 0xA5ADCB,
              result: 0x8AADF4, error: 0xED8796, caret: 0x8AADF4, activeLine: ThemeColor(hex: 0x363A4F, alpha: 0.5),
              sidebar: 0x1E2030, sidebarSelection: 0x363A4F, secondaryText: 0xA5ADCB, tertiaryText: 0x6E738D),
        Theme("catppuccin-mocha", "Catppuccin Mocha", .dark,
              background: 0x1E1E2E, text: 0xCDD6F4, lineNumber: 0x6C7086, lineNumberActive: 0xA6ADC8,
              result: 0x89B4FA, error: 0xF38BA8, caret: 0x89B4FA, activeLine: ThemeColor(hex: 0x313244, alpha: 0.5),
              sidebar: 0x181825, sidebarSelection: 0x313244, secondaryText: 0xA6ADC8, tertiaryText: 0x6C7086),
        Theme("dracula", "Dracula", .dark,
              background: 0x282A36, text: 0xF8F8F2, lineNumber: 0x6272A4, lineNumberActive: 0xBD93F9,
              result: 0x8BE9FD, error: 0xFF5555, caret: 0xFF79C6, activeLine: ThemeColor(hex: 0x44475A, alpha: 0.5),
              sidebar: 0x21222C, sidebarSelection: 0x44475A, secondaryText: 0xBFBFB8, tertiaryText: 0x6272A4),
        Theme("monokai-dark", "Monokai Dark", .dark,
              background: 0x272822, text: 0xF8F8F2, lineNumber: 0x75715E, lineNumberActive: 0xA59F85,
              result: 0x66D9EF, error: 0xF92672, caret: 0xF8F8F0, activeLine: ThemeColor(hex: 0x3E3D32),
              sidebar: 0x1E1F1C, sidebarSelection: 0x49483E, secondaryText: 0xA59F85, tertiaryText: 0x75715E),
        Theme("one-dark", "One Dark", .dark,
              background: 0x282C34, text: 0xABB2BF, lineNumber: 0x4B5263, lineNumberActive: 0xABB2BF,
              result: 0x61AFEF, error: 0xE06C75, caret: 0x61AFEF, activeLine: ThemeColor(hex: 0x2C313C),
              sidebar: 0x21252B, sidebarSelection: 0x3E4451, secondaryText: 0x9DA5B4, tertiaryText: 0x5C6370),
        Theme("rose-pine", "Rosé Pine", .dark,
              background: 0x191724, text: 0xE0DEF4, lineNumber: 0x6E6A86, lineNumberActive: 0x908CAA,
              result: 0x9CCFD8, error: 0xEB6F92, caret: 0x9CCFD8, activeLine: ThemeColor(hex: 0x26233A, alpha: 0.7),
              sidebar: 0x1F1D2E, sidebarSelection: 0x26233A, secondaryText: 0x908CAA, tertiaryText: 0x6E6A86),
        Theme("rose-pine-moon", "Rosé Pine Moon", .dark,
              background: 0x232136, text: 0xE0DEF4, lineNumber: 0x6E6A86, lineNumberActive: 0x908CAA,
              result: 0x9CCFD8, error: 0xEB6F92, caret: 0x9CCFD8, activeLine: ThemeColor(hex: 0x393552, alpha: 0.7),
              sidebar: 0x2A273F, sidebarSelection: 0x393552, secondaryText: 0x908CAA, tertiaryText: 0x6E6A86),
        Theme("tokyo-night", "Tokyo Night", .dark,
              background: 0x1A1B26, text: 0xC0CAF5, lineNumber: 0x3B4261, lineNumberActive: 0xA9B1D6,
              result: 0x7AA2F7, error: 0xF7768E, caret: 0x7AA2F7, activeLine: ThemeColor(hex: 0x292E42, alpha: 0.7),
              sidebar: 0x16161E, sidebarSelection: 0x292E42, secondaryText: 0xA9B1D6, tertiaryText: 0x565F89),
        Theme("tokyo-night-moon", "Tokyo Night Moon", .dark,
              background: 0x222436, text: 0xC8D3F5, lineNumber: 0x3B4261, lineNumberActive: 0x828BB8,
              result: 0x82AAFF, error: 0xFF757F, caret: 0x82AAFF, activeLine: ThemeColor(hex: 0x2F334D, alpha: 0.7),
              sidebar: 0x1E2030, sidebarSelection: 0x2F334D, secondaryText: 0x828BB8, tertiaryText: 0x636DA6),
        Theme("tokyo-night-storm", "Tokyo Night Storm", .dark,
              background: 0x24283B, text: 0xC0CAF5, lineNumber: 0x3B4261, lineNumberActive: 0xA9B1D6,
              result: 0x7AA2F7, error: 0xF7768E, caret: 0x7AA2F7, activeLine: ThemeColor(hex: 0x292E42, alpha: 0.7),
              sidebar: 0x1F2335, sidebarSelection: 0x292E42, secondaryText: 0xA9B1D6, tertiaryText: 0x565F89)
    ]
}

extension Theme {
    // Each theme maps its palette roles the same way: the base is the sheet,
    // the blue family colors results and the caret, red colors errors, the
    // darker surface is the sheet list, and the muted tones are line numbers
    // and tertiary text.
    init(
        _ id: String, _ name: String, _ kind: Kind,
        background: UInt32, text: UInt32, lineNumber: UInt32, lineNumberActive: UInt32,
        result: UInt32, error: UInt32, caret: UInt32, activeLine: ThemeColor,
        sidebar: UInt32, sidebarSelection: UInt32, secondaryText: UInt32, tertiaryText: UInt32
    ) {
        self.init(
            id: id, name: name, kind: kind,
            background: ThemeColor(hex: background), text: ThemeColor(hex: text),
            lineNumber: ThemeColor(hex: lineNumber), lineNumberActive: ThemeColor(hex: lineNumberActive),
            result: ThemeColor(hex: result), error: ThemeColor(hex: error), caret: ThemeColor(hex: caret),
            activeLine: activeLine, sidebar: ThemeColor(hex: sidebar),
            sidebarSelection: ThemeColor(hex: sidebarSelection),
            secondaryText: ThemeColor(hex: secondaryText), tertiaryText: ThemeColor(hex: tertiaryText)
        )
    }
}

/// The window mode: Light, Dark, or Auto, which follows macOS.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case light = "Light"
    case dark = "Dark"
    case auto = "Auto"

    /// The mode for a stored value; an unknown value is Auto.
    public init(stored: String) {
        self = AppearanceMode(rawValue: stored) ?? .auto
    }
}
