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
