// Number scanning is region-aware; inline comments are stripped at the
// caller, not here. Characters the language does not define fail with
// invalid syntax.

import Foundation

struct LineError: Error {
    var diagnostic: Diagnostic
}

enum Token: Equatable, Sendable {
    case number(Decimal)
    case monetary(MonetaryValue)
    case word(String)
    case plus
    case minus
    case star
    case slash
    case caret
    case openParen
    case closeParen
    case equals
    case semicolon
    /// The `:` between the hour and the minute of a clock reading.
    case colon
    case times
    /// The `in` keyword that introduces a representation conversion.
    case `in`
    /// The `%` sign of a percent form.
    case percent
    /// The bitwise AND `&` of the operator split: arithmetic binds
    /// tighter.
    case ampersand
    /// The bitwise OR `|`; the `or` word shares the meaning.
    case pipe
    /// The degree marker `°` that rides its number.
    case degree
    /// Nothing left on the line; only the parser sees it.
    case end
}

enum Tokenizer {
    static func tokenize(
        _ line: String,
        decimalSeparator: Character,
        groupingSeparator: Character
    ) throws -> [Token] {
        try scan(line, decimalSeparator: decimalSeparator, groupingSeparator: groupingSeparator, recovering: false)
            .map(\.token)
    }

    /// A token with the range of the line it was read from.
    struct Spanned {
        let token: Token
        let range: Range<String.Index>
    }

