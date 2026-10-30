// Parser (ADK-221): recursive descent over the token line with arithmetic
// precedence, right-associative `^`, unary minus binding looser than `^`,
// implicit multiplication through a parenthesis, `;` argument separation,
// and the incomplete/invalid distinction: a line cut short at its end — a
// trailing operator, an unclosed parenthesis or call, a bare assignment —
// is incomplete and shows no message.

import Foundation

enum Node {
    case number(Decimal)
    case reference(String)
    indirect case call(name: String, arguments: [Node])
    indirect case binary(NumericOperator, Node, Node)
    indirect case unaryMinus(Node)
    indirect case assignment(name: String, Node)
    /// A representation conversion: the inner value's numeric meaning does
    /// not change; the kind picks how the line displays it (ADK-222).
    indirect case representation(Display.Representation, Node)
    /// A quantity: a number with its unit, in the sense the language
    /// defines for conversions (ADK-227).
    indirect case quantity(Decimal, Unit)
    /// A quantity conversion through `in`: the value converts into the
    /// target unit, which the whole line's display carries (ADK-227). An
    /// `at` override substitutes a Settings reference for this
    /// expression only.
    indirect case conversion(Node, Unit, override: Units.Override?)
    /// `N% of M`: the share M that the percent N names (ADK-226).
    indirect case percentShare(Node, Node)
    /// `N% off M`: M with the share taken off it (ADK-226).
    indirect case percentOff(Node, Node)
    /// The bare `N%`: the fraction N/100, meaningful inside `X - N%`
    /// (ADK-226).
    indirect case percentPortion(Node)
}

enum NumericOperator {
    case add, subtract, multiply, divide, power
    /// The bitwise operators over whole numbers: arithmetic binds tighter
    /// than `&`, and `&` binds tighter than `|` and the `or` word (ADK-225).
    case bitwiseAnd, bitwiseOr
}

enum ParseError: Error {
    /// The line is only the start of its expression.
    case pending
    /// The line is an assignment whose value is still only the start of
    /// its expression; the assigned name walks with it, so dependents of
    /// the name never see a stale value (an assigned name whose expression
    /// never finished keeps it erred for the sheet).
    case pendingAssignment(String)
    /// The tokens cannot form an expression at all.
    case invalid
}

struct Parser {
    let tokens: [Token]
    private(set) var position: Int

    static func parse(_ tokens: [Token], definedNames: Set<String> = []) throws -> Node {
        var parser = Parser(tokens: tokens, position: 0)
        let node = try parser.parseTop(definedNames: definedNames)
        guard parser.atEnd else { throw ParseError.invalid }
        return node
    }

    mutating func parseTop(definedNames: Set<String>) throws -> Node {
        // Assignment: a leading word run the `=` ends at top level.
        var words = 0
        while case .word = peek() {
            words += 1
            position += 1
        }
        if words > 0, peek() == .equals {
            var names: [String] = []
            names.reserveCapacity(words)
            for index in 0 ..< tokens.count where index < words {
                if case .word(let word) = tokens[index] {
                    names.append(word)
                }
            }
            position += 1 // the `=`
            let name = normalizeName(names)
            // Unit aliases hold for every casing, so their reservation
            // holds likewise (ADK-227).
            guard Language.reservedNames.contains(name.lowercased()) == false else {
                throw LineError(diagnostic: .reservedName(name: name))
            }
            let value: Node
            do {
                value = try parseExpression(definedNames: definedNames)
            } catch ParseError.pending {
                throw ParseError.pendingAssignment(name)
            }
            return .assignment(name: name, value)
        }
        position = 0
        return try parseExpression(definedNames: definedNames)
    }

    /// Arithmetic binds tighter than `&` (bitwise AND), and `&` binds
    /// tighter than `|` and the `or` word (bitwise OR): `1 + 2 & 2` is 2
    /// and `1 | 2 & 0` is 1 (ADK-225). The `and` word weighs as the
    /// addition it stands for, so `6 and 3` is 9.
    mutating func parseExpression(definedNames: Set<String>) throws -> Node {
        var lhs = try parseBitwiseAnd(definedNames: definedNames)
        loop: while true {
            switch peek() {
            case .pipe, .word("or"):
                position += 1
                lhs = .binary(.bitwiseOr, lhs, try parseBitwiseAnd(definedNames: definedNames))
            default:
                break loop
            }
        }
        return lhs
    }

