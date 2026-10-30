// Numeric core (ADK-221): Foundation Decimal arithmetic with magnitude
// checks (ADR-006) and 34-significant-digit retention. Values stay
// independent of their display representation.

import Foundation

enum DecimalParseError: Error { case malformed }

enum DecimalError: Error { case malformed }

extension Decimal {
    /// Build a Decimal by parsing a text exponent form.
    init(exact text: String) throws {
        let locale = Locale(identifier: "en_US_POSIX")
        guard let parsed = Decimal(string: text, locale: locale) else {
            throw DecimalError.malformed
        }
        self = parsed
    }
}

/// Numeric operations: on failure they throw the diagnostic the expression
/// shows in place of its result.
enum Numeric {
    /// The supported magnitude range is zero plus 10^-127..10^127, either
    /// sign (ADR-006).
    static let maximumMagnitude = try! Decimal(exact: "1e127")
    static let minimumMagnitude = try! Decimal(exact: "1e-127")
    /// The smallest absolute magnitude below which nothing displays or
    /// evaluates but zero, in the sense of the plain exponent bound.
    static let scientificThreshold = try! Decimal(exact: "1e21")

    // MARK: Arithmetic; each result is checked against the magnitude range.

    static func add(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try check(a + b)
    }

    static func subtract(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try check(a - b)
    }

    static func multiply(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try check(a * b)
    }

    /// The quotient of two values with the mantissas divided separately:
    /// Foundation division underflows where the quotient's own exponent
    /// sinks below about -90, while the result is still representable — so
    /// the mantissas normalize apart, the small mantissa quotient divides
    /// safely near exponent zero, and the exponent reassembles through an
    /// exact string form that any representable decimal accepts (ADR-006).
    static func divide(_ a: Decimal, by b: Decimal) throws -> Decimal {
        if b == 0 { throw Diagnostic.divisionByZero }
        if a == 0 { return Decimal(0) }
        // The mantissas normalize apart over magnitudes: the remainder sign
        // is applied after reassembly, or the sign becomes part of the
        // digit string and counts as an exponent place (ADK-227).
        let negative = (a < 0) != (b < 0)
        let (mantissaA, exponentA) = normalizedParts(of: a < 0 ? -a : a)
        let (mantissaB, exponentB) = normalizedParts(of: b < 0 ? -b : b)
        let quotient = try check(mantissaA / mantissaB)
        let (mantissaQ, exponentQ) = normalizedParts(of: quotient)
        var digits = normalizedMantissaDigits(of: mantissaQ)
        var stripped = 0
        while digits.count > 1, digits.hasSuffix("0") {
            digits.removeLast()
            stripped += 1
        }
        let leadingExponent = exponentA - exponentB + exponentQ + stripped
        guard (-127 ... 127).contains(leadingExponent) else { throw Diagnostic.outOfRange }
        guard let value = parsedDecimal("\(digits)e\(leadingExponent - digits.count + 1)") else {
            throw Diagnostic.outOfRange
        }
        return try check(negative ? -value : value)
    }

    /// Parse a decimal text with `en_US_POSIX`, the form every supported
    /// decimal accepts.
    static func parsedDecimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Split a value into its mantissa in [1, 10) and its exponent, both
    /// derived without entering the underflowing region: magnitudes above
    /// one lose digits through divisions that stay inside the representable
    /// range and magnitudes below one climb through safe multiplications.
    /// The magnitude normalizes first: a negative mantissa never leaves
    /// the `mantissa < 1` climb until it reaches NaN (ADK-227).
    static func normalizedParts(of value: Decimal) -> (Decimal, Int) {
        if value.isNaN { return (value, 0) }
        var mantissa = value
        var exponent = 0
        let negative = mantissa < 0
        if negative { mantissa = -mantissa }
        while mantissa >= 10 {
            mantissa /= 10
            exponent += 1
        }
        while mantissa < 1 {
            mantissa *= 10
            exponent -= 1
        }
        return (negative ? -mantissa : mantissa, exponent)
    }

    /// The full-precision digit string of a normalized mantissa, decimal
    /// point removed: `3.333…` yields `333…`. The description carries every
    /// stored digit; `NSDecimalNumber` string formatting truncates instead.
    static func normalizedMantissaDigits(of mantissa: Decimal) -> String {
        mantissa.description.replacingOccurrences(of: ".", with: "")
    }

    static func power(_ base: Decimal, by exponent: Int) throws -> Decimal {
        if base == 0 && exponent < 0 { throw Diagnostic.divisionByZero }
        if exponent < 0 {
            // One final inversion keeps the wide negative exponents inside
            // the supported range; iterating divisions would underflow
            // while the needed result is still representable.
            let positive = try power(base, by: -exponent)
            return try divide(Decimal(1), by: positive)
        }
        var result = Decimal(1)
        var factor = base
        var bits = exponent
        while bits > 0 {
            if bits & 1 == 1 { result = try multiply(result, factor) }
            bits >>= 1
            if bits > 0 { factor = try multiply(factor, factor) }
        }
        return result
    }

