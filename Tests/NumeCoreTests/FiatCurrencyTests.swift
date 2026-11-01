import Foundation
@testable import NumeCore
import Testing

struct FiatCurrencyTests {
    @Test func yenFractionExampleRoundsOnlyDisplayInAnySystemRegion() throws {
        for locale in ["en_US", "pt_BR", "de_DE"] {
            let result = evaluate(sheetText: "10,5 JPY", context: context(locale))[0]
            #expect(result.display == "¥ 11")
            #expect(try result.value == .monetary(MonetaryValue(amount: #require(Decimal(string: "10.5")), currency: "JPY")))
        }
    }

    @Test func destinationCurrenciesUseTheirOwnFormatsBeyondTheFiveSymbols() {
        for locale in ["en_US", "pt_BR"] {
            let results = evaluate(sheetText: "10,50 DKK\n10.50 AUD\n10,50 PLN", context: context(locale))
            #expect(results.map(\.display) == ["DKK 10,50", "AUD 10.50", "PLN 10,50"])
        }
        #expect(FiatCurrencies.entries.count == 151)
        #expect(Set(FiatCurrencies.entries.map(\.code)).count == 151)
    }

    private func context(_ locale: String = "en_US") -> EvaluationContext {
        EvaluationContext(localeIdentifier: locale, timeZone: TimeZone(secondsFromGMT: 0)!, now: Date(timeIntervalSince1970: 0), displayPrecision: 2)
    }

    @Test func dollarSymbolAlwaysReadsUSD() {
        for locale in ["en_US", "pt_BR", "de_DE"] {
            let result = evaluate(sheetText: "$99.99", context: context(locale))[0]
            #expect(result.display == "$ 99.99")
            #expect(result.diagnostic == nil)
        }
    }

    @Test func amountsReadTheirCurrencySeparatorsAndSymbols() {
        for locale in ["en_US", "pt_BR"] {
            let results = evaluate(sheetText: "10,50 BRL\n10.50 USD\nR$ 10,50\n£ 10.50\n¥ 10\n€ 10", context: context(locale))
            #expect(results.map(\.display) == ["R$ 10,50", "$ 10.50", "R$ 10,50", "£ 10.50", "¥ 10", "€ 10"])
            #expect(results.allSatisfy { $0.diagnostic == nil })
        }
    }

    @Test func namesAndCodesAreCaseInsensitiveAndReserved() {
        let results = evaluate(sheetText: "10 dollars\n5 euros\n1 australian dollar\n2 Australian Dollars\n10 uSd\nuSd = 2\naustralian dollar = 3\n10 XYZ\n2 + 2", context: context())
        #expect(Array(results.prefix(5)).map(\.display) == ["$ 10", "€ 5", "AUD 1", "AUD 2", "$ 10"])
        #expect(results[5].diagnostic?.message == "Reserved name: uSd")
        #expect(results[6].diagnostic?.message == "Reserved name: australian dollar")
        #expect(results[7].diagnostic == .syntax)
        #expect(results[8].display == "4")
    }

    @Test func fixedFiatCatalogAndLanguageNamesAreReserved() {
        // Intersection of Coinbase currencies and USD exchange rates, 2026-10-31.
        let codes = "AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BTN BWP BYN BZD CAD CDF CHF CLP CNY COP CRC CUP CVE CZK DJF DKK DOP DZD EGP ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ GYD HKD HNL HRK HTG HUF IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR KMF KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SOS SRD SSP SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD UYU UZS VES VND VUV WST XAF XCD XOF XPF YER ZAR ZMW".components(separatedBy: " ")
        for code in codes {
            let results = evaluate(sheetText: "1 \(code.lowercased())\n\(code.lowercased()) = 2", context: context())
            #expect(results[0].value == .monetary(MonetaryValue(amount: 1, currency: code)))
            #expect(results[1].diagnostic?.message == "Reserved name: \(code.lowercased())")
        }
        for name in ["to", "at", "until", "of", "off", "as", "timespan", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"] {
            #expect(evaluate(sheetText: "\(name) = 2", context: context())[0].diagnostic?.message == "Reserved name: \(name)")
        }
    }

    @Test func conversionUsesTheProvidedTableWhateverItsBase() {
        var ctx = context()
        ctx.exchangeRates = ExchangeRateSnapshot(base: "EUR", rates: ["USD": 2, "BRL": 10, "EUR": 1], fetchedAt: Date(timeIntervalSince1970: 123))
        let results = evaluate(sheetText: "10 USD in BRL\n10 brl in usd\n10 dollars in euros\n10 USD in australian dollars\n2 + 2", context: ctx)
        #expect(results[0].value == .monetary(MonetaryValue(amount: 50, currency: "BRL")))
        #expect(results[0].display == "R$ 50")
        #expect(results[1].display == "$ 2")
        #expect(results[2].display == "€ 5")
        #expect(results[3].diagnostic?.message == "Exchange rate unavailable: AUD")
        #expect(results[4].display == "4")
    }

    @Test func roundingAndRegionalFormattingAffectOnlyDisplay() throws {
        let yen = evaluate(sheetText: "10,5 JPY", context: context("pt_BR"))[0]
        #expect(try yen.value == .monetary(MonetaryValue(amount: #require(Decimal(string: "10.5")), currency: "JPY")))
        #expect(yen.display == "¥ 11")
        #expect(evaluate(sheetText: "1,5 EUR", context: context("pt_BR"))[0].display == "€ 1,50")
        #expect(evaluate(sheetText: "1.5 EUR", context: context("en_US"))[0].display == "€ 1.50")
        var ctx = context()
        ctx.displayPrecision = 3
        let result = evaluate(sheetText: "$1.23456\n$10", context: ctx)
        #expect(result[0].display == "$ 1.235")
        #expect(try result[0].value == .monetary(MonetaryValue(amount: #require(Decimal(string: "1.23456")), currency: "USD")))
        #expect(result[1].display == "$ 10")
    }
}
