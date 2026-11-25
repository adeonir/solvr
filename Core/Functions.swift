import Foundation

enum Functions {
    private static let pi = VariableTable.Constants.values["pi"]!
    private static let naturalLog2 = try? Decimal(
        exact: "0.69314718055994530941723212145817656808"
    )
    private static let naturalLog10 = try? Decimal(
        exact: "2.30258509299404568401799145468436420760"
    )
    private static let seriesCutoff = try! Decimal(exact: "1e-46")
    private static let rootCutoff = try! Decimal(exact: "1e-36")

    static func apply(name: String, arguments: [Decimal]) throws -> Decimal {
        switch name {
        case "min": return try minimum(arguments)
        case "max": return try maximum(arguments, named: "max")
        case "sqrt": return try arityOne(arguments, named: "sqrt") { try sqrt($0) }
        case "fact": return try arityOne(arguments, named: "fact") { try factorial($0) }
        case "sin": return try arityOne(arguments, named: "sin") { try sine(degrees: $0) }
        case "round": return try arityOne(arguments, named: "round") {
                Numeric.roundPlain($0, scale: 0)
            }
        case "log":
            guard (1 ... 2).contains(arguments.count) else {
                throw Diagnostic.argumentCount(
                    function: "log", requirement: "1 or 2 arguments"
                )
            }
            return try logarithm(
                arguments[0], base: arguments.count == 2 ? arguments[1] : Decimal(10)
            )
        default:
            throw Diagnostic.syntax
        }
    }

    private static func arityOne(
        _ arguments: [Decimal], named function: String,
        _ body: (Decimal) throws -> Decimal
    ) throws -> Decimal {
        guard arguments.count == 1 else {
            throw Diagnostic.argumentCount(function: function, requirement: "1 argument")
        }
        return try body(arguments[0])
    }

    static func minimum(_ arguments: [Decimal]) throws -> Decimal {
        try extremum(arguments, named: "min", keep: { $0 < $1 })
    }

    static func maximum(_ arguments: [Decimal], named function: String = "max") throws -> Decimal {
        try extremum(arguments, named: function, keep: { $0 > $1 })
    }

    private static func extremum(
        _ arguments: [Decimal], named function: String,
        keep: (Decimal, Decimal) -> Bool
    ) throws -> Decimal {
        guard arguments.count >= 2 else {
            throw Diagnostic.argumentCount(
                function: function, requirement: "at least 2 arguments"
            )
        }
        var result = arguments[0]
        for argument in arguments.dropFirst() where keep(argument, result) {
            result = argument
        }
        return result
    }

    static func sqrt(_ x: Decimal) throws -> Decimal {
        if x.isNaN {
            throw Diagnostic.outOfRange
        }
        if x < 0 {
            throw Diagnostic.notARealNumber
        }
        if x == 0 {
            return Decimal(0)
        }
        let magnitude = x < 0 ? -x : x
        let (mantissa, exponent) = Numeric.normalizedParts(of: magnitude)
        var split = exponent.quotientAndRemainder(dividingBy: 2)
        if split.remainder < 0 {
            split.quotient -= 1
            split.remainder += 2
        }
        let decade = try Numeric.power(Decimal(10), by: split.quotient)
        let seed = split.remainder == 0 ? Decimal(2) : Decimal(5)
        var guess = try Numeric.multiply(seed, decade)
        for iteration in 1 ... 40 {
            let quotient = try Numeric.check(magnitude / guess)
            let previous = guess
            guess = try Numeric.check((guess + quotient) / 2)
            let delta = guess < previous ? previous - guess : guess - previous
            if iteration > 6, delta <= guess * rootCutoff {
                break
            }
        }
        return guess
    }

    static func factorial(_ x: Decimal) throws -> Decimal {
        if x.isNaN {
            throw Diagnostic.outOfRange
        }
        guard x >= 0, x == Numeric.roundPlain(x, scale: 0) else {
            throw Diagnostic.syntax
        }
        if x > 1_000_000 {
            throw Diagnostic.outOfRange
        }
        var product = Decimal(1)
        var step = Decimal(1)
        while step < x {
            step += 1
            product = try Numeric.multiply(product, step)
        }
        return product
    }

    static func sine(degrees: Decimal) throws -> Decimal {
        if degrees.isNaN {
            throw Diagnostic.outOfRange
        }
        let negative = degrees < 0
        var magnitude = negative ? -degrees : degrees
        if magnitude > 360 {
            var turns = magnitude / 360
            var floored = Decimal()
            var mutable = turns
            NSDecimalRound(&floored, &mutable, 0, .down)
            let turn = Decimal(360)
            while floored * turn > magnitude {
                floored -= 1
            }
            while (floored + 1) * turn <= magnitude {
                floored += 1
            }
            magnitude -= floored * turn
        }
        let radians = try Numeric.check(magnitude * pi / 180)
        let value = try sineSeries(radians)
        return negative ? -value : value
    }

    private static func sineSeries(_ radians: Decimal) throws -> Decimal {
        let squared = radians * radians
        var term = radians
        var sum = radians
        for index in 1 ... 200 {
            let denominator = Decimal(2 * index) * Decimal(2 * index + 1)
            term = try Numeric.check(-term * squared / denominator)
            let magnitude = term < 0 ? -term : term
            if magnitude < seriesCutoff {
                break
            }
            sum = try Numeric.check(sum + term)
        }
        return sum
    }