    /// Foundation reports calculation overflow or underflow as NaN; any NaN
    /// lies beyond the supported range (ADR-006).
    static func check(_ value: Decimal) throws -> Decimal {
        if value.isNaN { throw Diagnostic.outOfRange }
        return value
    }

    /// Diagnose a finished literal or value: zero passes; anything outside
    /// 10^-127..10^127 — including NaN — is a numeric-range error.
    static func rangeDiagnostic(for value: Decimal) -> Diagnostic? {
        if value == 0 { return nil }
        let magnitude = value < 0 ? -value : value
        if magnitude.isNaN { return .outOfRange }
        if magnitude > maximumMagnitude || magnitude < minimumMagnitude {
            return .outOfRange
        }
        return nil
    }

    // MARK: 34-significant-digit retention

    static let retainedDigits = 34

    /// Round the value to 34 significant decimal digits, exact ties away
    /// from zero (ADR-006). The magnitude normalizes next to 10^e with
    /// 1 <= mantissa < 10, rounds with one integer digit plus the remaining
    /// 33 decimals, and goes back through the exponent.
    static func retain(_ value: Decimal) -> Decimal {
        if value == 0 || value.isNaN { return value }
        var magnitude = value < 0 ? -value : value
        var exponent = 0
        while magnitude >= 10 { magnitude /= 10; exponent += 1 }
        while magnitude < 1 { magnitude *= 10; exponent -= 1 }
        var mantissa = roundPlain(magnitude, scale: retainedDigits - 1)
        if mantissa >= 10 {
            mantissa /= 10
            exponent += 1
        }
        // Reassemble through the mantissa digits: the divisions back down
        // the exponent would run Foundation division into its underflow
        // region below about 10^-90 (ADR-006).
        var digits = normalizedMantissaDigits(of: mantissa)
        var stripped = 0
        while digits.count > 1, digits.hasSuffix("0") {
            digits.removeLast()
            stripped += 1
        }
        guard let rebuilt = parsedDecimal(
            "\(digits)e\(exponent + stripped - digits.count + 1)"
        ) else {
            return value
        }
        return value < 0 ? -rebuilt : rebuilt
    }

    /// NSDecimalRound with the plain rounding mode: exact ties away from zero.
    static func roundPlain(_ value: Decimal, scale: Int) -> Decimal {
        var mutable = value
        var result = Decimal()
        NSDecimalRound(&result, &mutable, scale, .plain)
        return result
    }

    // MARK: Display representation (strictly separate from the value)

    /// The displayed representation: locale separators, the configured
    /// displayed decimal places with trailing zeros trimmed, a grouped
    /// integer part, and scientific notation from magnitude 10^21 up with
    /// the displayed places applied to the mantissa. Foundation numbers
    /// format through double precision, so the digits come from the Decimal
    /// description itself.
    static func display(_ value: Decimal, precision: Int, locale: Locale) -> String {
        if value.isNaN { return "NaN" }
        if value == 0 { return "0" }
        let negative = value < 0
        var magnitude = value < 0 ? -value : value
        let text: String
        if magnitude >= scientificThreshold {
            var exponent = 0
            while magnitude >= 10 { magnitude /= 10; exponent += 1 }
            var mantissa = roundPlain(magnitude, scale: precision)
            if mantissa >= 10 {
                mantissa /= 10
                exponent += 1
            }
            text = digits(of: mantissa, locale: locale) + "E\(exponent)"
        } else {
            magnitude = roundPlain(magnitude, scale: precision)
            if magnitude == 0 { return "0" }
            text = grouped(digits(of: magnitude, locale: locale), locale: locale)
        }
        return (negative ? "-" : "") + text
    }

    /// Full-precision digits of a decimal, with the decimal point at the
    /// locale's separator and trailing zeros trimmed.
    private static func digits(of value: Decimal, locale: Locale) -> String {
        let decimalSeparator = locale.decimalSeparator ?? "."
        var result = value.description
        if result.contains(".") {
            while result.last == "0" || result.last == "." {
                result = String(result.dropLast())
            }
        }
        return result.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// Insert the locale grouping separator every three digits of the
    /// integer part.
    private static func grouped(_ digits: String, locale: Locale) -> String {
        let groupingSeparator = locale.groupingSeparator ?? ","
        let integerPart: String
        let rest: String
        if let point = digits.firstIndex(where: { !$0.isNumber }) {
            integerPart = String(digits[..<point])
            rest = String(digits[point...])
        } else {
            integerPart = digits
            rest = ""
        }
        var output = ""
        for (position, digit) in integerPart.enumerated() {
            if position > 0, position < integerPart.count, (integerPart.count - position) % 3 == 0 {
                output.append(Character(groupingSeparator))
            }
            output.append(digit)
        }
        return output + rest
    }
}

private extension Decimal {
    var magnitude: Decimal { self < 0 ? -self : self }
}
