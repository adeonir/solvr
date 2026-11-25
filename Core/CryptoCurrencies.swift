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
        ($0[0], Decimal(string: $0[3], locale: Locale(identifier: "en_US_POSIX"))!)
    })

    static let names: [String: String] = {
        var names: [String: String] = [:]
        for row in rows {
            names[row[0].lowercased()] = row[0]
            names[row[1]] = row[0]
            names[row[2]] = row[0]
        }
        return names
    }()

    private static let rows: [[String]] = snapshot.split(separator: "\n").map { $0.components(separatedBy: "|") }
    private static let snapshot = """
    BTC|bitcoin|bitcoins|0.000012895222449
    ETH|ethereum|ethereums|0.0004422763077005
    USDT|tether|tethers|1.0011212558065033
    BNB|bnb|bnbs|0.0014247043738424
    XRP|xrp|xrps|0.7982120051085568
    USDC|usd coin|usd coins|1
    SOL|solana|solanas|0.0104264414555312
    ZEC|zcash|zcashs|0.0007815247547966
    HYPE|hyperliquid|hyperliquids|0.0113765642775882
    DOGE|dogecoin|dogecoins|13.1648235913638757
    USDS|usds|usdss|1.0001000100010001
    LINK|chainlink|chainlinks|0.0845665961945032
    ADA|cardano|cardanos|5.1746442432082794
    XLM|stellar|stellars|5.8716802987510936
    NEAR|near protocol|near protocols|0.225022502250225
    BCH|bitcoin cash|bitcoin cash|0.0035077872877789
    DAI|dai|dais|1.00002860879654
    UNI|uniswap|uniswaps|0.1405441870924219
    LTC|litecoin|litecoins|0.0178265830005705
    USD1|usd1|usd1s|1.0017028949213663
    AVAX|avalanche|avalanches|0.1165772907437631
    SUI|sui|suis|1.1113580795732385
    HBAR|hedera|hederas|13.8542532557495151
    QNT|quant|quants|0.0049773530436514
    PYUSD|paypal usd|paypal usds|1
    TAO|bittensor|bittensors|0.0042038002354128
    SHIB|shiba inu|shiba inus|213219.6162046908315565
    CRO|cronos|cronoss|19.3911188675586581
    ENA|ethena|ethenas|5.2637119696810191
    RLUSD|ripple usd|ripple usds|1
    """
}