    static func logarithm(_ x: Decimal, base: Decimal) throws -> Decimal {
        if x.isNaN || base.isNaN {
            throw Diagnostic.outOfRange
        }
        guard x > 0, base > 0 else { throw Diagnostic.notARealNumber }
        return try Numeric.divide(naturalLog(x), by: naturalLog(base))
    }

    static func naturalLog(_ x: Decimal) throws -> Decimal {
        guard x > 0 else { throw Diagnostic.notARealNumber }
        let (mantissa, exponent) = Numeric.normalizedParts(of: x)
        var scaled = mantissa
        var halves = 0
        while scaled >= 2 {
            scaled = try Numeric.check(scaled / 2)
            halves += 1
        }
        let ratio = try Numeric.check((scaled - 1) / (scaled + 1))
        var term = ratio
        var sum = ratio
        let squared = ratio * ratio
        for index in 1 ... 100 {
            term = try Numeric.check(term * squared / Decimal(2 * index + 1))
            if term < seriesCutoff {
                break
            }
            sum = try Numeric.check(sum + term)
        }
        var result = try Numeric.check(sum * 2)
        if halves != 0 {
            result = try Numeric.check(result + Decimal(halves) * naturalLog2!)
        }
        if exponent != 0 {
            result = try Numeric.check(result + Decimal(exponent) * naturalLog10!)
        }
        return result
    }

    static func bitwiseAnd(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try combining(a, b, bit: { left, right in left == 1 && right == 1 ? 1 : 0 },
                      negative: { negativeA, negativeB in negativeA && negativeB })
    }

    static func bitwiseOr(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        try combining(a, b, bit: { left, right in left == 1 || right == 1 ? 1 : 0 },
                      negative: { negativeA, negativeB in negativeA || negativeB })
    }

    private static func combining(
        _ a: Decimal, _ b: Decimal,
        bit: (Int, Int) -> Int,
        negative: (Bool, Bool) -> Bool
    ) throws -> Decimal {
        for value in [a, b] {
            if value.isNaN {
                throw Diagnostic.outOfRange
            }
            guard value == Numeric.roundPlain(value, scale: 0) else {
                throw Diagnostic.syntax
            }
        }
        let width = max(magnitudeBits(of: a).count, magnitudeBits(of: b).count) + 1
        let aPattern = patternBits(of: a, width: width)
        let bPattern = patternBits(of: b, width: width)
        var result = [Int]()
        for index in 0 ..< width {
            result.append(bit(aPattern[index], bPattern[index]))
        }
        let negativeResult = negative(a < 0, b < 0)
        let magnitude = negativeResult ? complementMagnitude(result) : result
        let value = try decimalFromBits(magnitude)
        return negativeResult ? -value : value
    }

    private static func patternBits(of value: Decimal, width: Int) -> [Int] {
        var padded = [Int](repeating: 0, count: width)
        let magnitude = value < 0 ? -value : value
        let bits = magnitudeBits(of: value < 0 ? magnitude - 1 : magnitude)
        for index in 0 ..< min(bits.count, width) {
            padded[index] = bits[index]
        }
        return value < 0 ? padded.map { $0 == 1 ? 0 : 1 } : padded
    }

    private static func magnitudeBits(of value: Decimal) -> [Int] {
        let magnitude = value < 0 ? -value : value
        if magnitude == 0 {
            return []
        }
        let (mantissa, exponent) = Numeric.normalizedParts(of: magnitude)
        var digitString = Numeric.normalizedMantissaDigits(of: mantissa)
        if exponent + 1 > digitString.count {
            digitString += String(
                repeating: "0", count: exponent + 1 - digitString.count
            )
        }
        var digits = digitString.compactMap(\.wholeNumberValue)
        var bits: [Int] = []
        while !(digits.count == 1 && digits[0] == 0) {
            var remainder = 0
            var quotient: [Int] = []
            for digit in digits {
                let part = remainder * 10 + digit
                quotient.append(part / 2)
                remainder = part % 2
            }
            while quotient.count > 1, quotient.first == 0 {
                quotient.removeFirst()
            }
            bits.append(remainder)
            digits = quotient
        }
        return bits
    }

    private static func complementMagnitude(_ bits: [Int]) -> [Int] {
        var flipped = bits.map { $0 == 1 ? 0 : 1 }
        var carry = 1
        var index = 0
        while carry > 0, index < flipped.count {
            let sum = flipped[index] + carry
            flipped[index] = sum % 2
            carry = sum / 2
            index += 1
        }
        return flipped
    }

    private static func decimalFromBits(_ bits: [Int]) throws -> Decimal {
        var decimalDigits = [0]
        for bit in bits.reversed() {
            var carry = bit
            var next: [Int] = []
            for digit in decimalDigits.reversed() {
                let sum = digit * 2 + carry
                next.append(sum % 10)
                carry = sum / 10
            }
            while carry > 0 {
                next.append(carry % 10); carry /= 10
            }
            decimalDigits = next.reversed()
        }
        let text = decimalDigits.map(String.init).joined()
        guard let value = Numeric.parsedDecimal(text) else {
            throw Diagnostic.outOfRange
        }
        return value
    }
}
