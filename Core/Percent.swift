import Foundation

enum Percent {
    static func share(_ percent: Decimal, of base: Decimal) throws -> Decimal {
        try Numeric.divide(Numeric.multiply(percent, base), by: 100)
    }

    static func off(_ percent: Decimal, of base: Decimal) throws -> Decimal {
        try Numeric.subtract(base, share(percent, of: base))
    }

    static func portion(_ percent: Decimal) throws -> Decimal {
        try Numeric.divide(percent, by: 100)
    }
}
