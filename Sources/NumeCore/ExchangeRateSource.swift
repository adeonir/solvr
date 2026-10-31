import Foundation

public struct ExchangeRateTable: Sendable, Equatable {
    public let base: String
    public let rates: [String: Decimal]

    public init(base: String, rates: [String: Decimal]) {
        self.base = base
        self.rates = rates
    }

    func validate() throws {
        guard !base.isEmpty, base == base.uppercased(), base.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              !rates.isEmpty,
              rates.allSatisfy({ !$0.key.isEmpty && $0.key == $0.key.uppercased() && !$0.value.isNaN && $0.value > 0 }),
              rates[base] == nil || rates[base] == 1
        else { throw ExchangeRateUpdateError.invalidResponse }
    }

    static func decode(base: String, strings: [String: String]) throws -> ExchangeRateTable {
        var rates: [String: Decimal] = [:]
        let pattern = #"^[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#
        for (code, string) in strings {
            guard let match = string.range(of: pattern, options: .regularExpression), match == string.startIndex ..< string.endIndex,
                  let rate = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")), !rate.isNaN, rate > 0
            else { throw ExchangeRateUpdateError.invalidResponse }
            rates[code] = rate
        }
        let table = ExchangeRateTable(base: base, rates: rates)
        try table.validate()
        return table
    }
}

public enum ExchangeRateUpdateError: Error, Sendable, Equatable {
    case invalidResponse
    case httpStatus(Int)
}

public protocol ExchangeRateSource: Sendable {
    func fetch() async throws -> ExchangeRateTable
}

public struct CoinbaseExchangeRateSource: ExchangeRateSource {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    private let transport: Transport

    public init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }) {
        self.transport = transport
    }

    public func fetch() async throws -> ExchangeRateTable {
        let request = URLRequest(url: URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=USD")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (data, status) = try await transport(request)
        guard (200 ..< 300).contains(status) else { throw ExchangeRateUpdateError.httpStatus(status) }
        struct Response: Decodable {
            struct Body: Decodable {
                let currency: String
                let rates: [String: String]
            }

            let data: Body
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try ExchangeRateTable.decode(base: response.data.currency, strings: response.data.rates)
    }
}
