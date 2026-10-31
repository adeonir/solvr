import Foundation

/// An amount and its currency remain separate from display rounding.
public struct MonetaryValue: Sendable, Equatable {
    public var amount: Decimal
    public var currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency.uppercased()
    }
}

enum Money {
    static let symbols: [(String, String)] = [("R$", "BRL"), ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY")]
    /// Shared currencies (EUR, CHF and the regional X currencies) deliberately
    /// have no home locale. USD and GBP follow their unambiguous symbol forms.
    static let locales: [String: String] = Dictionary(uniqueKeysWithValues: """
    AED:ar_AE AFN:fa_AF ALL:sq_AL AMD:hy_AM ANG:nl_CW AOA:pt_AO ARS:es_AR AUD:en_AU AWG:nl_AW AZN:az_AZ
    BAM:bs_BA BBD:en_BB BDT:bn_BD BGN:bg_BG BHD:ar_BH BIF:fr_BI BMD:en_BM BND:ms_BN BOB:es_BO BRL:pt_BR BSD:en_BS BTN:dz_BT BWP:en_BW BYN:be_BY BZD:en_BZ
    CAD:en_CA CDF:fr_CD CLP:es_CL CNY:zh_CN COP:es_CO CRC:es_CR CUP:es_CU CVE:pt_CV CZK:cs_CZ DJF:fr_DJ DKK:da_DK DOP:es_DO DZD:ar_DZ EGP:ar_EG ETB:am_ET
    FJD:en_FJ FKP:en_FK GBP:en_GB GEL:ka_GE GHS:en_GH GIP:en_GI GMD:en_GM GNF:fr_GN GTQ:es_GT GYD:en_GY HKD:zh_HK HNL:es_HN HRK:hr_HR HTG:fr_HT HUF:hu_HU
    IDR:id_ID ILS:he_IL INR:en_IN IQD:ar_IQ IRR:fa_IR ISK:is_IS JMD:en_JM JOD:ar_JO JPY:ja_JP KES:en_KE KGS:ky_KG KHR:km_KH KMF:fr_KM KRW:ko_KR KWD:ar_KW KYD:en_KY KZT:kk_KZ
    LAK:lo_LA LBP:ar_LB LKR:si_LK LRD:en_LR LSL:en_LS LYD:ar_LY MAD:ar_MA MDL:ro_MD MGA:fr_MG MKD:mk_MK MMK:my_MM MNT:mn_MN MOP:zh_MO MRU:ar_MR MUR:en_MU MVR:dv_MV MWK:en_MW MXN:es_MX MYR:ms_MY MZN:pt_MZ
    NAD:en_NA NGN:en_NG NIO:es_NI NOK:nb_NO NPR:ne_NP NZD:en_NZ OMR:ar_OM PAB:es_PA PEN:es_PE PGK:en_PG PHP:en_PH PKR:en_PK PLN:pl_PL PYG:es_PY QAR:ar_QA RON:ro_RO RSD:sr_RS RUB:ru_RU RWF:rw_RW
    SAR:ar_SA SBD:en_SB SCR:en_SC SDG:ar_SD SEK:sv_SE SGD:en_SG SHP:en_SH SOS:so_SO SRD:nl_SR SSP:en_SS SVC:es_SV SYP:ar_SY SZL:en_SZ THB:th_TH TJS:tg_TJ TMT:tk_TM TND:ar_TN TOP:to_TO TRY:tr_TR TTD:en_TT TWD:zh_TW TZS:sw_TZ
    UAH:uk_UA UGX:en_UG USD:en_US UYU:es_UY UZS:uz_UZ VES:es_VE VND:vi_VN VUV:en_VU WST:en_WS YER:ar_YE ZAR:en_ZA ZMW:en_ZM
    """.split(whereSeparator: \.isWhitespace).map { pair in
        let fields = pair.split(separator: ":")
        // Keep the currency's regional separators with Latin decimal digits,
        // matching the calculator's numeric language.
        return (String(fields[0]), String(fields[1]) + "@numbers=latn")
    })
    static let names = FiatCurrencies.names

    static func scanName(at start: String.Index, in line: String) -> (String, String.Index)? {
        var index = start
        var words: [String] = []
        var match: (String, String.Index)?
        while index < line.endIndex, line[index].isLetter {
            let wordStart = index
            while index < line.endIndex, line[index].isLetter || line[index].isNumber || line[index] == "_" {
                index = line.index(after: index)
            }
            words.append(line[wordStart ..< index].lowercased())
            if let code = names[words.joined(separator: " ")] {
                match = (code, index)
            }
            while index < line.endIndex, Tokenizer.isBlank(line[index]) {
                index = line.index(after: index)
            }
        }
        return match
    }

    static func display(_ value: MonetaryValue, context: EvaluationContext) -> String {
        let symbol = symbols.first { $0.1 == value.currency }?.0 ?? value.currency
        let locale = Locale(identifier: locales[value.currency] ?? context.localeIdentifier)
        let precision = FiatCurrencies.byCode[value.currency]?.hasDecimalPlaces == false ? 0 : max(0, context.displayPrecision)
        let rounded = Numeric.roundPlain(value.amount, scale: precision)
        var number = Numeric.display(rounded, precision: precision, locale: locale)
        if rounded != Numeric.roundPlain(rounded, scale: 0), let separator = locale.decimalSeparator {
            let places = number.components(separatedBy: separator).last?.count ?? 0
            number += String(repeating: "0", count: max(0, precision - places))
        }
        return symbol + " " + number
    }

    static func scanLiteral(at start: String.Index, in line: String, locale: Locale) throws -> (MonetaryValue, String.Index)? {
        var index = start
        var code: String?
        for (symbol, currency) in symbols where line[index...].hasPrefix(symbol) {
            code = currency
            index = line.index(index, offsetBy: symbol.count)
            while index < line.endIndex, Tokenizer.isBlank(line[index]) {
                index = line.index(after: index)
            }
            break
        }
        let numberStart = index
        guard index < line.endIndex, line[index].isNumber else { return nil }
        while index < line.endIndex {
            let ch = line[index]
            if ch.isNumber || ch == "." || ch == "," {
                index = line.index(after: index)
            } else if Tokenizer.isBlank(ch) {
                let next = line.index(after: index)
                guard next < line.endIndex, line[next].isNumber else { break }
                index = next
            } else {
                break
            }
        }
        let numberEnd = index
        if code == nil {
            while index < line.endIndex, Tokenizer.isBlank(line[index]) {
                index = line.index(after: index)
            }
            guard let match = scanName(at: index, in: line) else { return nil }
            code = match.0
            index = match.1
        } else {
            index = numberEnd
        }
        let currency = code!
        let numberLocale = Locale(identifier: locales[currency] ?? locale.identifier)
        let separator = numberLocale.decimalSeparator?.first ?? "."
        let run = String(line[numberStart ..< numberEnd])
        // A no-decimal currency still accepts the fractional input `10,5 JPY`;
        // rounding is display-only. Prefer its own grouping interpretation,
        // then permit the other decimal separator for a fractional input.
        let alternateSeparator: Character = separator == "." ? "," : "."
        let fractionalAmount = FiatCurrencies.byCode[currency]?.hasDecimalPlaces == false ? Tokenizer.parseNumberRun(run, decimal: alternateSeparator, grouping: separator) : nil
        guard let amount = Tokenizer.parseNumberRun(run, decimal: separator, grouping: separator == "." ? "," : ".") ?? fractionalAmount else {
            throw LineError(diagnostic: .syntax)
        }
        return (MonetaryValue(amount: amount, currency: currency), index)
    }
}
