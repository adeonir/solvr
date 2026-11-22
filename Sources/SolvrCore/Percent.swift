// Percentage shares and discounts over numeric amounts — `N% of M`,
// `N% off M`, and the portion a bare `%` contributes in `X - N%`. Currency
// parsing and formatting stay out of scope.

import Foundation

enum Percent {
    /// The share of the base that `N` percent names: `52% of 900` is 468.
    static func share(_ percent: Decimal, of base: Decimal) throws -> Decimal {
        try Numeric.divide(Numeric.multiply(percent, base), by: 100)
    }

    /// The base with its share of `N` percent taken off: `20% off 80` is 64.
    static func off(_ percent: Decimal, of base: Decimal) throws -> Decimal {
        try Numeric.subtract(base, share(percent, of: base))
    }

    /// The fraction `N/100` that a bare `N%` stands for in `X - N%`:
    /// `10 - 40%` takes four tenths off ten.
    static func portion(_ percent: Decimal) throws -> Decimal {
        try Numeric.divide(percent, by: 100)
    }
}
