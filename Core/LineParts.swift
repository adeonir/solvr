import Foundation

/// The kinds of part a sheet line shows in a theme color.
public enum SyntaxKind: CaseIterable, Sendable {
    case heading
    case comment
    /// A number with no unit, a monetary value, or a currency.
    case value
    /// A calendar date, or a duration of days or longer.
    case calendarDate
    /// A time-of-day, or a duration shorter than a day.
    case timeOfDay
    /// A quantity, or a unit written alone.
    case unit
    /// A variable, a function, or a constant.
    case name
    /// An operator, a label, or any other reserved name.
    case muted
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
    func parts(ofLine rawLine: String) -> [LinePart] {
        func offsets(_ range: Range<String.Index>) -> Range<Int> {
            rawLine.utf16.distance(from: rawLine.startIndex, to: range.lowerBound)
                ..< rawLine.utf16.distance(from: rawLine.startIndex, to: range.upperBound)
        }

        let commentStart = rawLine.range(of: "//")?.lowerBound
        let code = commentStart.map { rawLine[rawLine.startIndex ..< $0] } ?? rawLine[...]
        let comment = commentStart.map {
            LinePart(kind: .comment, range: offsets($0 ..< rawLine.endIndex))
        }

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
                var end = position
                var words: [String] = []
                while end < spanned.count, case let .word(word) = spanned[end].token {
                    words.append(word)
                    end += 1
                }
                let followsIn = position > 0 && spanned[position - 1].token == .in
                if followsIn, let count = Self.currencyWordCount(words) {
                    let last = spanned[position + count - 1]
                    result.append(LinePart(kind: .value, range: lineRange(item.range.lowerBound ..< last.range.upperBound)))
                    position += count
                    continue
                }
                let target = followsIn ? Self.kind(ofUnit: words[0]) : nil
                let weekday = words.count == 1 && Dates.Weekday(keyword: words[0]) != nil
                    && end < spanned.count && spanned[end].token == .in
                if target == nil, !weekday,
                   let name = matchingDefinedName(words: words, definedNames: definedNames)
                {
                    let last = spanned[position + name.count - 1]
                    result.append(LinePart(kind: .name, range: lineRange(item.range.lowerBound ..< last.range.upperBound)))
                    position += name.count
                    leading = false
                    continue
                }
                let kind = weekday ? .calendarDate : target ?? Self.kind(ofWord: words[0], leading: leading)
                if let kind {
                    result.append(LinePart(kind: kind, range: lineRange(item.range)))
                }
                position += 1
                continue
            case .number:
                if let pair = numberPair(at: position, in: spanned) {
                    result.append(LinePart(kind: pair.kind, range: lineRange(item.range.lowerBound ..< spanned[pair.end].range.upperBound)))
                    position = pair.end + 1
                    leading = false
                    if pair.namesPlaces {
                        position = endOfPlace(at: position, in: spanned)
                        if position < spanned.count, spanned[position].token == .in {
                            result.append(LinePart(kind: .muted, range: lineRange(spanned[position].range)))
                            position = endOfPlace(at: position + 1, in: spanned)
                        }
                    }
                    continue
                }
                result.append(LinePart(kind: .value, range: lineRange(item.range)))
            case .monetary:
                result.append(LinePart(kind: .value, range: lineRange(item.range)))
            case .in, .plus, .minus, .star, .slash, .caret, .equals, .times, .percent, .ampersand, .pipe:
                result.append(LinePart(kind: .muted, range: lineRange(item.range)))
            case .openParen, .closeParen, .semicolon, .colon, .degree, .end:
                break
            }
            leading = false
            position += 1
        }
        return result + (comment.map { [$0] } ?? [])
    }

    private func numberPair(
        at position: Int, in spanned: [Tokenizer.Spanned]
    ) -> (kind: SyntaxKind, end: Int, namesPlaces: Bool)? {
        if let end = endOfTimeOfDay(at: position, in: spanned) {
            return (.timeOfDay, end, true)
        }
        var next = position + 1
        if next < spanned.count, spanned[next].token == .degree {
            next += 1
        }
        guard next < spanned.count, case let .word(word) = spanned[next].token else { return nil }
        if let kind = Self.kind(ofUnit: word) {
            return (kind, next, false)
        }
        if Dates.month(for: word) != nil, case let .number(day) = spanned[position].token,
           Dates.integer(of: day, range: 1 ... 31) != nil
        {
            let year = next + 1
            if year < spanned.count, case let .number(value) = spanned[year].token, Dates.integer(of: value) != nil {
                return (.calendarDate, year, false)
            }
            return (.calendarDate, next, false)
        }
        return nil
    }

    private func endOfTimeOfDay(at position: Int, in spanned: [Tokenizer.Spanned]) -> Int? {
        func number(_ index: Int) -> Decimal? {
            guard index < spanned.count, case let .number(value) = spanned[index].token else { return nil }
            return value
        }
        guard let hour = number(position).flatMap({ Dates.integer(of: $0) }) else { return nil }
        var end = position + 1
        var minute = 0
        if end < spanned.count, spanned[end].token == .colon {
            guard let written = number(end + 1).flatMap({ Dates.integer(of: $0, range: 0 ... 59) }) else { return nil }
            minute = written
            end += 2
        }
        guard end < spanned.count, case let .word(word) = spanned[end].token,
              let meridiem = TimeOfDay.Meridiem(word: word),
              TimeOfDay(hour: hour, minute: minute, meridiem: meridiem) != nil
        else { return nil }
        return end
    }

    private func endOfPlace(at start: Int, in spanned: [Tokenizer.Spanned]) -> Int {
        var index = start
        while index < spanned.count, case let .word(word) = spanned[index].token,
              !TimeZones.connectorWords.contains(word.lowercased())
        {
            index += 1
        }
        return index
    }

    private static func currencyWordCount(_ words: [String]) -> Int? {
        (1 ... words.count).reversed().first {
            Money.names[words.prefix($0).joined(separator: " ").lowercased()] != nil
        }
    }

    private static func kind(ofUnit word: String) -> SyntaxKind? {
        if Units.unit(for: word) != nil {
            return .unit
        }
        return Duration.unit(for: word).map(kind(of:))
    }

    private static func kind(of unit: Duration.Unit) -> SyntaxKind {
        [Duration.second, Duration.minute, Duration.hour].contains(unit) ? .timeOfDay : .calendarDate
    }

    private static func kind(ofWord word: String, leading: Bool) -> SyntaxKind? {
        let lowered = word.lowercased()
        if Language.functionNames.contains(word) || Language.constantNames.contains(word) {
            return .name
        }
        if Language.operatorNames.contains(word) {
            return .muted
        }
        if let kind = kind(ofUnit: word) {
            return kind
        }
        if Money.names[lowered] != nil {
            return .value
        }
        if Language.reservedNames.contains(word) || Language.reservedNames.contains(lowered) {
            return .muted
        }
        return leading ? .muted : nil
    }
}
