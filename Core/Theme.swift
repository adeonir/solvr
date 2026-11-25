// Every color the window draws, as one value.

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
    /// The separators between rows and the edges of fields.
    public let border: ThemeColor
    /// The background of a text field.
    public let inputBackground: ThemeColor
    public let syntax: SyntaxColors

    /// The theme color for a kind of part of a sheet line. A muted part
    /// takes the secondary text color.
    public func color(for kind: SyntaxKind) -> ThemeColor {
        switch kind {
        case .heading: syntax.heading
        case .comment: syntax.comment
        case .value: syntax.value
        case .calendarDate: syntax.calendarDate
        case .timeOfDay: syntax.timeOfDay
        case .unit: syntax.unit
        case .name: syntax.name
        case .muted: secondaryText
        }
    }

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
        tertiaryText: ThemeColor(hex: 0x8E8E93),
        border: ThemeColor(hex: 0x000000, alpha: 0.1),
        inputBackground: ThemeColor(hex: 0xFFFFFF),
        syntax: SyntaxColors(
            heading: 0x1D1D1F, comment: 0x8E8E93, value: 0xB25000, calendarDate: 0x248A3D,
            timeOfDay: 0x8A6D3B, unit: 0x0E7C86, name: 0x5856D6
        )
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
        tertiaryText: ThemeColor(hex: 0x7C7C82),
        border: ThemeColor(hex: 0xFFFFFF, alpha: 0.1),
        inputBackground: ThemeColor(hex: 0x1E1E1E),
        syntax: SyntaxColors(
            heading: 0xF5F5F7, comment: 0x7C7C82, value: 0xFF9F0A, calendarDate: 0x32D74B,
            timeOfDay: 0xD6B07A, unit: 0x40C8E0, name: 0x7D7AFF
        )
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
              background: 0xFFFBEB, text: 0x1F1F1F, lineNumber: 0x6C664B, lineNumberActive: 0x644AC9,
              result: 0x036A96, error: 0xCB3A2A, caret: 0x644AC9, activeLine: ThemeColor(hex: 0xE2DECA),
              sidebar: 0xCECCC0, sidebarSelection: 0xCFCFDE, secondaryText: 0x6C664B, tertiaryText: 0x6C664B,
              border: ThemeColor(hex: 0xBCBAB3), inputBackground: 0xFFFBEB,
              syntax: SyntaxColors(heading: 0x644AC9, comment: 0x6C664B, value: 0x644AC9, calendarDate: 0x846E15,
                                   timeOfDay: 0xA3144D, unit: 0x036A96, name: 0x14710A)),
        Theme("catppuccin-latte", "Catppuccin Latte", .light,
              background: 0xEFF1F5, text: 0x4C4F69, lineNumber: 0x8C8FA1, lineNumberActive: 0x8839EF,
              result: 0x1E66F5, error: 0xD20F39, caret: 0xDC8A78, activeLine: ThemeColor(hex: 0x4C4F69, alpha: 0.07),
              sidebar: 0xE6E9EF, sidebarSelection: 0xCCD0DA, secondaryText: 0x6C6F85, tertiaryText: 0x9CA0B0,
              border: ThemeColor(hex: 0xACB0BE), inputBackground: 0xCCD0DA,
              syntax: SyntaxColors(heading: 0xD20F39, comment: 0x7C7F93, value: 0xFE640B, calendarDate: 0x40A02B,
                                   timeOfDay: 0x8839EF, unit: 0xDF8E1D, name: 0x1E66F5)),
        Theme("monokai-light", "Monokai Light", .light,
              background: 0xFAFAF5, text: 0x272822, lineNumber: 0xB7B5A6, lineNumberActive: 0x75715E,
              result: 0x66D9EF, error: 0xF92672, caret: 0x66D9EF, activeLine: ThemeColor(hex: 0xECEBDD),
              sidebar: 0xF0EFE6, sidebarSelection: 0xE2E0D0, secondaryText: 0x75715E, tertiaryText: 0xA09D8A,
              border: ThemeColor(hex: 0xE2E0D0), inputBackground: 0xFAFAF5,
              syntax: SyntaxColors(heading: 0xA6E22E, comment: 0x75715E, value: 0xAE81FF, calendarDate: 0xE6DB74,
                                   timeOfDay: 0xFD971F, unit: 0xA6E22E, name: 0xA6E22E)),
        Theme("one-light", "One Light", .light,
              background: 0xFAFAFA, text: 0x383A42, lineNumber: 0x9D9D9F, lineNumberActive: 0x383A42,
              result: 0x4078F2, error: 0xE45649, caret: 0x526FFF, activeLine: ThemeColor(hex: 0x383A42, alpha: 0.05),
              sidebar: 0xEAEAEB, sidebarSelection: 0xE5E5E6, secondaryText: 0x696C77, tertiaryText: 0xA0A1A7,
              border: ThemeColor(hex: 0xDBDBDC), inputBackground: 0xFFFFFF,
              syntax: SyntaxColors(heading: 0xE45649, comment: 0xA0A1A7, value: 0xB76B01, calendarDate: 0x50A14F,
                                   timeOfDay: 0xA626A4, unit: 0x0184BC, name: 0x4078F2)),
        Theme("rose-pine-dawn", "Rosé Pine Dawn", .light,
              background: 0xFAF4ED, text: 0x575279, lineNumber: 0x9893A5, lineNumberActive: 0x797593,
              result: 0x56949F, error: 0xB4637A, caret: 0x56949F, activeLine: ThemeColor(hex: 0xF4EDE8),
              sidebar: 0xFFFAF3, sidebarSelection: 0xF2E9E1, secondaryText: 0x797593, tertiaryText: 0x9893A5,
              border: ThemeColor(hex: 0xDFDAD9), inputBackground: 0xF9F2EA,
              syntax: SyntaxColors(heading: 0x907AA9, comment: 0x9893A5, value: 0xD7827E, calendarDate: 0xEA9D34,
                                   timeOfDay: 0x286983, unit: 0x56949F, name: 0x907AA9)),
        Theme("tokyo-night-day", "Tokyo Night Day", .light,
              background: 0xE1E2E7, text: 0x3760BF, lineNumber: 0xA8AECB, lineNumberActive: 0xB15C00,
              result: 0x2E7DE9, error: 0xC64343, caret: 0x3760BF, activeLine: ThemeColor(hex: 0xC4C8DA),
              sidebar: 0xD0D5E3, sidebarSelection: 0xC4C8DA, secondaryText: 0x6172B0, tertiaryText: 0x848CB5,
              border: ThemeColor(hex: 0xB4B5B9), inputBackground: 0xC1C9DF,
              syntax: SyntaxColors(heading: 0x2E7DE9, comment: 0x848CB5, value: 0xB15C00, calendarDate: 0x587539,
                                   timeOfDay: 0x7847BD, unit: 0x188092, name: 0x2E7DE9)),
        Theme("catppuccin-frappe", "Catppuccin Frappé", .dark,
              background: 0x303446, text: 0xC6D0F5, lineNumber: 0x838BA7, lineNumberActive: 0xCA9EE6,
              result: 0x8CAAEE, error: 0xE78284, caret: 0xF2D5CF, activeLine: ThemeColor(hex: 0xC6D0F5, alpha: 0.07),
              sidebar: 0x292C3C, sidebarSelection: 0x414559, secondaryText: 0xA5ADCE, tertiaryText: 0x737994,
              border: ThemeColor(hex: 0x626880), inputBackground: 0x414559,
              syntax: SyntaxColors(heading: 0xE78284, comment: 0x949CBB, value: 0xEF9F76, calendarDate: 0xA6D189,
                                   timeOfDay: 0xCA9EE6, unit: 0xE5C890, name: 0x8CAAEE)),
        Theme("catppuccin-macchiato", "Catppuccin Macchiato", .dark,
              background: 0x24273A, text: 0xCAD3F5, lineNumber: 0x8087A2, lineNumberActive: 0xC6A0F6,
              result: 0x8AADF4, error: 0xED8796, caret: 0xF4DBD6, activeLine: ThemeColor(hex: 0xCAD3F5, alpha: 0.07),
              sidebar: 0x1E2030, sidebarSelection: 0x363A4F, secondaryText: 0xA5ADCB, tertiaryText: 0x6E738D,
              border: ThemeColor(hex: 0x5B6078), inputBackground: 0x363A4F,
              syntax: SyntaxColors(heading: 0xED8796, comment: 0x939AB7, value: 0xF5A97F, calendarDate: 0xA6DA95,
                                   timeOfDay: 0xC6A0F6, unit: 0xEED49F, name: 0x8AADF4)),
        Theme("catppuccin-mocha", "Catppuccin Mocha", .dark,
              background: 0x1E1E2E, text: 0xCDD6F4, lineNumber: 0x7F849C, lineNumberActive: 0xCBA6F7,
              result: 0x89B4FA, error: 0xF38BA8, caret: 0xF5E0DC, activeLine: ThemeColor(hex: 0xCDD6F4, alpha: 0.07),
              sidebar: 0x181825, sidebarSelection: 0x313244, secondaryText: 0xA6ADC8, tertiaryText: 0x6C7086,
              border: ThemeColor(hex: 0x585B70), inputBackground: 0x313244,
              syntax: SyntaxColors(heading: 0xF38BA8, comment: 0x9399B2, value: 0xFAB387, calendarDate: 0xA6E3A1,
                                   timeOfDay: 0xCBA6F7, unit: 0xF9E2AF, name: 0x89B4FA)),
        Theme("dracula", "Dracula", .dark,
              background: 0x282A36, text: 0xF8F8F2, lineNumber: 0x6272A4, lineNumberActive: 0xBD93F9,
              result: 0x8BE9FD, error: 0xFF5555, caret: 0xFF79C6, activeLine: ThemeColor(hex: 0x44475A, alpha: 117.0 / 255),
              sidebar: 0x21222C, sidebarSelection: 0x44475A, secondaryText: 0x6272A4, tertiaryText: 0x6272A4,
              border: ThemeColor(hex: 0x191A21), inputBackground: 0x282A36,
              syntax: SyntaxColors(heading: 0xBD93F9, comment: 0x6272A4, value: 0xBD93F9, calendarDate: 0xF1FA8C,
                                   timeOfDay: 0xFF79C6, unit: 0x8BE9FD, name: 0x50FA7B)),
        Theme("monokai-dark", "Monokai Dark", .dark,
              background: 0x272822, text: 0xF8F8F2, lineNumber: 0x90908A, lineNumberActive: 0xC2C2BF,
              result: 0x66D9EF, error: 0xF92672, caret: 0xF8F8F0, activeLine: ThemeColor(hex: 0x3E3D32),
              sidebar: 0x1E1F1C, sidebarSelection: 0x49483E, secondaryText: 0x90908A, tertiaryText: 0x75715E,
              border: ThemeColor(hex: 0x414339), inputBackground: 0x414339,
              syntax: SyntaxColors(heading: 0xA6E22E, comment: 0x75715E, value: 0xAE81FF, calendarDate: 0xE6DB74,
                                   timeOfDay: 0xFD971F, unit: 0xA6E22E, name: 0xA6E22E)),
        Theme("one-dark", "One Dark", .dark,
              background: 0x282C34, text: 0xABB2BF, lineNumber: 0x636D83, lineNumberActive: 0xABB2BF,
              result: 0x61AFEF, error: 0xE06C75, caret: 0x528BFF, activeLine: ThemeColor(hex: 0x99BBFF, alpha: 0.04),
              sidebar: 0x21252B, sidebarSelection: 0x3E4451, secondaryText: 0x828997, tertiaryText: 0x5C6370,
              border: ThemeColor(hex: 0x181A1F), inputBackground: 0x1B1D23,
              syntax: SyntaxColors(heading: 0xE06C75, comment: 0x5C6370, value: 0xD19A66, calendarDate: 0x98C379,
                                   timeOfDay: 0xC678DD, unit: 0x56B6C2, name: 0x61AFEF)),
        Theme("rose-pine", "Rosé Pine", .dark,
              background: 0x191724, text: 0xE0DEF4, lineNumber: 0x6E6A86, lineNumberActive: 0x908CAA,
              result: 0x9CCFD8, error: 0xEB6F92, caret: 0x9CCFD8, activeLine: ThemeColor(hex: 0x21202E),
              sidebar: 0x1F1D2E, sidebarSelection: 0x26233A, secondaryText: 0x908CAA, tertiaryText: 0x6E6A86,
              border: ThemeColor(hex: 0x403D52), inputBackground: 0x232034,
              syntax: SyntaxColors(heading: 0xC4A7E7, comment: 0x6E6A86, value: 0xEBBCBA, calendarDate: 0xF6C177,
                                   timeOfDay: 0x31748F, unit: 0x9CCFD8, name: 0xC4A7E7)),
        Theme("rose-pine-moon", "Rosé Pine Moon", .dark,
              background: 0x232136, text: 0xE0DEF4, lineNumber: 0x6E6A86, lineNumberActive: 0x908CAA,
              result: 0x9CCFD8, error: 0xEB6F92, caret: 0x9CCFD8, activeLine: ThemeColor(hex: 0x2A283E),
              sidebar: 0x2A273F, sidebarSelection: 0x393552, secondaryText: 0x908CAA, tertiaryText: 0x6E6A86,
              border: ThemeColor(hex: 0x44415A), inputBackground: 0x322E49,
              syntax: SyntaxColors(heading: 0xC4A7E7, comment: 0x6E6A86, value: 0xEA9A97, calendarDate: 0xF6C177,
                                   timeOfDay: 0x3E8FB0, unit: 0x9CCFD8, name: 0xC4A7E7)),
        Theme("tokyo-night", "Tokyo Night", .dark,
              background: 0x1A1B26, text: 0xC0CAF5, lineNumber: 0x3B4261, lineNumberActive: 0xFF9E64,
              result: 0x7AA2F7, error: 0xDB4B4B, caret: 0xC0CAF5, activeLine: ThemeColor(hex: 0x292E42),
              sidebar: 0x16161E, sidebarSelection: 0x292E42, secondaryText: 0xA9B1D6, tertiaryText: 0x565F89,
              border: ThemeColor(hex: 0x15161E), inputBackground: 0x0C0E14,
              syntax: SyntaxColors(heading: 0x7AA2F7, comment: 0x565F89, value: 0xFF9E64, calendarDate: 0x9ECE6A,
                                   timeOfDay: 0x9D7CD8, unit: 0x2AC3DE, name: 0x7AA2F7)),
        Theme("tokyo-night-moon", "Tokyo Night Moon", .dark,
              background: 0x222436, text: 0xC8D3F5, lineNumber: 0x3B4261, lineNumberActive: 0xFF966C,
              result: 0x82AAFF, error: 0xC53B53, caret: 0xC8D3F5, activeLine: ThemeColor(hex: 0x2F334D),
              sidebar: 0x1E2030, sidebarSelection: 0x2F334D, secondaryText: 0x828BB8, tertiaryText: 0x636DA6,
              border: ThemeColor(hex: 0x1B1D2B), inputBackground: 0x191B29,
              syntax: SyntaxColors(heading: 0x82AAFF, comment: 0x636DA6, value: 0xFF966C, calendarDate: 0xC3E88D,
                                   timeOfDay: 0xFCA7EA, unit: 0x65BCFF, name: 0x82AAFF)),
        Theme("tokyo-night-storm", "Tokyo Night Storm", .dark,
              background: 0x24283B, text: 0xC0CAF5, lineNumber: 0x3B4261, lineNumberActive: 0xFF9E64,
              result: 0x7AA2F7, error: 0xDB4B4B, caret: 0xC0CAF5, activeLine: ThemeColor(hex: 0x292E42),
              sidebar: 0x1F2335, sidebarSelection: 0x292E42, secondaryText: 0xA9B1D6, tertiaryText: 0x565F89,
              border: ThemeColor(hex: 0x1D202F), inputBackground: 0x1B1E2D,
              syntax: SyntaxColors(heading: 0x7AA2F7, comment: 0x565F89, value: 0xFF9E64, calendarDate: 0x9ECE6A,
                                   timeOfDay: 0x9D7CD8, unit: 0x2AC3DE, name: 0x7AA2F7))
    ]
}

