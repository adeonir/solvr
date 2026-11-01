import Foundation

/// Versioned catalog: only these codes enter the language, never codes learned
/// from an update. Names and decimal support come from Coinbase /v2/currencies;
/// membership is its intersection with /v2/exchange-rates?currency=USD.
/// Captured 2026-10-31. Rates are units per USD, retained as decimal strings.
public enum FiatCurrencies {
    public struct Entry: Sendable, Equatable {
        public let code: String
        public let name: String
        public let hasDecimalPlaces: Bool
    }

    public static let entries: [Entry] = rows.map {
        Entry(code: $0[0], name: $0[1], hasDecimalPlaces: $0[2] == "1")
    }

    static let byCode = Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
    static let shippedRates: [String: Decimal] = Dictionary(uniqueKeysWithValues: rows.map {
        ($0[0], Decimal(string: $0[3], locale: Locale(identifier: "en_US_POSIX"))!)
    })

    static let names: [String: String] = {
        var names: [String: String] = [:]
        let plurals = ["real": "reais", "krone": "kroner", "krona": "kronor", "leu": "lei", "loti": "maloti", "lilangeni": "emalangeni", "yen": "yen", "won": "won", "yuan": "yuan", "renminbi": "renminbi", "baht": "baht", "rand": "rand", "złoty": "złotys"]
        for entry in entries {
            names[entry.code.lowercased()] = entry.code
            var words = entry.name.components(separatedBy: " ")
            let last = words.removeLast()
            let plural = (words + [plurals[last] ?? last + "s"]).joined(separator: " ")
            for name in [entry.name, plural] {
                names[name] = entry.code
                names[name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))] = entry.code
            }
        }
        for (name, code) in ["dollar": "USD", "dollars": "USD", "pound": "GBP", "pounds": "GBP", "yen": "JPY", "brazilian real": "BRL", "brazilian reais": "BRL", "brazilian reals": "BRL", "reals": "BRL", "chinese yuan": "CNY", "chinese yuans": "CNY", "british pounds sterling": "GBP", "pound sterling": "GBP", "pounds sterling": "GBP"] {
            names[name] = code
        }
        return names
    }()

    private static let rows: [[String]] = snapshot.split(separator: "\n").map { $0.components(separatedBy: "|") }
    private static let snapshot = """
    AED|united arab emirates dirham|1|3.67255
    AFN|afghan afghani|1|64.5208955
    ALL|albanian lek|1|81.234586
    AMD|armenian dram|1|360.0225355
    ANG|netherlands antillean gulden|1|1.79
    AOA|angolan kwanza|1|915.5
    ARS|argentine peso|1|1535.38
    AUD|australian dollar|1|1.4225
    AWG|aruban florin|1|1.8025
    AZN|azerbaijani manat|1|1.7
    BAM|bosnia and herzegovina convertible mark|1|1.748785
    BBD|barbadian dollar|1|2
    BDT|bangladeshi taka|1|124.076021
    BGN|bulgarian lev|1|1.7528
    BHD|bahraini dinar|1|0.377277
    BIF|burundian franc|0|2999.327512
    BMD|bermudian dollar|1|1
    BND|brunei dollar|1|1.2771055
    BOB|bolivian boliviano|1|11.5703
    BRL|real|1|5.439299999999999
    BSD|bahamian dollar|1|1
    BTN|bhutanese ngultrum|1|94.859449
    BWP|botswana pula|1|13.806105
    BYN|belarusian ruble|1|2.944059
    BZD|belize dollar|1|2.0109265
    CAD|canadian dollar|1|1.39753
    CDF|congolese franc|1|2313.316259
    CHF|swiss franc|1|0.8243905
    CLP|chilean peso|0|993.045
    CNY|chinese renminbi yuan|1|6.657415
    COP|colombian peso|1|3191.85515
    CRC|costa rican colón|1|454.4732535
    CUP|cuban peso|1|25.375
    CVE|cape verdean escudo|1|98.5929325
    CZK|czech koruna|1|21.81685
    DJF|djiboutian franc|0|177.7795645
    DKK|danish krone|1|6.69737
    DOP|dominican peso|1|60.620541
    DZD|algerian dinar|1|135.704
    EGP|egyptian pound|1|55.8631185
    ETB|ethiopian birr|1|161.3486585
    EUR|euro|1|0.894543502165275
    FJD|fijian dollar|1|2.243325
    FKP|falkland pound|1|0.746638
    GBP|british pound|1|0.74663788460103
    GEL|georgian lari|1|2.5969
    GHS|ghanaian cedi|1|11.641633
    GIP|gibraltar pound|1|0.746638
    GMD|gambian dalasi|1|74.0771525
    GNF|guinean franc|0|8845.58665
    GTQ|guatemalan quetzal|1|7.640504
    GYD|guyanese dollar|1|209.490578
    HKD|hong kong dollar|1|7.845245
    HNL|honduran lempira|1|26.878193
    HRK|croatian kuna|1|6.75234
    HTG|haitian gourde|1|130.946653
    HUF|hungarian forint|0|327.9455
    IDR|indonesian rupiah|1|18134.525
    ILS|israeli new sheqel|1|3.1437
    INR|indian rupee|1|94.9242005
    IQD|iraqi dinar|1|1515.079406
    IRR|iranian rial|1|1868410
    ISK|icelandic króna|0|121.8225
    JMD|jamaican dollar|1|158.793815
    JOD|jordanian dinar|1|0.709
    JPY|japanese yen|0|157.592037235
    KES|kenyan shilling|1|129.87
    KGS|kyrgyzstani som|1|87.4487
    KHR|cambodian riel|1|4077.7247915
    KMF|comorian franc|0|440.948018
    KRW|south korean won|0|1333.32
    KWD|kuwaiti dinar|1|0.310477
    KYD|cayman islands dollar|1|0.8328315
    KZT|kazakhstani tenge|1|453.234991
    LAK|lao kip|1|22502.0202465
    LBP|lebanese pound|1|89490.7066495
    LKR|sri lankan rupee|1|332.4296535
    LRD|liberian dollar|1|169.89578
    LSL|lesotho loti|1|16.6761215
    LYD|libyan dinar|1|6.4246135
    MAD|moroccan dirham|1|9.82782
    MDL|moldovan leu|1|17.8906465
    MGA|malagasy ariary|1|4520.730901
    MKD|macedonian denar|1|54.970193
    MMK|myanmar kyat|1|2099.975
    MNT|mongolian tögrög|1|2623.5
    MOP|macanese pataca|1|8.0753175
    MRU|mauritanian ouguiya|1|40.4683265
    MUR|mauritian rupee|1|47.280001
    MVR|maldivian rufiyaa|1|15.4511
    MWK|malawian kwacha|1|1732.6417385
    MXN|mexican peso|1|18.787075
    MYR|malaysian ringgit|1|4.058195
    MZN|mozambican metical|1|63.869997
    NAD|namibian dollar|1|16.6761215
    NGN|nigerian naira|1|1346.47
    NIO|nicaraguan córdoba|1|36.778169
    NOK|norwegian krone|1|9.211175
    NPR|nepalese rupee|1|151.756308
    NZD|new zealand dollar|1|1.774231
    OMR|omani rial|1|0.3844515
    PAB|panamanian balboa|1|1
    PEN|peruvian sol|1|3.4597745
    PGK|papua new guinean kina|1|4.548156
    PHP|philippine peso|1|63.743975
    PKR|pakistani rupee|1|276.488265
    PLN|polish złoty|1|3.947941
    PYG|paraguayan guaraní|0|5855.3972565
    QAR|qatari riyal|1|3.64324
    RON|romanian leu|1|4.78205
    RSD|serbian dinar|1|105.26992
    RUB|russian ruble|1|80.4660985
    RWF|rwandan franc|0|1475.347449
    SAR|saudi riyal|1|3.75404
    SBD|solomon islands dollar|1|8.058208
    SCR|seychellois rupee|1|13.7610885
    SDG|sudanese pound|1|601.5
    SEK|swedish krona|1|9.82645
    SGD|singapore dollar|1|1.27852
    SHP|saint helenian pound|1|0.746638
    SOS|somali shilling|1|571.14958
    SRD|surinamese dollar|1|37.62835
    SSP|south sudanese pound|1|130.26
    SVC|salvadoran colón|1|8.744508
    SYP|syrian pound|1|512.795
    SZL|swazi lilangeni|1|16.673579
    THB|thai baht|1|33.67114
    TJS|tajikistani somoni|1|9.2028105
    TMT|turkmenistani manat|1|3.52977
    TND|tunisian dinar|1|2.992416
    TOP|tongan paʻanga|1|2.40776
    TRY|turkish lira|1|49.94055
    TTD|trinidad and tobago dollar|1|6.776407
    TWD|new taiwan dollar|1|32.62325
    TZS|tanzanian shilling|1|2641.799
    UAH|ukrainian hryvnia|1|45.352986
    UGX|ugandan shilling|0|4251.0457515
    USD|united states dollar|1|1
    UYU|uruguayan peso|1|40.2011835
    UZS|uzbekistan som|1|11987.4167775
    VES|venezuelan bolívar soberano|1|887.6022135
    VND|vietnamese đồng|0|25803.3113035
    VUV|vanuatu vatu|0|115.785
    WST|samoan tala|1|2.763185
    XAF|central african cfa franc|0|586.7820205
    XCD|east caribbean dollar|1|2.701275
    XOF|west african cfa franc|0|586.7820205
    XPF|cfp franc|0|106.7474775
    YER|yemeni rial|1|236.1655295
    ZAR|south african rand|1|16.7136975
    ZMW|zambian kwacha|1|20.17003
    """
}
