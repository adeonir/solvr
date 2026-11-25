@testable import Core
import Testing

struct ThemeCatalogTests {
    @Test func themeIdentifiersAreUnique() {
        #expect(Set(Theme.catalog.map(\.id)).count == Theme.catalog.count)
    }

    @Test func defaultLightKeepsTheAppleColors() {
        let theme = Theme.defaultLight
        #expect(theme.background == ThemeColor(hex: 0xFFFFFF))
        #expect(theme.text == ThemeColor(hex: 0x1D1D1F))
        #expect(theme.result == ThemeColor(hex: 0x0062CC))
        #expect(theme.error == ThemeColor(hex: 0xD70015))
        #expect(theme.sidebar == ThemeColor(hex: 0xF2F2F4))
        #expect(theme.activeLine == ThemeColor(hex: 0x000000, alpha: 0.05))
    }

    @Test func defaultDarkKeepsTheAppleColors() {
        let theme = Theme.defaultDark
        #expect(theme.background == ThemeColor(hex: 0x1E1E1E))
        #expect(theme.text == ThemeColor(hex: 0xF5F5F7))
        #expect(theme.result == ThemeColor(hex: 0x4DA3FF))
        #expect(theme.error == ThemeColor(hex: 0xFF453A))
        #expect(theme.sidebar == ThemeColor(hex: 0x232326))
        #expect(theme.activeLine == ThemeColor(hex: 0xFFFFFF, alpha: 0.06))
    }
}

struct ThemeSyntaxColorTests {
    @Test func everyThemeColorsEverySyntaxKindApartFromTheBackground() {
        for theme in Theme.catalog {
            for kind in SyntaxKind.allCases {
                #expect(theme.color(for: kind) != theme.background, "\(theme.id) \(kind)")
            }
        }
    }

    @Test func aCommentDiffersFromThePlainText() {
        for theme in Theme.catalog {
            #expect(theme.color(for: .comment) != theme.text, "\(theme.id)")
        }
    }

    /// Each theme's colors for value, calendar date, time-of-day, unit,
    /// name, and muted, in that order.
    private static let meaningColors: [(String, [UInt32])] = [
        ("default-light", [0xB25000, 0x248A3D, 0x8A6D3B, 0x0E7C86, 0x5856D6, 0x636368]),
        ("default-dark", [0xFF9F0A, 0x32D74B, 0xD6B07A, 0x40C8E0, 0x7D7AFF, 0xA1A1A6]),
        ("alucard", [0x644AC9, 0x846E15, 0xA3144D, 0x036A96, 0x14710A, 0x6C664B]),
        ("catppuccin-latte", [0xFE640B, 0x40A02B, 0x8839EF, 0xDF8E1D, 0x1E66F5, 0x6C6F85]),
        ("monokai-light", [0xAE81FF, 0xE6DB74, 0xFD971F, 0xA6E22E, 0xA6E22E, 0x75715E]),
        ("one-light", [0xB76B01, 0x50A14F, 0xA626A4, 0x0184BC, 0x4078F2, 0x696C77]),
        ("rose-pine-dawn", [0xD7827E, 0xEA9D34, 0x286983, 0x56949F, 0x907AA9, 0x797593]),
        ("tokyo-night-day", [0xB15C00, 0x587539, 0x7847BD, 0x188092, 0x2E7DE9, 0x6172B0]),
        ("catppuccin-frappe", [0xEF9F76, 0xA6D189, 0xCA9EE6, 0xE5C890, 0x8CAAEE, 0xA5ADCE]),
        ("catppuccin-macchiato", [0xF5A97F, 0xA6DA95, 0xC6A0F6, 0xEED49F, 0x8AADF4, 0xA5ADCB]),
        ("catppuccin-mocha", [0xFAB387, 0xA6E3A1, 0xCBA6F7, 0xF9E2AF, 0x89B4FA, 0xA6ADC8]),
        ("dracula", [0xBD93F9, 0xF1FA8C, 0xFF79C6, 0x8BE9FD, 0x50FA7B, 0x6272A4]),
        ("monokai-dark", [0xAE81FF, 0xE6DB74, 0xFD971F, 0xA6E22E, 0xA6E22E, 0x90908A]),
        ("one-dark", [0xD19A66, 0x98C379, 0xC678DD, 0x56B6C2, 0x61AFEF, 0x828997]),
        ("rose-pine", [0xEBBCBA, 0xF6C177, 0x31748F, 0x9CCFD8, 0xC4A7E7, 0x908CAA]),
        ("rose-pine-moon", [0xEA9A97, 0xF6C177, 0x3E8FB0, 0x9CCFD8, 0xC4A7E7, 0x908CAA]),
        ("tokyo-night", [0xFF9E64, 0x9ECE6A, 0x9D7CD8, 0x2AC3DE, 0x7AA2F7, 0xA9B1D6]),
        ("tokyo-night-moon", [0xFF966C, 0xC3E88D, 0xFCA7EA, 0x65BCFF, 0x82AAFF, 0x828BB8]),
        ("tokyo-night-storm", [0xFF9E64, 0x9ECE6A, 0x9D7CD8, 0x2AC3DE, 0x7AA2F7, 0xA9B1D6])
    ]

    @Test(arguments: meaningColors)
    func aThemeColorsEachMeaning(id: String, hexes: [UInt32]) throws {
        let theme = try #require(Theme.catalog.first { $0.id == id })
        let kinds: [SyntaxKind] = [.value, .calendarDate, .timeOfDay, .unit, .name, .muted]
        #expect(kinds.map { theme.color(for: $0) } == hexes.map { ThemeColor(hex: $0) })
    }

    @Test func everyThemeHasItsMeaningColorsListed() {
        #expect(Set(Self.meaningColors.map(\.0)) == Set(Theme.catalog.map(\.id)))
    }

    @Test func aThemeKeepsItsCommentColor() {
        #expect(Theme.catalog.first { $0.id == "dracula" }?.color(for: .comment) == ThemeColor(hex: 0x6272A4))
    }

    @Test func theDefaultThemesColorTheHeadingLikeThePlainText() {
        #expect(Theme.defaultLight.color(for: .heading) == Theme.defaultLight.text)
        #expect(Theme.defaultDark.color(for: .heading) == Theme.defaultDark.text)
    }
}
