// The Settings window's Appearance tab (ADK-260). The font family menu is
// the first typography field (ADK-262); size and line height join it in a
// later task. The chosen family applies to every open sheet at once.

import NumeCore
import SwiftUI

struct AppearanceSettingsView: View {
    static let familyKey = "sheetFontFamily"

    @AppStorage(familyKey) private var family = SheetTypography.defaultFamily

    var body: some View {
        Form {
            Picker("Font", selection: $family) {
                ForEach(SheetFonts.menuFamilies(stored: family, in: InstalledFonts.faces), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
