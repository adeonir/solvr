// Parser (ADK-221): recursive descent over the token line with arithmetic
// precedence, right-associative `^`, unary minus binding looser than `^`,
// implicit multiplication through a parenthesis, `;` argument separation,
// and the incomplete/invalid distinction: a line cut short at its end — a
// trailing operator, an unclosed parenthesis or call, a bare assignment —
// is incomplete and shows no message.

import Foundation

enum Node {
    case number(Decimal)
    case monetary(MonetaryValue)
    indirect case monetaryConversion(Node, String)
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
    /// A duration quantity: a number with a time unit, whose value
    /// anchors on the seconds magnitude (ADK-228).
    case duration(Decimal, Duration.Unit)
    /// A duration conversion through `in`: representational, the count
    /// shown in the destination unit while the value keeps its seconds
    /// magnitude (ADK-228).
    indirect case durationConversion(Node, Duration.Unit)
    /// `N to timespan`: the duration composed to its decomposed form,
    /// representational like the conversion (ADK-228).
    indirect case toTimespan(Node)
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
    /// A calendar date literal: `31 Mar`, `31 Mar 2027` (ADK-229).
    case date(Dates.Spec)
    /// `days until <date>`: the calendar-day difference to the date
    /// (ADK-229).
    case daysUntil(Dates.Spec)
    /// `<weekday> in N weeks`: the weekday of the calendar week N weeks
    /// away (ADK-229).
    case weekday(Dates.Weekday, weeks: Int)
    /// `<date> + N month(s)` and its negative `... - ...`: a shift in
    /// calendar months (ADK-229).
    indirect case calendarShift(Node, months: Int)
    /// A clock reading with the place it belongs to: `11am`, `11am PST`;
    /// no place means the sheet's system time zone (ADK-249).
    case timeOfDay(TimeOfDay, place: TimeZones.Place?)
    /// `<time> in <place>`: the same instant shown in the destination
    /// place's clock (ADK-249).
    indirect case timeOfDayConversion(Node, target: TimeZones.Place)
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
                if case let .word(word) = tokens[index] {
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
                lhs = try .binary(.bitwiseOr, lhs, parseBitwiseAnd(definedNames: definedNames))
            default:
                break loop
            }
        }
        while peek() == .in, let match = currencyName(at: position + 1) {
            position = match.end
            lhs = .monetaryConversion(lhs, match.code)
        }
        return lhs
    }

    mutating func parseBitwiseAnd(definedNames: Set<String>) throws -> Node {
        var lhs = try parseAdditive(definedNames: definedNames)
        loop: while peek() == .ampersand {
            position += 1
            lhs = try .binary(.bitwiseAnd, lhs, parseAdditive(definedNames: definedNames))
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
                // The calendar-month shift keeps whole calendar months on
                // a date; other values add numerically (ADK-229).
                if Dates.isCalendarDate(lhs), let months = try parseMonthCount() {
                    lhs = .calendarShift(lhs, months: months)
                } else {
                    lhs = try .binary(.add, lhs, parseMultiplicative(definedNames: definedNames))
                }
            case .minus:
                position += 1
                if Dates.isCalendarDate(lhs), let months = try parseMonthCount() {
                    lhs = .calendarShift(lhs, months: -months)
                } else {
                    lhs = try .binary(.subtract, lhs, parseMultiplicative(definedNames: definedNames))
                }
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
                lhs = try .binary(.multiply, lhs, parsePower(definedNames: definedNames))
            case .slash:
                position += 1
                lhs = try .binary(.divide, lhs, parsePower(definedNames: definedNames))
            case .openParen:
                // Implicit multiplication: `2 (3)` multiplies 2 by 3.
                lhs = try .binary(.multiply, lhs, parsePower(definedNames: definedNames))
            case .in:
                if currencyName(at: position + 1) != nil {
                    break loop
                }
                // Representation and unit conversions at the tight
                // multiplicative level: `0b110111011 in hex + 1` adds one
                // to the value, `10 ft in m` converts the quantity.
                position += 1
                // A time-of-day converts into the clock of the place the
                // line names: `11am PST in London` (ADK-249).
                if case .timeOfDay = lhs, let target = parsePlace() {
                    lhs = .timeOfDayConversion(lhs, target: target)
                } else {
                    guard case let .word(keyword) = peek() else {
                        throw atEnd ? ParseError.pending : .invalid
                    }
                    if let representation = Display.Representation(keyword: keyword) {
                        position += 1
                        lhs = .representation(representation, lhs)
                    } else if let unit = Units.unit(for: keyword) {
                        position += 1
                        lhs = try parseConversion(lhs, unit, definedNames: definedNames)
                    } else if let unit = Duration.unit(for: keyword) {
                        // A duration unit conversion is representational: the
                        // count shows in the destination unit (ADK-228).
                        position += 1
                        lhs = .durationConversion(lhs, unit)
                    } else {
                        throw ParseError.invalid
                    }
                }
            case let .word(leading) where leading.lowercased() == "to":
                // `to timespan` composes the duration representation in
                // the written order, at the same level as `in` (ADK-228):
                // `1500 mins to timespan in days` reads the days back and
                // `1500 mins in days to timespan` composes last.
                guard peekTimespanKeyword() else {
                    throw position + 1 >= tokens.count ? ParseError.pending : .invalid
                }
                position += 2
                lhs = .toTimespan(lhs)
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
            return try .unaryMinus(parsePower(definedNames: definedNames))
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
        case let .monetary(value):
            position += 1
            return .monetary(value)
        case let .number(value):
            position += 1
            // The degree marker rides its number: `45°` keeps the value
            // and the trigonometric forms read degrees (ADK-225).
            if peek() == .degree {
                position += 1
            }
            // A written clock reading keeps its hour and minute as clock
            // fields, read in the place it names or in the system time
            // zone (ADK-249).
            if let time = parseTimeOfDay(starting: value) {
                return time
            }
            // A unit word straight after its number makes the pair a
            // quantity: `16px` or `2 inches` (ADK-227).
            if case let .word(unitWord) = peek(), let unit = Units.unit(for: unitWord) {
                position += 1
                return .quantity(value, unit)
            }
            // A duration unit word straight after its number makes the
            // pair a duration quantity: `15 min` is 15 minutes, not a
            // minimum call (ADK-228).
            if case let .word(unitWord) = peek(), let unit = Duration.unit(for: unitWord) {
                position += 1
                return .duration(value, unit)
            }
            // A month name straight after its number makes the pair a
            // calendar date, with an optional year after the month
            // (ADK-229).
            if case let .word(monthWord) = peek(), Dates.month(for: monthWord) != nil {
                let date = try parseDateLiteral(day: value)
                return .date(date)
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
        case let .word(first):
            position += 1
            // `days until <date>`: the calendar-day difference to the
            // next occurrence or the dated day (ADK-229).
            if first.lowercased() == "days", case let .word(second) = peek(), second.lowercased() == "until" {
                position += 1
                return try parseDaysUntil()
            }
            // `<weekday> in N weeks`: the weekday of the calendar week N
            // weeks away (ADK-229).
            if let weekday = Dates.Weekday(keyword: first.lowercased()), peek() == .in {
                position += 1
                return try parseWeekday(weekday)
            }
            if Language.functionNames.contains(first) {
                return try parseFunctionCall(first, definedNames: definedNames)
            }
            // Recognize the longest complete name defined before the
            // reference; any run of spaces, tabs, and non-breaking spaces
            // between the words of a name counts as one space (ADR-002).
            var words = [first]
            while case let .word(word) = peek() {
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
        case .minus, .plus, .star, .slash, .caret, .closeParen, .equals, .semicolon, .colon, .times, .in, .percent, .end, .ampersand, .pipe, .degree:
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
        var arguments: [Node] = try [parseExpression(definedNames: definedNames)]
        while peek() == .semicolon {
            position += 1
            try arguments.append(parseExpression(definedNames: definedNames))
        }
        guard peek() == .closeParen else {
            throw atEnd ? ParseError.pending : .invalid
        }
        position += 1
        return .call(name: name, arguments: arguments)
    }

    /// Whether the tokens from the current position spell `timespan`
    /// behind the `to` the caller seen: `N to timespan` is the composed
    /// duration form (ADK-228).
    private func peekTimespanKeyword() -> Bool {
        guard position + 1 < tokens.count, case let .word(second) = tokens[position + 1] else {
            return false
        }
        return second.lowercased() == "timespan"
    }

    // MARK: Percent forms (ADK-226)

    /// The percent forms after `<value>%`: `of M` takes the share of M,
    /// `off M` takes the share of M off it, and the bare `%` is the
    /// portion N/100 that `X - N%` consumes.
    private mutating func parsePercentForms(
        _ lhs: Node, definedNames: Set<String>
    ) throws -> Node {
        position += 1 // the `%`
        if case let .word(keyword) = peek(), keyword == "of" || keyword == "off" {
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
        _ source: Node, _ target: Unit, definedNames _: Set<String>
    ) throws -> Node {
        // The expression-local `at Npx` or `at N ppi` clause substitutes
        // its reference for this expression only (ADK-227).
        if case let .word(keyword) = peek(), keyword == "at" {
            position += 1
            guard case let .number(value) = peek() else {
                throw atEnd ? ParseError.pending : .invalid
            }
            position += 1
            guard case let .word(unitWord) = peek(),
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

    // MARK: Date forms (ADK-229)

    /// `<day> <month> [year]` after the day's number is known: the whole
    /// numbers parse, a non-integer or out-of-range day runs the numeric
    /// line logic instead of a date.
    private mutating func parseDateLiteral(day: Decimal) throws -> Dates.Spec {
        guard let dayNumber = Dates.integer(of: day, range: 1 ... 31), case let .word(monthWord) = peek(), let month = Dates.month(for: monthWord) else {
            throw ParseError.invalid
        }
        position += 1
        return try parseYearSuffix(day: dayNumber, month: month)
    }

    /// The optional year after a written date, whole numbers only.
    private mutating func parseYearSuffix(day: Int, month: Int) throws -> Dates.Spec {
        var year: Int?
        if case let .number(value) = peek() {
            guard let yearNumber = Dates.integer(of: value) else {
                throw ParseError.invalid
            }
            year = yearNumber
            position += 1
        }
        return Dates.Spec(day: day, month: month, year: year)
    }

    /// After `days until`: the day and month, optional year, form the
    /// referenced date; the `until` keyword cannot stand alone.
    private mutating func parseDaysUntil() throws -> Node {
        guard case let .number(day) = peek() else {
            throw atEnd ? ParseError.pending : .invalid
        }
        position += 1
        let spec = try parseDateLiteral(day: day)
        return .daysUntil(spec)
    }

    /// After the weekday's name: `in N weeks`, whole weeks only.
    private mutating func parseWeekday(_ weekday: Dates.Weekday) throws -> Node {
        guard case let .number(count) = peek() else {
            throw atEnd ? ParseError.pending : .invalid
        }
        position += 1
        guard case let .word(unit) = peek(),
              ["week", "weeks"].contains(unit.lowercased()),
              let weeks = Dates.integer(of: count)
        else {
            throw ParseError.invalid
        }
        position += 1
        return .weekday(weekday, weeks: weeks)
    }

    /// `<date> +/- N month(s)` on a calendar date: the written sign the
    /// caller already consumed, so the count comes out signed at the end.
    /// No count with months behind it keeps the plain operator form.
    private mutating func parseMonthCount() throws -> Int? {
        guard case let .number(count) = peek() else { return nil }
        let next = position + 1
        guard next < tokens.count, case let .word(unit) = tokens[next],
              Dates.monthShiftUnit(unit)
        else {
            return nil
        }
        guard let whole = Dates.integer(of: count) else { throw ParseError.invalid }
        position += 2
        return whole
    }

    // MARK: Time-of-day forms (ADK-249)

    /// `<hour>[:<minute>] am|pm` after its hour number is known, with the
    /// place the reading belongs to when one follows. A non-whole or
    /// out-of-range hour, a missing minute, or a missing meridiem leaves
    /// the number to the numeric line logic.
    private mutating func parseTimeOfDay(starting hour: Decimal) -> Node? {
        guard let whole = Dates.integer(of: hour) else { return nil }
        var minute = 0
        var meridiemIndex = position
        if peek() == .colon {
            guard case let .number(value) = peek(1),
                  let written = Dates.integer(of: value, range: 0 ... 59)
            else { return nil }
            minute = written
            meridiemIndex += 2
        }
        guard case let .word(word) = peek(meridiemIndex - position),
              let meridiem = TimeOfDay.Meridiem(word: word),
              let time = TimeOfDay(hour: whole, minute: minute, meridiem: meridiem)
        else { return nil }
        position = meridiemIndex + 1
        return .timeOfDay(time, place: parsePlace())
    }

    /// The place the coming word run names: one time zone abbreviation such
    /// as `PST`, or a city such as `London`, `New York`, or `sf`, whose zone
    /// the city data resolves during evaluation (ADK-249, ADK-250).
    private mutating func parsePlace() -> TimeZones.Place? {
        var words: [String] = []
        var index = position
        while index < tokens.count, case let .word(word) = tokens[index],
              !TimeZones.connectorWords.contains(word.lowercased())
        {
            words.append(word)
            index += 1
        }
        guard let place = TimeZones.place(words: words) else { return nil }
        position = index
        return place
    }

    // MARK: Helpers

    private func currencyName(at start: Int) -> (code: String, end: Int)? {
        var index = start
        var words: [String] = []
        var match: (String, Int)?
        while index < tokens.count, case let .word(word) = tokens[index] {
            words.append(word.lowercased())
            index += 1
            if let code = Money.names[words.joined(separator: " ")] {
                match = (code, index)
            }
        }
        return match
    }

    private func peek(_ offset: Int = 0) -> Token {
        let index = position + offset
        return index < tokens.count ? tokens[index] : .end
    }

    private var atEnd: Bool {
        position >= tokens.count
    }
}
