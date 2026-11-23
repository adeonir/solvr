// The font family menu and the sheet size and line height fields store a
// valid value as it is typed, so it reaches every open sheet at once. A
// cleared or invalid field restores its value when focus leaves it: the
// default for an empty field, otherwise the last valid value.

import Core
import SwiftUI

extension AppearanceMode {
    static let key = "appearanceMode"
    static let lightThemeKey = "lightThemeID"
    static let darkThemeKey = "darkThemeID"

    /// The appearance forced on the app, or nil to let macOS decide.
    var appearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
    }
}

struct AppearanceSettingsView: View {
    static let familyKey = "sheetFontFamily"
    static let sizeKey = "sheetFontSize"
    static let lineHeightKey = "sheetLineHeight"
    /// The row height of the Settings design, shared by both tabs.
    static let rowHeight: CGFloat = 24

    @AppStorage(AppearanceMode.key) private var modeName = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceMode.lightThemeKey) private var lightThemeID = Theme.defaultLight.id
    @AppStorage(AppearanceMode.darkThemeKey) private var darkThemeID = Theme.defaultDark.id
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(familyKey) private var family = SheetTypography.defaultFamily
    @AppStorage(sizeKey) private var storedSize = TypographySetting.sizeDefault
    @AppStorage(lineHeightKey) private var storedLineHeight = TypographySetting.lineHeightDefault
    @State private var sizeText = ""
    @State private var lineHeightText = ""
    @FocusState private var focused: Field?

    private enum Field {
        case size
        case lineHeight
    }

    private var size: Int {
        TypographySetting.storedSize(storedSize)
    }

    private var lineHeight: Double {
        TypographySetting.storedLineHeight(storedLineHeight)
    }

    /// The kind the window shows now: the mode decides it, and Auto follows macOS.
    private var kind: Theme.Kind {
        Theme.active(mode: AppearanceMode(stored: modeName), systemIsDark: colorScheme == .dark, lightID: nil, darkID: nil).kind
    }

    private var defaultTheme: Theme {
        kind == .light ? .defaultLight : .defaultDark
    }

    /// The theme kept for the current kind; a choice is kept for that kind only.
    private var themeID: Binding<String> {
        Binding(
            get: {
                let kept = kind == .light ? lightThemeID : darkThemeID
                return Theme.list(for: kind).first { $0.id == kept }?.id ?? defaultTheme.id
            },
            set: { kind == .light ? (lightThemeID = $0) : (darkThemeID = $0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $modeName) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(height: Self.rowHeight)
                .settingsRow()
                Picker("Theme", selection: themeID) {
                    Text("Default").tag(defaultTheme.id)
                    Divider()
                    ForEach(Theme.list(for: kind).dropFirst()) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .frame(height: Self.rowHeight)
                .settingsRow()
            } header: {
                Text("Colors").settingsHeader()
            }
            Section {
                Picker("Font", selection: $family) {
                    ForEach(SheetFonts.monospacedFamilies(in: InstalledFonts.faces), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(height: Self.rowHeight)
                .settingsRow()
                HStack {
                    Text("Size")
                    Spacer()
                    HStack(spacing: 8) {
                        TextField("", text: $sizeText)
                            .settingsField()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .focused($focused, equals: .size)
                        Text("px")
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .leading)
                    }
                }
                .frame(height: AppearanceSettingsView.rowHeight)
                .settingsRow()
                HStack {
                    Text("Line Height")
                    Spacer()
                    HStack(spacing: 8) {
                        TextField("", text: $lineHeightText)
                            .settingsField()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .focused($focused, equals: .lineHeight)
                        Color.clear
                            .frame(width: 20, height: 1)
                    }
                }
                .frame(height: AppearanceSettingsView.rowHeight)
                .settingsRow()
            } header: {
                Text("Typography").settingsHeader()
            }
        }
        .formStyle(.grouped)
        .settingsThemed()
        .frame(width: 500)
        .onAppear {
            // The stored family returns to the default when it is no longer
            // installed, and the menu shows the installed families only.
            family = SheetFonts.resolvedFamily(family, in: InstalledFonts.faces)
            sizeText = String(size)
            lineHeightText = Self.format(lineHeight)
        }
        .onChange(of: sizeText) { _, text in
            // A valid size commits as typed; an empty or invalid field holds
            // its last valid size and commits on focus leave.
            if let size = TypographySetting.validSize(of: text) {
                storedSize = size
            }
        }
        .onChange(of: lineHeightText) { _, text in
            // A valid line height commits as typed; an empty or invalid field
            // holds its last valid value and commits on focus leave.
            if let lineHeight = TypographySetting.validLineHeight(of: text) {
                storedLineHeight = lineHeight
            }
        }
        .onChange(of: focused) { previous, current in
            if previous == .size, current != .size {
                // The empty field commits the default, any other invalid text
                // commits the last valid value, and the field shows the result.
                storedSize = TypographySetting.committedSize(sizeText, lastValid: size)
                sizeText = String(size)
            }
            if previous == .lineHeight, current != .lineHeight {
                storedLineHeight = TypographySetting.committedLineHeight(lineHeightText, lastValid: lineHeight)
                lineHeightText = Self.format(lineHeight)
            }
        }
    }

    /// The line height as CSS number text: a dot separator and no trailing
    /// zero, whatever the regional number formatting.
    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