    /// Reads the tokens with their ranges. A recovering scan skips what it
    /// cannot read, a character the language does not define or a number
    /// that does not parse, instead of throwing.
    static func scan(
        _ line: String,
        decimalSeparator: Character,
        groupingSeparator: Character,
        recovering: Bool
    ) throws -> [Spanned] {
        var tokens: [Spanned] = []
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            let start = index
            let locale = Locale(identifier: decimalSeparator == "." ? "en_US" : "pt_BR")
            let literal = recovering
                ? try? Money.scanLiteral(at: index, in: line, locale: locale)
                : try Money.scanLiteral(at: index, in: line, locale: locale)
            if let (value, next) = literal {
                tokens.append(Spanned(token: .monetary(value), range: start ..< next))
                index = next
                continue
            }
            if character.isLetter {
                while index < line.endIndex,
                      line[index].isLetter || line[index].isNumber || line[index] == "_"
                {
                    index = line.index(after: index)
                }
                let word = String(line[start ..< index])
                tokens.append(Spanned(token: word == "times" ? .times : word == "in" ? .in : .word(word), range: start ..< index))
                continue
            }
            if character.isNumber {
                // A base literal `0b/0o/0x <digits>` shares the plain
                // decimal value of its digits in its base.
                if let literal = Display.scanBaseLiteral(at: index, in: line) {
                    tokens.append(Spanned(token: .number(literal.value), range: start ..< literal.end))
                    index = literal.end
                    continue
                }
                do {
                    let (number, next) = try scanNumber(
                        from: index, in: line,
                        decimalSeparator: decimalSeparator,
                        groupingSeparator: groupingSeparator
                    )
                    tokens.append(Spanned(token: .number(number), range: start ..< next))
                    index = next
                } catch where recovering {
                    index = line.index(after: index)
                }
                continue
            }
            let token: Token?
            switch character {
            case "+": token = .plus
            case "-": token = .minus
            case "*", "×": token = .star
            case "/": token = .slash
            case "^": token = .caret
            case "(": token = .openParen
            case ")": token = .closeParen
            case "=": token = .equals
            case ";": token = .semicolon
            case ":": token = .colon
            case "%": token = .percent
            case "&": token = .ampersand
            case "|": token = .pipe
            case "°": token = .degree
            case " ", "\t", "\u{00A0}", "\u{202F}", "\u{2060}":
                token = nil
            default:
                if !recovering {
                    throw LineError(diagnostic: .syntax)
                }
                token = nil
            }
            index = line.index(after: index)
            if let token {
                tokens.append(Spanned(token: token, range: start ..< index))
            }
        }
        return tokens
    }

    /// Scan a number: a run of digits and the two regional separators,
    /// with the blanks between digit groups of a grouped number inside the
    /// run. A separator at the run edges folds the trailing part into its
    /// own token, so an expression like `2.+3` fails as invalid syntax
    /// instead of swallowing characters.
    static func scanNumber(
        from start: String.Index, in line: String,
        decimalSeparator: Character, groupingSeparator: Character
    ) throws -> (Decimal, String.Index) {
        var index = start
        var run = ""
        while index < line.endIndex {
            let character = line[index]
            if character.isNumber || character == decimalSeparator || character == groupingSeparator {
                run += String(character)
                index = line.index(after: index)
            } else if isBlank(character) {
                // A blank inside a number may group digits: `5 300` is one
                // number when the following group is complete.
                let next = line.index(after: index)
                guard next < line.endIndex, line[next].isNumber else { break }
                run += String(character)
                index = next
            } else {
                break
            }
        }
        guard let number = parseNumberRun(run, decimal: decimalSeparator, grouping: groupingSeparator) else {
            throw LineError(diagnostic: .syntax)
        }
        return (number, index)
    }

    /// Interpret a digit run. Digits around the locale decimal separator
    /// are decimal; the other separator groups thousands in complete 3-digit
    /// groups, and blanks inside the run group alike; when both kinds
    /// appear, the last separator is the decimal one. A run that starts
    /// ends with separators, repeats adjacent separators, uses a duplicate
    /// decimal point, or wears incomplete groups does not parse.
    static func parseNumberRun(
        _ run: String, decimal decimalSeparator: Character, grouping groupingSeparator: Character
    ) -> Decimal? {
        var digits: [Character] = []
        var separators: [Int: Character] = [:]
        for (offset, character) in run.enumerated() {
            if character.isNumber {
                digits.append(character)
            } else {
                // Blanks group like the locale grouping separator here;
                // the complete-group check decides whether the run reads
                // as one number.
                separators[offset] = isBlank(character) ? groupingSeparator : character
                digits.append("/")
            }
        }
        guard digits.first?.isNumber == true, digits.last?.isNumber == true else { return nil }
        for pair in zip(digits, digits.dropFirst()) where pair.0 == "/" && pair.1 == "/" {
            return nil
        }

        let kinds = Set(separators.values)
        var canonical = ""
        if kinds.isEmpty {
            canonical = digits.map { String($0) }.joined()
        } else if kinds.count == 2 {
            let lastPosition = separators.keys.max()!
            guard separators[lastPosition] == decimalSeparator,
                  separators.values.filter({ $0 == decimalSeparator }).count == 1,
                  separators.values.filter({ $0 == groupingSeparator }).count == separators.count - 1,
                  hasCompleteGroups(
                      digits: Array(digits[0 ..< lastPosition]),
                      separators: separators.filter { $0.key < lastPosition },
                      grouping: groupingSeparator
                  )
            else { return nil }
            // The grouped digits fold together; only the decimal separator
            // survives the canonical form: `1.500,5` is `1500.5`.
            canonical = digits
                .enumerated()
                .map { offset, digit -> String in
                    if digit != "/" {
                        return String(digit)
                    }
                    return offset == lastPosition ? "." : ""
                }
                .joined()
        } else if separators.count == 1, let only = separators.values.first, only == decimalSeparator {
            canonical = digits.map { $0 == "/" ? "." : String($0) }.joined()
        } else if separators.values.allSatisfy({ $0 == groupingSeparator }),
                  hasCompleteGroups(digits: digits, separators: separators, grouping: groupingSeparator)
        {
            canonical = digits.filter { $0 != "/" }.map(String.init).joined()
        } else {
            return nil
        }
        guard let value = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return value
    }

    /// A run grouping with the locale grouping separator needs every group
    /// to be three digits long before the first group can be shorter, with
    /// no shorter trailing group: `1.500` is a thousand (Brazilian), while
    /// `1.50` is not a valid number in that locale.
    static func hasCompleteGroups(
        digits: [Character], separators: [Int: Character], grouping _: Character
    ) -> Bool {
        let positions = separators.keys.sorted()
        guard !positions.isEmpty else { return false }
        var previous = -1
        for (step, position) in positions.enumerated() {
            let groupLength = position - previous - 1
            if step > 0, groupLength != 3 {
                return false
            }
            previous = position
        }
        let tail = digits.count - positions.last! - 1
        return tail == 3
    }

    /// The horizontal blanks between words and between grouped digits
    /// count alike.
    static func isBlank(_ character: Character) -> Bool {
        character == " " || character == "\t"
            || character == "\u{00A0}" || character == "\u{202F}" || character == "\u{2060}"
    }
}
