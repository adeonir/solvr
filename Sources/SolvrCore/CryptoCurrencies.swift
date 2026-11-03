import Foundation

/// Versioned catalog: only these cryptocurrencies enter the language, and only
/// a new version of the app changes them. They are the largest by market value
/// (CoinGecko, captured 2026-10-31) among those that Coinbase
/// /v2/exchange-rates?currency=USD gives a rate for, so every entry converts.
/// Rates are units per USD, retained as decimal strings.
public enum CryptoCurrencies {
    public struct Entry: Sendable, Equatable {
        public let code: String
        public let name: String
    }

    public static let entries: [Entry] = rows.map { Entry(code: $0[0], name: $0[1]) }

    static let codes = Set(entries.map(\.code))
    static let shippedRates: [String: Decimal] = Dictionary(uniqueKeysWithValues: rows.map {
        ($0[0], Decimal(string: $0[2], locale: Locale(identifier: "en_US_POSIX"))!)
    })

    /// Lower-case code, full name, and plural name, each mapping to the code.
    static let names: [String: String] = {
        var names: [String: String] = [:]
        for entry in entries {
            names[entry.code.lowercased()] = entry.code
            names[entry.name] = entry.code
            // "bitcoin cash" names a coin whose plural reads the same.
            names[entry.name == "bitcoin cash" ? entry.name : entry.name + "s"] = entry.code
        }
        return names
    }()

    private static let rows: [[String]] = snapshot.split(separator: "\n").map { $0.components(separatedBy: "|") }
    private static let snapshot = """
    BTC|bitcoin|0.000012895222449
    ETH|ethereum|0.0004422763077005
    USDT|tether|1.0011212558065033
    BNB|bnb|0.0014247043738424
    XRP|xrp|0.7982120051085568
    USDC|usd coin|1
    SOL|solana|0.0104264414555312
    ZEC|zcash|0.0007815247547966
    HYPE|hyperliquid|0.0113765642775882
    DOGE|dogecoin|13.1648235913638757
    USDS|usds|1.0001000100010001
    LINK|chainlink|0.0845665961945032
    ADA|cardano|5.1746442432082794
    XLM|stellar|5.8716802987510936
    NEAR|near protocol|0.225022502250225
    BCH|bitcoin cash|0.0035077872877789
    DAI|dai|1.00002860879654
    UNI|uniswap|0.1405441870924219
    LTC|litecoin|0.0178265830005705
    USD1|usd1|1.0017028949213663
    AVAX|avalanche|0.1165772907437631
    SUI|sui|1.1113580795732385
    HBAR|hedera|13.8542532557495151
    QNT|quant|0.0049773530436514
    PYUSD|paypal usd|1
    TAO|bittensor|0.0042038002354128
    SHIB|shiba inu|213219.6162046908315565
    CRO|cronos|19.3911188675586581
    ENA|ethena|5.2637119696810191
    RLUSD|ripple usd|1
    """
}
