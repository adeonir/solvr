// The Settings theme comes from the same resolution as the main window: the
// mode, the macOS appearance, and the kept light and dark theme identifiers.
// The Default themes keep the system look.

import SolvrCore
import SwiftUI

private extension Color {
    init(_ value: ThemeColor) {
        self.init(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

/// Reads the active theme the same way the main window does.
private struct ActiveTheme: DynamicProperty {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceMode.key) private var modeName = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceMode.lightThemeKey) private var lightThemeID = Theme.defaultLight.id
    @AppStorage(AppearanceMode.darkThemeKey) private var darkThemeID = Theme.defaultDark.id

    var theme: Theme {
        Theme.active(
            mode: AppearanceMode(stored: modeName),
            systemIsDark: colorScheme == .dark,
            lightID: lightThemeID,
            darkID: darkThemeID
        )
    }

    var isDefault: Bool {
        theme.id == Theme.defaultLight.id || theme.id == Theme.defaultDark.id
    }
}

private struct SettingsThemeModifier: ViewModifier {
    private let active = ActiveTheme()

    @ViewBuilder
    func body(content: Content) -> some View {
        if active.isDefault {
            content
        } else {
            let theme = active.theme
            content
                .scrollContentBackground(.hidden)
                .background(Color(theme.background))
                .tint(Color(theme.result))
        }
    }
}

private struct SettingsRowModifier: ViewModifier {
    private let active = ActiveTheme()

    @ViewBuilder
    func body(content: Content) -> some View {
        if active.isDefault {
            content
        } else {
            content
                .foregroundStyle(Color(active.theme.text), Color(active.theme.secondaryText))
                .listRowBackground(Color(active.theme.sidebar))
                .listRowSeparatorTint(Color(active.theme.border))
        }
    }
}

private struct SettingsHeaderModifier: ViewModifier {
    private let active = ActiveTheme()

    @ViewBuilder
    func body(content: Content) -> some View {
        if active.isDefault {
            content
        } else {
            content.foregroundStyle(Color(active.theme.text))
        }
    }
}

private struct SettingsFieldModifier: ViewModifier {
    private let active = ActiveTheme()
    @FocusState private var isFocused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active.isDefault {
            content.textFieldStyle(.roundedBorder)
        } else {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            content
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, 6)
                .frame(height: 22)
                // A click on the field's background, outside the text, still starts editing.
                .background(
                    shape.fill(Color(active.theme.inputBackground))
                        .contentShape(shape)
                        .onTapGesture { isFocused = true }
                )
                .overlay(shape.strokeBorder(Color(active.theme.border)))
                .contentShape(shape)
                .pointerStyle(.horizontalText)
        }
    }
}

extension View {
    /// Draws the Settings form from the active theme.
    func settingsThemed() -> some View {
        modifier(SettingsThemeModifier())
    }

    /// Draws a Settings form row on the active theme's group color, with the
    /// theme's border color between rows.
    func settingsRow() -> some View {
        modifier(SettingsRowModifier())
    }

    /// Draws a Settings section label in the active theme's text color.
    func settingsHeader() -> some View {
        modifier(SettingsHeaderModifier())
    }

    /// Draws a Settings text field on the active theme's field background,
    /// edged in the theme's border color.
    func settingsField() -> some View {
        modifier(SettingsFieldModifier())
    }
}