    mutating func parseBitwiseAnd(definedNames: Set<String>) throws -> Node {
        var lhs = try parseAdditive(definedNames: definedNames)
        loop: while peek() == .ampersand {
            position += 1
            lhs = .binary(.bitwiseAnd, lhs, try parseAdditive(definedNames: definedNames))
        }
        return lhs
    }

    /// The additive level: `+`, `-`, and the `and` word, which adds.
    mutating func parseAdditive(definedNames: Set<String>) throws -> Node {
        var lhs = try parseMultiplicative(definedNames: definedNames)
        loop: while true {
            switch peek() {
            case .plus, .word("and"):
                position += 1
                lhs = .binary(.add, lhs, try parseMultiplicative(definedNames: definedNames))
            case .minus:
                position += 1
                lhs = .binary(.subtract, lhs, try parseMultiplicative(definedNames: definedNames))
            default:
                break loop
            }
        }
        return lhs
    }

    mutating func parseMultiplicative(definedNames: Set<String>) throws -> Node {
        var lhs = try parsePower(definedNames: definedNames)
        loop: while true {
            switch peek() {
            case .star, .times:
                position += 1
                lhs = .binary(.multiply, lhs, try parsePower(definedNames: definedNames))
            case .slash:
                position += 1
                lhs = .binary(.divide, lhs, try parsePower(definedNames: definedNames))
            case .openParen:
                // Implicit multiplication: `2 (3)` multiplies 2 by 3.
                lhs = .binary(.multiply, lhs, try parsePower(definedNames: definedNames))
            case .in:
                // Representation and unit conversions at the tight
                // multiplicative level: `0b110111011 in hex + 1` adds one
                // to the value, `10 ft in m` converts the quantity.
                position += 1
                guard case .word(let keyword) = peek() else {
                    throw atEnd ? ParseError.pending : .invalid
                }
                if let representation = Display.Representation(keyword: keyword) {
                    position += 1
                    lhs = .representation(representation, lhs)
                } else if let unit = Units.unit(for: keyword) {
                    position += 1
                    lhs = try parseConversion(lhs, unit, definedNames: definedNames)
                } else {
                    throw ParseError.invalid
                }
            case .percent:
                lhs = try parsePercentForms(lhs, definedNames: definedNames)
            case .word("as") where matchesPercentRatioKeyword():
                // `X as a % of Y`: the ratio shown as a percent
                // representation (ADK-226); the numeric value stays X/Y.
                position += 4 // as, a, %, of
                let total = try parsePower(definedNames: definedNames)
                lhs = .representation(.percent, .binary(.divide, lhs, total))
            default:
                break loop
            }
        }
        return lhs
    }

    /// Unary minus binds looser than `^`: `-2^2` is -(2^2), while the
    /// exponent side accepts signs, right-associatively: `2^3^2` is 512.
    mutating func parsePower(definedNames: Set<String>) throws -> Node {
        if peek() == .minus {
            position += 1
            return .unaryMinus(try parsePower(definedNames: definedNames))
        }
        let lhs = try parsePrimary(definedNames: definedNames)
        if peek() == .caret {
            position += 1
            let exponent = try parsePower(definedNames: definedNames)
            return .binary(.power, lhs, exponent)
        }
        return lhs
    }

    mutating func parsePrimary(definedNames: Set<String>) throws -> Node {
        switch peek() {
        case .number(let value):
            position += 1
            // The degree marker rides its number: `45°` keeps the value
            // and the trigonometric forms read degrees (ADK-225).
            if peek() == .degree {
                position += 1
            }
            // A unit word straight after its number makes the pair a
            // quantity: `16px` or `2 inches` (ADK-227).
            if case .word(let unitWord) = peek(), let unit = Units.unit(for: unitWord) {
                position += 1
                return .quantity(value, unit)
            }
            return .number(value)
        case .openParen:
            position += 1
            let inner = try parseExpression(definedNames: definedNames)
            guard peek() == .closeParen else {
                throw atEnd ? ParseError.pending : .invalid
            }
            position += 1
            return inner
        case .word(let first):
            position += 1
            if Language.functionNames.contains(first) {
                return try parseFunctionCall(first, definedNames: definedNames)
            }
            // Recognize the longest complete name defined before the
            // reference; any run of spaces, tabs, and non-breaking spaces
            // between the words of a name counts as one space (ADR-002).
            var words = [first]
            while case .word(let word) = peek() {
                words.append(word)
                position += 1
            }
            let defined = matchingDefinedName(
                words: words, definedNames: definedNames
            )
            if let match = defined, match.count < words.count {
                position -= words.count - match.count // leave stray words for the leftover check
            }
            return .reference(defined?.joined(separator: " ") ?? first)
        case .minus, .plus, .star, .slash, .caret, .closeParen, .equals, .semicolon, .times, .in, .percent, .end, .ampersand, .pipe, .degree:
            throw atEnd ? ParseError.pending : .invalid
        }
    }

