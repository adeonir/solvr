import Testing

@testable import SolvrCore

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

    @Test func aThemeKeepsItsFamilyColors() {
        #expect(Theme.catalog.first { $0.id == "dracula" }?.color(for: .comment) == ThemeColor(hex: 0x6272A4))
        #expect(Theme.catalog.first { $0.id == "dracula" }?.color(for: .monetaryValue) == ThemeColor(hex: 0x50FA7B))
        #expect(Theme.catalog.first { $0.id == "catppuccin-mocha" }?.color(for: .number) == ThemeColor(hex: 0xFAB387))
    }

    @Test func theDefaultThemesColorTheHeadingLikeThePlainText() {
        #expect(Theme.defaultLight.color(for: .heading) == Theme.defaultLight.text)
        #expect(Theme.defaultDark.color(for: .heading) == Theme.defaultDark.text)
    }
}
