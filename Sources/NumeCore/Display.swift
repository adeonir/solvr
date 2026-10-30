// Display (ADK-222): regional reading and representation of numbers.
// Base literals (`0b`, `0o`, `0x`) share the plain decimal value with
// every other number, and `in sci`, `in bin`, `in oct`, and `in hex`
// change only the representation shown beside an expression — never the
// numeric value itself.

import Foundation

enum Display {
    /// What a value converts into through `in <representation>`.
    enum Representation: Sendable {
        /// Scientific notation, e.g. `5,3E3` with Brazilian formatting.
        case sci
        /// Base two with the `0b` prefix.
        case bin
        /// Base eight with the `0o` prefix.
        case oct
        /// Base sixteen with the `0x` prefix.
        case hex

        var base: Int? {
            switch self {
            case .sci: return nil
            case .bin: return 2
            case .oct: return 8
            case .hex: return 16
            }
        }

        /// The representation keyword that follows `in`.
        init?(keyword: String) {
            switch keyword {
            case "sci": self = .sci
            case "bin": self = .bin
            case "oct": self = .oct
            case "hex": self = .hex
            default: return nil
            }
        }
    }

    // MARK: Base-literal reading

    /// Read the base literal starting at `start`: a `0` with the `b`, `o`,
    /// or `x` prefix followed by digits of that base; nil when the prefix
    /// or the digits do not form one. The literal's value is its digit
    /// value in the base — `0b110111011`, `0x1bb`, and `443` share it.
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

    /// The digit value of a character in the base's alphabet: digits up to
    /// the letters `a` through `f` in hexadecimal, uppercase or lowercase.
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

    // MARK: Applying a representation

    /// A value converts into a base representation only when it is an
    /// integer; scientific notation applies to every value.
    static func validate(_ value: Decimal, as representation: Representation) throws {
        guard representation.base != nil else { return }
        if value.isNaN { throw Diagnostic.outOfRange }
        guard value == Numeric.roundPlain(value, scale: 0) else {
            throw Diagnostic.syntax
        }
    }

    /// The representation of a converted value: locale separators and the
    /// displayed decimal places apply to the scientific mantissa; a base
    /// representation holds its integer digits with the language prefix.
    static func format(
        _ value: Decimal, as representation: Representation,
        precision: Int, locale: Locale
    ) -> String {
        switch representation {
        case .sci:
            return scientific(value, precision: precision, locale: locale)
        case .bin, .oct, .hex:
            guard let base = representation.base else { return "" }
            let sign = value < 0 ? "-" : ""
            let magnitude = value < 0 ? -value : value
            guard let integer = integerDigits(of: magnitude) else { return "" }
            let prefix = representation == .bin ? "0b" : representation == .oct ? "0o" : "0x"
            return sign + prefix + baseDigits(integer, base: base)
        }
    }

    /// Scientific notation with the displayed decimal places on the
    /// mantissa, the locale decimal separator, and trailing zeros
    /// trimmed: `5 300 in sci` at two displayed places, Brazilian
    /// formatting, is `5,3E3`.
    static func scientific(
        _ value: Decimal, precision: Int, locale: Locale
    ) -> String {
        if value == 0 { return "0" }
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

    // MARK: Helpers

    /// Full-precision digits of a decimal, decimal point at the locale
    /// separator, trailing zeros trimmed. Foundation numbers format
    /// through double precision, so the digits come from the Decimal
    /// description itself.
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

    /// The plain decimal digit string of an integer of any supported
    /// magnitude, rebuilt from its normalized mantissa and exponent:
    /// trailing zeros beyond the integer's last place belong only to the
    /// stored scale and drop, so `443.00` and `443` hold digits alike.
    private static func integerDigits(of magnitude: Decimal) -> String? {
        if magnitude == 0 { return "0" }
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

    /// The digit string of a decimal integer re-expressed in the base,
    /// most significant digit last in the output, by long division over
    /// the digits with the remainder at each step.
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