    /// Call forms: the parentheses form like `min(3; 7)` and the prefix
    /// form without parentheses, where the operand follows the name, like
    /// `sqrt 16`. The `log` name takes its base before the value in the
    /// prefix form, so `log 2 (10)` is the base-2 logarithm of 10 (ADK-225).
    private mutating func parseFunctionCall(
        _ name: String, definedNames: Set<String>
    ) throws -> Node {
        if peek() == .openParen {
            return try parseCall(name: name, definedNames: definedNames)
        }
        let base = try parsePower(definedNames: definedNames)
        guard name == "log", peek() == .openParen else {
            return .call(name: name, arguments: [base])
        }
        position += 1 // the `(`
        let value = try parseExpression(definedNames: definedNames)
        guard peek() == .closeParen else {
            throw atEnd ? ParseError.pending : .invalid
        }
        position += 1
        return .call(name: name, arguments: [value, base])
    }

    mutating func parseCall(name: String, definedNames: Set<String>) throws -> Node {
        position += 1 // the `(`
        // An empty call still parses, so `sqrt()` names its argument-count
        // error instead of failing as unmatched syntax (ADK-225).
        guard peek() != .closeParen else {
            position += 1
            return .call(name: name, arguments: [])
        }
        var arguments: [Node] = [try parseExpression(definedNames: definedNames)]
        while peek() == .semicolon {
            position += 1
            arguments.append(try parseExpression(definedNames: definedNames))
        }
        guard peek() == .closeParen else {
            throw atEnd ? ParseError.pending : .invalid
        }
        position += 1
        return .call(name: name, arguments: arguments)
    }

    // MARK: Percent forms (ADK-226)

    /// The percent forms after `<value>%`: `of M` takes the share of M,
    /// `off M` takes the share of M off it, and the bare `%` is the
    /// portion N/100 that `X - N%` consumes.
    private mutating func parsePercentForms(
        _ lhs: Node, definedNames: Set<String>
    ) throws -> Node {
        position += 1 // the `%`
        if case .word(let keyword) = peek(), keyword == "of" || keyword == "off" {
            position += 1
            let amount = try parsePower(definedNames: definedNames)
            return keyword == "of" ? .percentShare(lhs, amount) : .percentOff(lhs, amount)
        }
        // The words reserved for the percent forms mean nothing alone.
        if case .word = peek() {
            throw ParseError.invalid
        }
        return .percentPortion(lhs)
    }

    /// Whether the words from the current position spell the ratio keyword
    /// `as a % of`, with an operand after it: `X as a % of Y`.
    private func matchesPercentRatioKeyword() -> Bool {
        position + 4 < tokens.count
            && tokens[position + 1] == .word("a")
            && tokens[position + 2] == .percent
            && tokens[position + 3] == .word("of")
    }

    // MARK: Unit forms (ADK-227)

    private mutating func parseConversion(
        _ source: Node, _ target: Unit, definedNames: Set<String>
    ) throws -> Node {
        // The expression-local `at Npx` or `at N ppi` clause substitutes
        // its reference for this expression only (ADK-227).
        if case let .word(keyword) = peek(), keyword == "at" {
            position += 1
            guard case .number(let value) = peek() else {
                throw atEnd ? ParseError.pending : .invalid
            }
            position += 1
            guard case .word(let unitWord) = peek(),
                let kind = Units.Override.kind(for: unitWord)
            else {
                throw atEnd ? ParseError.pending : .invalid
            }
            position += 1
            return .conversion(
                source, target, override: Units.Override(kind: kind, value: value)
            )
        }
        return .conversion(source, target, override: nil)
    }

    // MARK: Helpers

    private func peek() -> Token {
        position < tokens.count ? tokens[position] : .end
    }

    private var atEnd: Bool { position >= tokens.count }
}
