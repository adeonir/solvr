import Foundation

enum Display {
    enum Representation: Sendable {
        case sci
        case bin
        case oct
        case hex
        case percent

        var base: Int? {
            switch self {
            case .sci, .percent: nil
            case .bin: 2
            case .oct: 8
            case .hex: 16
            }
        }

        init?(keyword: String) {
            switch keyword {
            case "sci": self = .sci
            case "bin": self = .bin
            case "oct": self = .oct
            case "hex": self = .hex
            case "percent": self = .percent
            default: return nil
            }
        }
    }

    static func scanBaseLiteral(
        at start: String.Index, in line: String
    ) -> (value: Decimal, end: String.Index)? {
        guard line[start] == "0" else { return nil }
        let afterZero = line.index(after: start)
        guard afterZero < line.endIndex else { return nil }
        let base: Int
        switch line[afterZero] {
        case "b": base = 2
        case "o": base = 8
        case "x": base = 16
        default: return nil
        }
        var index = line.index(after: afterZero)
        var value = Decimal(0)
        var readAnyDigit = false
        while index < line.endIndex, let digit = baseDigitValue(line[index], in: base) {
            value = value * Decimal(base) + Decimal(digit)
            readAnyDigit = true
            index = line.index(after: index)
        }
        guard readAnyDigit else { return nil }
        return (value, index)
    }

    private static func baseDigitValue(_ character: Character, in base: Int) -> Int? {
        guard let ascii = character.asciiValue else { return nil }
        let digit: Int
        switch ascii {
        case 0x30 ... 0x39: digit = Int(ascii - 0x30)
        case 0x61 ... 0x66: digit = Int(ascii - 0x61) + 10
        case 0x41 ... 0x46: digit = Int(ascii - 0x41) + 10
        default: return nil
        }
        return digit < base ? digit : nil
    }

    static func validate(_ value: Decimal, as representation: Representation) throws {
        guard representation.base != nil else { return }
        if value.isNaN {
            throw Diagnostic.outOfRange
        }
        guard value == Numeric.roundPlain(value, scale: 0) else {
            throw Diagnostic.syntax
        }
    }

    static func format(
        _ value: Decimal, as representation: Representation,
        precision: Int, locale: Locale
    ) -> String {
        switch representation {
        case .sci:
            return scientific(value, precision: precision, locale: locale)
        case .percent:
            let scaled = value * 100
            guard !scaled.isNaN else { return "" }
            return digits(of: Numeric.roundPlain(scaled, scale: precision), locale: locale) + "%"
        case .bin, .oct, .hex:
            guard let base = representation.base else { return "" }
            let sign = value < 0 ? "-" : ""
            let magnitude = value < 0 ? -value : value
            guard let integer = integerDigits(of: magnitude) else { return "" }
            let prefix = representation == .bin ? "0b" : representation == .oct ? "0o" : "0x"
            return sign + prefix + baseDigits(integer, base: base)
        }
    }

    static func scientific(
        _ value: Decimal, precision: Int, locale: Locale
    ) -> String {
        if value == 0 {
            return "0"
        }
        let negative = value < 0
        var magnitude = negative ? -value : value
        var exponent = 0
        while magnitude >= 10 {
            magnitude /= 10
            exponent += 1
        }
        while magnitude < 1 {
            magnitude *= 10
            exponent -= 1
        }
        var mantissa = Numeric.roundPlain(magnitude, scale: precision)
        if mantissa >= 10 {
            mantissa /= 10
            exponent += 1
        }
        return (negative ? "-" : "") + digits(of: mantissa, locale: locale) + "E\(exponent)"
    }

    private static func digits(of value: Decimal, locale: Locale) -> String {
        let decimalSeparator = locale.decimalSeparator ?? "."
        var digits = value.description
        if digits.contains(".") {
            while digits.last == "0" || digits.last == "." {
                digits.removeLast()
            }
        }
        return digits.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    private static func integerDigits(of magnitude: Decimal) -> String? {
        if magnitude == 0 {
            return "0"
        }
        guard !magnitude.isNaN,
              magnitude == Numeric.roundPlain(magnitude, scale: 0)
        else { return nil }
        let (mantissa, exponent) = Numeric.normalizedParts(of: magnitude)
        var digits = Numeric.normalizedMantissaDigits(of: mantissa)
        while digits.count - 1 > exponent, digits.hasSuffix("0") {
            digits.removeLast()
        }
        guard digits.count - 1 <= exponent else { return nil }
        return digits + String(repeating: "0", count: exponent - (digits.count - 1))
    }

    private static func baseDigits(_ integer: String, base: Int) -> String {
        let alphabet = Array("0123456789abcdef")
        var digits = integer.map { $0.wholeNumberValue! }
        var output = ""
        while !(digits.count == 1 && digits[0] == 0) {
            var quotient: [Int] = []
            var remainder = 0
            for digit in digits {
                let part = remainder * 10 + digit
                quotient.append(part / base)
                remainder = part % base
            }
            digits = quotient
            while digits.count > 1, digits.first == 0 {
                digits.removeFirst()
            }
            output = String(alphabet[remainder]) + output
        }
        return output.isEmpty ? "0" : output
    }
}
