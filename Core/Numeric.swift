import Foundation

enum DecimalParseError: Error { case malformed }

enum DecimalError: Error { case malformed }

extension Decimal {
    init(exact text: String) throws {
        let locale = Locale(identifier: "en_US_POSIX")
        guard let parsed = Decimal(string: text, locale: locale) else {
            throw DecimalError.malformed
        }
        self = parsed
    }
}

enum Numeric {
    static let maximumMagnitude = try! Decimal(exact: "1e127")
    static let minimumMagnitude = try! Decimal(exact: "1e-127")
    static let scientificThreshold = try! Decimal(exact: "1e21")

    static func add(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try check(a + b)
    }

    static func subtract(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try check(a - b)
    }

    static func multiply(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try check(a * b)
    }

    static func divide(_ a: Decimal, by b: Decimal) throws -> Decimal {
        if b == 0 {
            throw Diagnostic.divisionByZero
        }
        if a == 0 {
            return Decimal(0)
        }
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
        guard (-127 ... 127).contains(leadingExponent), let value = parsedDecimal("\(digits)e\(leadingExponent - digits.count + 1)") else {
            throw Diagnostic.outOfRange
        }
        return try check(negative ? -value : value)
    }

    static func parsedDecimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func normalizedParts(of value: Decimal) -> (Decimal, Int) {
        if value.isNaN {
            return (value, 0)
        }
        var mantissa = value
        var exponent = 0
        let negative = mantissa < 0
        if negative {
            mantissa = -mantissa
        }
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

    static func normalizedMantissaDigits(of mantissa: Decimal) -> String {
        mantissa.description.replacingOccurrences(of: ".", with: "")
    }

    static func power(_ base: Decimal, by exponent: Int) throws -> Decimal {
        if base == 0, exponent < 0 {
            throw Diagnostic.divisionByZero
        }
        if exponent < 0 {
            let positive = try power(base, by: -exponent)
            return try divide(Decimal(1), by: positive)
        }
        var result = Decimal(1)
        var factor = base
        var bits = exponent
        while bits > 0 {
            if bits & 1 == 1 {
                result = try multiply(result, factor)
            }
            bits >>= 1
            if bits > 0 {
                factor = try multiply(factor, factor)
            }
        }
        return result
    }

    static func check(_ value: Decimal) throws -> Decimal {
        if value.isNaN {
            throw Diagnostic.outOfRange
        }
        return value
    }

    static func rangeDiagnostic(for value: Decimal) -> Diagnostic? {
        if value == 0 {
            return nil
        }
        let magnitude = value < 0 ? -value : value
        if magnitude.isNaN {
            return .outOfRange
        }
        if magnitude > maximumMagnitude || magnitude < minimumMagnitude {
            return .outOfRange
        }
        return nil
    }

    static let retainedDigits = 34

    static func retain(_ value: Decimal) -> Decimal {
        if value == 0 || value.isNaN {
            return value
        }
        var magnitude = value < 0 ? -value : value
        var exponent = 0
        while magnitude >= 10 {
            magnitude /= 10; exponent += 1
        }
        while magnitude < 1 {
            magnitude *= 10; exponent -= 1
        }
        var mantissa = roundPlain(magnitude, scale: retainedDigits - 1)
        if mantissa >= 10 {
            mantissa /= 10
            exponent += 1
        }
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

    static func roundPlain(_ value: Decimal, scale: Int) -> Decimal {
        var mutable = value
        var result = Decimal()
        NSDecimalRound(&result, &mutable, scale, .plain)
        return result
    }

    static func display(_ value: Decimal, precision: Int, locale: Locale) -> String {
        if value.isNaN {
            return "NaN"
        }
        if value == 0 {
            return "0"
        }
        let negative = value < 0
        var magnitude = value < 0 ? -value : value
        let text: String
        if magnitude >= scientificThreshold {
            var exponent = 0
            while magnitude >= 10 {
                magnitude /= 10; exponent += 1
            }
            var mantissa = roundPlain(magnitude, scale: precision)
            if mantissa >= 10 {
                mantissa /= 10
                exponent += 1
            }
            text = digits(of: mantissa, locale: locale) + "E\(exponent)"
        } else {
            magnitude = roundPlain(magnitude, scale: precision)
            if magnitude == 0 {
                return "0"
            }
            text = grouped(digits(of: magnitude, locale: locale), locale: locale)
        }
        return (negative ? "-" : "") + text
    }

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
    var magnitude: Decimal {
        self < 0 ? -self : self
    }
}
