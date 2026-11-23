import Testing

@testable import Core

struct ThemeChoiceTests {
    @Test func lightListHoldsDefaultThenTheOtherLightThemesAlphabetically() {
        #expect(Theme.list(for: .light).map(\.name) == [
            "Default", "Alucard", "Catppuccin Latte", "Monokai Light", "One Light", "Rosé Pine Dawn", "Tokyo Night Day"
        ])
    }

    @Test func darkListHoldsDefaultThenTheOtherDarkThemesAlphabetically() {
        #expect(Theme.list(for: .dark).map(\.name) == [
            "Default", "Catppuccin Frappé", "Catppuccin Macchiato", "Catppuccin Mocha", "Dracula", "Monokai Dark",
            "One Dark", "Rosé Pine", "Rosé Pine Moon", "Tokyo Night", "Tokyo Night Moon", "Tokyo Night Storm"
        ])
    }

    @Test func everyListedThemeMatchesItsKind() {
        #expect(Theme.list(for: .light).allSatisfy { $0.kind == .light })
        #expect(Theme.list(for: .dark).allSatisfy { $0.kind == .dark })
    }

    @Test func everyThemeHasItsOwnErrorColor() {
        let errors = Theme.catalog.map(\.error)
        #expect(Theme.catalog.count == 19)
        for theme in Theme.catalog {
            #expect(theme.error != theme.text)
            #expect(theme.error != theme.background)
        }
        #expect(Theme.catalog.first { $0.id == "catppuccin-mocha" }?.error == ThemeColor(hex: 0xF38BA8))
        #expect(errors.count == Theme.catalog.count)
    }

    @Test func autoFollowsTheSystemAppearanceAndAppliesTheThemeKeptForIt() {
        let kept = (light: "catppuccin-latte", dark: "dracula")
        #expect(Theme.active(mode: .auto, systemIsDark: true, lightID: kept.light, darkID: kept.dark).name == "Dracula")
        #expect(Theme.active(mode: .auto, systemIsDark: false, lightID: kept.light, darkID: kept.dark).name == "Catppuccin Latte")
    }

    @Test func changingModeByHandAppliesTheThemeKeptForTheNewMode() {
        let dark = Theme.active(mode: .dark, systemIsDark: false, lightID: "alucard", darkID: "dracula")
        #expect(dark.name == "Dracula")
        let light = Theme.active(mode: .light, systemIsDark: true, lightID: "alucard", darkID: "dracula")
        #expect(light.name == "Alucard")
    }

    @Test func noThemeChosenYetAppliesDefault() {
        #expect(Theme.active(mode: .dark, systemIsDark: false, lightID: nil, darkID: nil) == .defaultDark)
        #expect(Theme.active(mode: .light, systemIsDark: true, lightID: nil, darkID: nil) == .defaultLight)
    }

    @Test func unknownIdentifierResolvesToDefault() {
        #expect(Theme.active(mode: .dark, systemIsDark: false, lightID: nil, darkID: "nope") == .defaultDark)
    }

    @Test func identifierOfTheOtherKindResolvesToDefault() {
        #expect(Theme.active(mode: .dark, systemIsDark: false, lightID: nil, darkID: "alucard") == .defaultDark)
    }

    @Test func storedModeFallsBackToAuto() {
        #expect(AppearanceMode(stored: "Dark") == .dark)
        #expect(AppearanceMode(stored: "Light") == .light)
        #expect(AppearanceMode(stored: "garbage") == .auto)
    }
}
