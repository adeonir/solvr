// The Settings window's Appearance tab (ADK-260, ADK-261, ADK-262). The font
// family menu and the sheet size and line height fields store a valid value as it is typed, so it reaches
// every open sheet at once. A cleared or invalid field restores its value
// when focus leaves it: the default for an empty field, otherwise the last
// valid value.

import NumeCore
import SwiftUI

struct AppearanceSettingsView: View {
    static let familyKey = "sheetFontFamily"
    static let sizeKey = "sheetFontSize"
    static let lineHeightKey = "sheetLineHeight"
    /// The row height of the Settings design, shared by both tabs.
    static let rowHeight: CGFloat = 24

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

    var body: some View {
        Form {
            Picker("Font", selection: $family) {
                ForEach(SheetFonts.menuFamilies(stored: family, in: InstalledFonts.faces), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(height: Self.rowHeight)
            HStack {
                Text("Size")
                Spacer()
                HStack(spacing: 8) {
                    TextField("", text: $sizeText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .focused($focused, equals: .size)
                    Text("px")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .leading)
                }
            }
            .frame(height: AppearanceSettingsView.rowHeight)
            HStack {
                Text("Line Height")
                Spacer()
                HStack(spacing: 8) {
                    TextField("", text: $lineHeightText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .focused($focused, equals: .lineHeight)
                    Color.clear
                        .frame(width: 20, height: 1)
                }
            }
            .frame(height: AppearanceSettingsView.rowHeight)
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onAppear {
            sizeText = String(size)
            lineHeightText = Self.format(lineHeight)
        }
        .onChange(of: sizeText) { _, text in
            storedSize = TypographySetting.committedSize(text, lastValid: size)
        }
        .onChange(of: lineHeightText) { _, text in
            storedLineHeight = TypographySetting.committedLineHeight(text, lastValid: lineHeight)
        }
        .onChange(of: focused) { previous, current in
            if previous == .size, current != .size {
                sizeText = String(size)
            }
            if previous == .lineHeight, current != .lineHeight {
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
