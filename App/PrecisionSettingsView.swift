// The Settings window's display precision fields (ADK-255). A valid value
// is stored as it is typed and reaches every open sheet at once. A cleared
// or invalid field restores its last valid value when focus leaves it.

import SolvrCore
import SwiftUI

struct PrecisionSettingsView: View {
    static let generalKey = "generalPrecision"
    static let cryptoKey = "cryptoPrecision"

    @AppStorage(generalKey) private var generalPrecision = PrecisionSetting.generalDefault
    @AppStorage(cryptoKey) private var cryptoPrecision = PrecisionSetting.cryptoDefault
    @State private var generalText = ""
    @State private var cryptoText = ""
    @FocusState private var focused: Field?

    private enum Field {
        case general
        case crypto
    }

    private var generalValue: Int {
        PrecisionSetting.stored(generalPrecision, in: PrecisionSetting.generalRange, default: PrecisionSetting.generalDefault)
    }

    private var cryptoValue: Int {
        PrecisionSetting.stored(cryptoPrecision, in: PrecisionSetting.cryptoRange, default: PrecisionSetting.cryptoDefault)
    }

    var body: some View {
        Form {
            HStack {
                Text("General precision")
                Spacer()
                TextField("", text: $generalText)
                    .settingsField()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .focused($focused, equals: .general)
            }
            .frame(height: AppearanceSettingsView.rowHeight)
            .settingsRow()
            HStack {
                Text("Crypto precision")
                Spacer()
                TextField("", text: $cryptoText)
                    .settingsField()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .focused($focused, equals: .crypto)
            }
            .frame(height: AppearanceSettingsView.rowHeight)
            .settingsRow()
        }
        .formStyle(.grouped)
        .settingsThemed()
        .frame(width: 500)
        .onAppear {
            generalText = String(generalValue)
            cryptoText = String(cryptoValue)
        }
        .onChange(of: generalText) { _, text in
            generalPrecision = PrecisionSetting.committed(text, in: PrecisionSetting.generalRange, lastValid: generalValue)
        }
        .onChange(of: cryptoText) { _, text in
            cryptoPrecision = PrecisionSetting.committed(text, in: PrecisionSetting.cryptoRange, lastValid: cryptoValue)
        }
        .onChange(of: focused) { previous, current in
            if previous == .general, current != .general {
                generalText = String(generalValue)
            }
            if previous == .crypto, current != .crypto {
                cryptoText = String(cryptoValue)
            }
        }
    }
}
