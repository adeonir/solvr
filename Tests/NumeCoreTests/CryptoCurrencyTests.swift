import Foundation
@testable import NumeCore
import Testing

struct CryptoCurrencyTests {
    private func context(_ locale: String = "en_US", cryptoPrecision: Int = 10) -> EvaluationContext {
        var context = EvaluationContext(localeIdentifier: locale, timeZone: TimeZone(secondsFromGMT: 0)!, now: Date(timeIntervalSince1970: 0), displayPrecision: 2)
        context.cryptoPrecision = cryptoPrecision
        context.exchangeRates = ExchangeRateSnapshot(
            base: "USD",
            rates: ["BRL": 5, "EUR": 0.5, "BTC": Decimal(string: "0.00002")!, "ETH": Decimal(string: "0.0005")!],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        return context
    }

    @Test func catalogHoldsThirtyDistinctCodesWithRatesAndNoNameClash() {
        #expect(CryptoCurrencies.entries.count == 30)
        #expect(CryptoCurrencies.codes.count == 30)
        #expect(CryptoCurrencies.codes.isDisjoint(with: Set(FiatCurrencies.entries.map(\.code))))
        #expect(Set(CryptoCurrencies.shippedRates.keys) == CryptoCurrencies.codes)
        #expect(ExchangeRateSnapshot.shipped.rates["BTC"] != nil)
        #expect(Set(FiatCurrencies.names.keys).isDisjoint(with: Set(CryptoCurrencies.names.keys)))
    }

    @Test func symbolsCodesAndNamesReadTheirCryptocurrency() {
        let results = evaluate(sheetText: "₿1\nΞ 2\n3 eth\n1 bitcoin\n2 Bitcoins\n1 Bitcoin Cash\n4 ethereums\n1 BTC", context: context())
        #expect(results.map(\.display) == ["BTC 1", "ETH 2", "ETH 3", "BTC 1", "BTC 2", "BCH 1", "ETH 4", "BTC 1"])
        #expect(results[0].value == .monetary(MonetaryValue(amount: 1, currency: "BTC")))
    }

    @Test func unlistedCryptocurrenciesAreNotRecognized() {
        #expect(evaluate(sheetText: "1 TRX\n1 XMR\n1 ₿₿", context: context()).allSatisfy { $0.diagnostic != nil })
    }

    @Test func codesAndNamesAreReservedInAnyLetterCase() {
        let results = evaluate(sheetText: "btc = 1\nEth = 1\nbitcoin = 1\nbitcoin cash = 2\nshiba inus = 3\nbitcoinz = 4", context: context())
        #expect(results[0].diagnostic?.message == "Reserved name: btc")
        #expect(results[1].diagnostic?.message == "Reserved name: Eth")
        #expect(results[2].diagnostic?.message == "Reserved name: bitcoin")
        #expect(results[3].diagnostic?.message == "Reserved name: bitcoin cash")
        #expect(results[4].diagnostic?.message == "Reserved name: shiba inus")
        #expect(results[5].diagnostic == nil)
        for code in CryptoCurrencies.codes {
            #expect(evaluate(sheetText: "\(code.lowercased()) = 1", context: context())[0].diagnostic?.message == "Reserved name: \(code.lowercased())")
        }
    }

    @Test func resultUsesCodeRegionalFormatAndCryptoPrecision() throws {
        #expect(evaluate(sheetText: "1,5 BTC", context: context("pt_BR"))[0].display == "BTC 1,5000000000")
        #expect(evaluate(sheetText: "1.5 BTC", context: context("en_US"))[0].display == "BTC 1.5000000000")
        #expect(evaluate(sheetText: "1.5 BTC", context: context("en_US", cryptoPrecision: 5))[0].display == "BTC 1.50000")
        #expect(evaluate(sheetText: "1.5 BTC\n1 BTC", context: context("en_US", cryptoPrecision: 15)).map(\.display) == ["BTC 1.500000000000000", "BTC 1"])
        let value = try #require(Decimal(string: "0.123456789012345678"))
        let result = evaluate(sheetText: "0.123456789012345678 BTC", context: context("en_US", cryptoPrecision: 12))[0]
        #expect(result.display == "BTC 0.123456789012")
        #expect(result.value == .monetary(MonetaryValue(amount: value, currency: "BTC")))
    }

    @Test func precisionStaysFromFiveToFifteen() {
        #expect(context(cryptoPrecision: 2).cryptoPrecision == 5)
        #expect(context(cryptoPrecision: 40).cryptoPrecision == 15)
        #expect(EvaluationContext(localeIdentifier: "en_US", timeZone: .gmt, now: Date(), displayPrecision: 2).cryptoPrecision == 10)
        var ctx = context()
        ctx.cryptoPrecision = 99
        #expect(ctx.cryptoPrecision == 15)
    }

    @Test func fiatPrecisionDoesNotAffectCryptoAndTheReverse() {
        var ctx = context(cryptoPrecision: 6)
        ctx.displayPrecision = 3
        #expect(evaluate(sheetText: "1.23456789 BTC\n1.23456789 USD", context: ctx).map(\.display) == ["BTC 1.234568", "$ 1.235"])
    }

    @Test func convertsBetweenCryptocurrenciesAndFiat() {
        let results = evaluate(sheetText: "1 BTC in ETH\n1 ETH in bitcoin\n1 BTC in USD\n$50000 in BTC\n1000 BRL in btc\n1 BTC in EUR\n2 + 2", context: context())
        #expect(results[0].display == "ETH 25")
        #expect(results[1].display == "BTC 0.0400000000")
        #expect(results[2].display == "$ 50,000")
        #expect(results[3].display == "BTC 1")
        #expect(results[4].display == "BTC 0.0040000000")
        #expect(results[5].display == "€ 25,000")
        #expect(results[6].display == "4")
    }

    @Test func missingCryptoRateNamesTheCauseAndKeepsOtherLines() {
        let results = evaluate(sheetText: "1 BTC in LTC\n1 BTC in USD", context: context())
        #expect(results[0].diagnostic?.message == "Exchange rate unavailable: LTC")
        #expect(results[1].display == "$ 50,000")
    }

    @Test func convertedCryptoKeepsFullDecimalValue() throws {
        let result = evaluate(sheetText: "$1 in BTC", context: context("en_US", cryptoPrecision: 5))[0]
        #expect(result.display == "BTC 0.00002")
        #expect(try result.value == .monetary(MonetaryValue(amount: #require(Decimal(string: "0.00002")), currency: "BTC")))
    }

    @Test func variableBindingKeepsCryptoIdentity() {
        let results = evaluate(sheetText: "coin = 2 ETH\ncoin in BTC", context: context())
        #expect(results.map(\.display) == ["ETH 2", "BTC 0.0800000000"])
    }

    @Test func sourceDecodesCryptoRatesAndShippedRatesCoverEveryEntry() async throws {
        let source = CoinbaseExchangeRateSource { _ in
            (Data(#"{"data":{"currency":"USD","rates":{"BTC":"0.00002","ETH":"0.0005","BRL":"5"}}}"#.utf8), 200)
        }
        let table = try await source.fetch()
        #expect(table.rates["BTC"] == Decimal(string: "0.00002"))
        let snapshot = ExchangeRateSnapshot(base: table.base, rates: table.rates, fetchedAt: Date(timeIntervalSince1970: 1))
        #expect(try snapshot.convert(MonetaryValue(amount: 1, currency: "BTC"), to: "BRL").amount == 250_000)
    }
}