extension Theme {
    /// Each theme maps its palette roles the same way: the base is the sheet,
    /// the blue family colors results and the caret, red colors errors, the
    /// darker surface is the sheet list, and the muted tones are line numbers
    /// and tertiary text.
    init(
        _ id: String, _ name: String, _ kind: Kind,
        background: UInt32, text: UInt32, lineNumber: UInt32, lineNumberActive: UInt32,
        result: UInt32, error: UInt32, caret: UInt32, activeLine: ThemeColor,
        sidebar: UInt32, sidebarSelection: UInt32, secondaryText: UInt32, tertiaryText: UInt32,
        border: ThemeColor, inputBackground: UInt32,
        syntax: SyntaxColors
    ) {
        self.init(
            id: id, name: name, kind: kind,
            background: ThemeColor(hex: background), text: ThemeColor(hex: text),
            lineNumber: ThemeColor(hex: lineNumber), lineNumberActive: ThemeColor(hex: lineNumberActive),
            result: ThemeColor(hex: result), error: ThemeColor(hex: error), caret: ThemeColor(hex: caret),
            activeLine: activeLine, sidebar: ThemeColor(hex: sidebar),
            sidebarSelection: ThemeColor(hex: sidebarSelection),
            secondaryText: ThemeColor(hex: secondaryText), tertiaryText: ThemeColor(hex: tertiaryText),
            border: border, inputBackground: ThemeColor(hex: inputBackground),
            syntax: syntax
        )
    }
}

/// The colors a theme gives the parts of a sheet line that stand out from
/// its text. Every theme other than Default takes from its official palette
/// the number color for a value, the string color for a calendar date, the
/// keyword color for a time-of-day, the type color for a unit, and the
/// function color for a name. Monokai shows a time-of-day in orange because
/// its keyword color is its error color, and Rosé Pine shows a name in the
/// heading color because its function color is its number color.
public struct SyntaxColors: Equatable, Sendable {
    public let heading: ThemeColor
    public let comment: ThemeColor
    public let value: ThemeColor
    public let calendarDate: ThemeColor
    public let timeOfDay: ThemeColor
    public let unit: ThemeColor
    public let name: ThemeColor

    init(
        heading: UInt32, comment: UInt32, value: UInt32, calendarDate: UInt32,
        timeOfDay: UInt32, unit: UInt32, name: UInt32
    ) {
        self.heading = ThemeColor(hex: heading)
        self.comment = ThemeColor(hex: comment)
        self.value = ThemeColor(hex: value)
        self.calendarDate = ThemeColor(hex: calendarDate)
        self.timeOfDay = ThemeColor(hex: timeOfDay)
        self.unit = ThemeColor(hex: unit)
        self.name = ThemeColor(hex: name)
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
