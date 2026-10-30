// Tokenizer (ADK-221): turns one sheet line into tokens with region-aware
// number scanning, inline-comment stripping at the caller, and the `times`
// multiplication word. Characters the language does not define fail with
// invalid syntax.

import Foundation

struct LineError: Error {
    var diagnostic: Diagnostic
}

import Foundation

enum Token: Equatable, Sendable {
    case number(Decimal)
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
    case times
    /// Nothing left on the line; only the parser sees it.
    case end
}

enum Tokenizer {
    static func tokenize(
        _ line: String,
        decimalSeparator: Character,
        groupingSeparator: Character
    ) throws -> [Token] {
        var tokens: [Token] = []
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character.isLetter {
                let start = index
                while index < line.endIndex,
                    line[index].isLetter || line[index].isNumber || line[index] == "_"
                {
                    index = line.index(after: index)
                }
                let word = String(line[start ..< index])
                tokens.append(word == "times" ? .times : .word(word))
                continue
            }
            if character.isNumber {
                let (number, next) = try scanNumber(
                    from: index, in: line,
                    decimalSeparator: decimalSeparator,
                    groupingSeparator: groupingSeparator
                )
                tokens.append(.number(number))
                index = next
                continue
            }
            switch character {
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*", "×": tokens.append(.star)
            case "/": tokens.append(.slash)
            case "^": tokens.append(.caret)
            case "(": tokens.append(.openParen)
            case ")": tokens.append(.closeParen)
            case "=": tokens.append(.equals)
            case ";": tokens.append(.semicolon)
            case " ", "\t", "\u{00A0}", "\u{202F}", "\u{2060}":
                break
            default:
                throw LineError(diagnostic: .syntax)
            }
            index = line.index(after: index)
        }
        return tokens
    }

    /// Scan a number: a run of digits and the two regional separators. A
    /// separator at the run edges folds the trailing part into its own
    /// token, so an expression like `2.+3` fails as invalid syntax instead
    /// of swallowing characters.
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
            } else {
                break
            }
        }
        guard let number = parseNumberRun(run, decimal: decimalSeparator, grouping: groupingSeparator) else {
            throw LineError(diagnostic: .syntax)
        }
        return (number, index)
    }

    /// Interpret a digit run. Digits around the locale decimal separator are
    /// decimal; the other separator groups thousands in complete 3-digit
    /// groups; when both kinds appear, the last separator is the decimal
    /// one. A run that starts ends with separators, repeats adjacent
    /// separators, uses a duplicate decimal point, or wears incomplete
    /// groups does not parse.
    static func parseNumberRun(
        _ run: String, decimal decimalSeparator: Character, grouping groupingSeparator: Character
    ) -> Decimal? {
        var digits: [Character] = []
        var separators: [Int: Character] = [:]
        for (offset, character) in run.enumerated() {
            if character.isNumber {
                digits.append(character)
            } else {
                separators[offset] = character
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
            canonical = digits.map { $0 == "/" ? "." : String($0) }.joined()
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
        digits: [Character], separators: [Int: Character], grouping: Character
    ) -> Bool {
        let positions = separators.keys.sorted()
        guard !positions.isEmpty else { return false }
        var previous = -1
        for (step, position) in positions.enumerated() {
            let groupLength = position - previous - 1
            if step > 0 && groupLength != 3 {
                return false
            }
            previous = position
        }
        let tail = digits.count - positions.last! - 1
        return tail == 3
    }
}
