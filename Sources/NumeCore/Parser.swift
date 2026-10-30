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
}

enum NumericOperator {
    case add, subtract, multiply, divide, power
}

enum ParseError: Error {
    /// The line is only the start of its expression.
    case pending
    /// The tokens cannot form an expression at all.
    case invalid
}

/// Names the language keeps for functions and constants; assigning to them
/// is a reserved-name error (shared language semantics).
enum Language {
    static let functionNames: Set<String> = ["min", "max", "sqrt", "fact", "sin", "round", "log"]
    static let constantNames: Set<String> = ["pi"]
    static var reservedNames: Set<String> { functionNames.union(constantNames) }
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
            guard Language.reservedNames.contains(name) == false else {
                throw LineError(diagnostic: .reservedName(name: name))
            }
            let value = try parseExpression(definedNames: definedNames)
            return .assignment(name: name, value)
        }
        position = 0
        return try parseExpression(definedNames: definedNames)
    }

    mutating func parseExpression(definedNames: Set<String>) throws -> Node {
        var lhs = try parseMultiplicative(definedNames: definedNames)
        loop: while true {
            switch peek() {
            case .plus:
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
            if peek() == .openParen, Language.functionNames.contains(first) {
                return try parseCall(name: first, definedNames: definedNames)
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
        case .minus, .plus, .star, .slash, .caret, .closeParen, .equals, .semicolon, .times, .end:
            throw atEnd ? ParseError.pending : .invalid
        }
    }

    mutating func parseCall(name: String, definedNames: Set<String>) throws -> Node {
        position += 1 // the `(`
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

    // MARK: Helpers

    private func peek() -> Token {
        position < tokens.count ? tokens[position] : .end
    }

    private var atEnd: Bool { position >= tokens.count }
}

/// Names normalize runs of spaces, tabs, and non-breaking spaces between
/// the words of a name into one space (ADR-002).
func normalizeName(_ words: [String]) -> String {
    words.joined(separator: " ")
}

/// Longest complete defined name the word run starts with, as words.
func matchingDefinedName(words: [String], definedNames: Set<String>) -> [String]? {
    guard !definedNames.isEmpty, !words.isEmpty else { return nil }
    for length in stride(from: words.count, through: 1, by: -1) {
        let candidate = Array(words.prefix(length))
        let name = normalizeName(candidate)
        if definedNames.contains(name) {
            return candidate
        }
    }
    return nil
}
