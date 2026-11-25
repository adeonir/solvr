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
    case colon
    case times
    case `in`
    case percent
    case ampersand
    case pipe
    case degree
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

    struct Spanned {
        let token: Token
        let range: Range<String.Index>
    }

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

    static func parseNumberRun(
        _ run: String, decimal decimalSeparator: Character, grouping groupingSeparator: Character
    ) -> Decimal? {
        var digits: [Character] = []
        var separators: [Int: Character] = [:]
        for (offset, character) in run.enumerated() {
            if character.isNumber {
                digits.append(character)
            } else {
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

    static func isBlank(_ character: Character) -> Bool {
        character == " " || character == "\t"
            || character == "\u{00A0}" || character == "\u{202F}" || character == "\u{2060}"
    }
}
