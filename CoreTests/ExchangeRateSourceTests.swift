import Foundation
#if canImport(Core)
@testable import Core
#else
#endif
import Testing

struct ExchangeRateSourceTests {
    @Test func publicEndpointUsesNoKeyAndPreservesDecimalStrings() async throws {
        let source = CoinbaseExchangeRateSource { request in
            #expect(request.url?.absoluteString == "https://api.coinbase.com/v2/exchange-rates?currency=USD")
            #expect(request.httpMethod == "GET")
            #expect(request.allHTTPHeaderFields?.isEmpty != false)
            return (Data(#"{"data":{"currency":"EUR","rates":{"EUR":"1","USD":"2","BRL":"10","BTC":"0.00001234567890123456789012345678901"}}}"#.utf8), 200)
        }
        let table = try await source.fetch()
        #expect(table.base == "EUR")
        #expect(table.rates["BRL"] == 10)
        #expect(table.rates["BTC"] == Decimal(string: "0.00001234567890123456789012345678901"))
    }

    @Test(arguments: ["", "not json", #"{"data":{"currency":"USD","rates":{}}}"#, #"{"data":{"currency":"USD","rates":{"BRL":"0"}}}"#, #"{"data":{"currency":"USD","rates":{"BRL":"-1"}}}"#, #"{"data":{"currency":"USD","rates":{"BRL":"5junk"}}}"#, #"{"data":{"currency":"USD","rates":{"BRL":5}}}"#, #"{"data":{"currency":"USD","rates":{"USD":"2"}}}"#])
    func invalidTablesFailWithoutBecomingUsableRates(_ body: String) async {
        let source = CoinbaseExchangeRateSource { _ in (Data(body.utf8), 200) }
        await #expect(throws: (any Error).self) { try await source.fetch() }
    }

    @Test func httpFailureIsNotAUsableTable() async {
        let source = CoinbaseExchangeRateSource { _ in
            (Data(#"{"data":{"currency":"USD","rates":{"BRL":"5"}}}"#.utf8), 503)
        }
        await #expect(throws: ExchangeRateUpdateError.httpStatus(503)) { try await source.fetch() }
    }
}
