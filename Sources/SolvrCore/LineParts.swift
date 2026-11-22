// Line parts (ADK-331): the recognized parts of each sheet line, for the
// editor to color. The parts come from the same reading the evaluation uses.

import Foundation

/// The kinds of part a sheet line shows in a theme color.
public enum SyntaxKind: CaseIterable, Sendable {
    case heading
    case comment
    case label
    case number
    case monetaryValue
    case variable
    case unit
    case currency
    case function
    case constant
    case `operator`
    case reservedName
}

/// A recognized part of a line: its kind and its range in the line as the
/// user wrote it, in UTF-16 offsets.
public struct LinePart: Equatable, Sendable {
    public let kind: SyntaxKind
    public let range: Range<Int>

    public init(kind: SyntaxKind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// The recognized parts of each line of the sheet text, one array per line.
/// A line that cannot be calculated or is incomplete keeps the parts that
/// are recognized, characters the language does not define get no part, and
/// a text line has none.
public func lineParts(sheetText: String, context: EvaluationContext) -> [[LinePart]] {
    var evaluator = SheetEvaluator(context: context)
    return sheetText.components(separatedBy: "\n").map { line in
        _ = evaluator.evaluate(line: line)
        return evaluator.parts(ofLine: line)
    }
}

extension SheetEvaluator {
    /// The parts of one line, read after the line evaluated, so the names it
    /// defines count as variables.
    func parts(ofLine rawLine: String) -> [LinePart] {
        func offsets(_ range: Range<String.Index>) -> Range<Int> {
            rawLine.utf16.distance(from: rawLine.startIndex, to: range.lowerBound)
                ..< rawLine.utf16.distance(from: rawLine.startIndex, to: range.upperBound)
        }

        // A comment runs from the first `//` to the end of the line.
        let commentStart = rawLine.range(of: "//")?.lowerBound
        let code = commentStart.map { rawLine[rawLine.startIndex ..< $0] } ?? rawLine[...]
        let comment = commentStart.map {
            LinePart(kind: .comment, range: offsets($0 ..< rawLine.endIndex))
        }

        // The heading rule of the evaluation: one to six `#`, a space, then text.
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if case .some = Self.headingExpression.firstMatch(
            in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)
        ) {
            let start = code.firstIndex { !Tokenizer.isBlank($0) } ?? code.startIndex
            let end = code.lastIndex { !Tokenizer.isBlank($0) }.map { code.index(after: $0) } ?? code.endIndex
            return [LinePart(kind: .heading, range: offsets(start ..< end))] + (comment.map { [$0] } ?? [])
        }
        guard carriesEvaluationSignal(trimmed) else { return comment.map { [$0] } ?? [] }

        let spanned = (try? Tokenizer.scan(
            String(code), decimalSeparator: decimalSeparator, groupingSeparator: groupingSeparator,
            recovering: true
        )) ?? []
        // The tokens' indexes belong to the code slice copy; it shares its
        // offsets with the line, which begins at the same place.
        let codeText = String(code)
        func lineRange(_ range: Range<String.Index>) -> Range<Int> {
            codeText.utf16.distance(from: codeText.startIndex, to: range.lowerBound)
                ..< codeText.utf16.distance(from: codeText.startIndex, to: range.upperBound)
        }

        let definedNames = variables.definedNames
        var leading = true
        var position = 0
        var result: [LinePart] = []
        while position < spanned.count {
            let item = spanned[position]
            switch item.token {
            case .word:
                // A run of words: the longest defined name first, then each
                // word on its own.
                var end = position
                var words: [String] = []
                while end < spanned.count, case let .word(word) = spanned[end].token {
                    words.append(word)
                    end += 1
                }
                if let name = matchingDefinedName(words: words, definedNames: definedNames) {
                    let last = spanned[position + name.count - 1]
                    result.append(LinePart(kind: .variable, range: lineRange(item.range.lowerBound ..< last.range.upperBound)))
                    position += name.count
                    leading = false
                    continue
                }
                let kind = Self.kind(ofWord: words[0], leading: leading)
                if let kind {
                    result.append(LinePart(kind: kind, range: lineRange(item.range)))
                }
                position += 1
                continue
            case .number:
                result.append(LinePart(kind: .number, range: lineRange(item.range)))
            case .monetary:
                result.append(LinePart(kind: .monetaryValue, range: lineRange(item.range)))
            case .in:
                result.append(LinePart(kind: .reservedName, range: lineRange(item.range)))
            case .plus, .minus, .star, .slash, .caret, .equals, .times, .percent, .ampersand, .pipe:
                result.append(LinePart(kind: .operator, range: lineRange(item.range)))
            case .openParen, .closeParen, .semicolon, .colon, .degree, .end:
                break
            }
            leading = false
            position += 1
        }
        return result + (comment.map { [$0] } ?? [])
    }

    /// The kind of a word that no defined name claims; an unknown word is a
    /// label only in the run of words that opens the line.
    private static func kind(ofWord word: String, leading: Bool) -> SyntaxKind? {
        let lowered = word.lowercased()
        if Language.functionNames.contains(word) { return .function }
        if Language.constantNames.contains(word) { return .constant }
        if Language.operatorNames.contains(word) { return .operator }
        if Units.unit(for: word) != nil || Duration.unit(for: word) != nil { return .unit }
        if Money.names[lowered] != nil { return .currency }
        if Language.reservedNames.contains(word) || Language.reservedNames.contains(lowered) { return .reservedName }
        return leading ? .label : nil
    }
}
