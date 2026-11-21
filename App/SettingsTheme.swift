// The active theme's colors for the Settings window (ADK-330). The theme comes
// from the same resolution as the main window: the mode, the macOS appearance,
// and the kept light and dark theme identifiers. The Default themes keep the
// system look.

import SolvrCore
import SwiftUI

private extension Color {
    init(_ value: ThemeColor) {
        self.init(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

private struct SettingsThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceMode.key) private var modeName = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceMode.lightThemeKey) private var lightThemeID = Theme.defaultLight.id
    @AppStorage(AppearanceMode.darkThemeKey) private var darkThemeID = Theme.defaultDark.id

    private var theme: Theme {
        Theme.active(
            mode: AppearanceMode(stored: modeName),
            systemIsDark: colorScheme == .dark,
            lightID: lightThemeID,
            darkID: darkThemeID
        )
    }

    private var isDefault: Bool {
        theme.id == Theme.defaultLight.id || theme.id == Theme.defaultDark.id
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDefault {
            content
        } else {
            content
                .scrollContentBackground(.hidden)
                .background(Color(theme.background))
                .foregroundStyle(Color(theme.text), Color(theme.secondaryText))
                .tint(Color(theme.result))
        }
    }
}

private struct SettingsRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceMode.key) private var modeName = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceMode.lightThemeKey) private var lightThemeID = Theme.defaultLight.id
    @AppStorage(AppearanceMode.darkThemeKey) private var darkThemeID = Theme.defaultDark.id

    @ViewBuilder
    func body(content: Content) -> some View {
        let theme = Theme.active(
            mode: AppearanceMode(stored: modeName),
            systemIsDark: colorScheme == .dark,
            lightID: lightThemeID,
            darkID: darkThemeID
        )
        if theme.id == Theme.defaultLight.id || theme.id == Theme.defaultDark.id {
            content
        } else {
            content.listRowBackground(Color(theme.sidebar))
        }
    }
}

extension View {
    /// Draws the Settings form from the active theme.
    func settingsThemed() -> some View {
        modifier(SettingsThemeModifier())
    }

    /// Draws a Settings form row on the active theme's group color.
    func settingsRow() -> some View {
        modifier(SettingsRowModifier())
    }
}
