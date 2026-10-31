import Foundation

/// One immutable rate table, with its own base and fetch instant. An update
/// failure belongs to the service, not to this usable evaluator input.
public struct ExchangeRateSnapshot: Sendable, Equatable, Codable {
    public let base: String
    public let rates: [String: Decimal]
    public let fetchedAt: Date

    public init(base: String, rates: [String: Decimal], fetchedAt: Date) {
        self.base = base.uppercased()
        self.rates = rates
        self.fetchedAt = fetchedAt
    }

    public static let shipped = ExchangeRateSnapshot(base: "USD", rates: FiatCurrencies.shippedRates, fetchedAt: Date(timeIntervalSince1970: 1_793_404_800))

    public func convert(_ value: MonetaryValue, to destination: String) throws -> MonetaryValue {
        let target = destination.uppercased()
        if value.currency == target {
            return value
        }
        func rate(_ code: String) throws -> Decimal {
            if code == base {
                return 1
            }
            guard let rate = rates[code], !rate.isNaN, rate > 0 else {
                throw Diagnostic.exchangeRateUnavailable(currency: code)
            }
            return rate
        }
        let sourceRate = try rate(value.currency)
        let targetRate = try rate(target)
        let amount = try Numeric.divide(Numeric.multiply(value.amount, targetRate), by: sourceRate)
        if let diagnostic = Numeric.rangeDiagnostic(for: amount) {
            throw diagnostic
        }
        return MonetaryValue(amount: Numeric.retain(amount), currency: target)
    }
}
