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
    indirect case representation(Display.Representation, Node)
    indirect case quantity(Decimal, Unit)
    case duration(Decimal, Duration.Unit)
    indirect case durationConversion(Node, Duration.Unit)
    indirect case toTimespan(Node)
    indirect case conversion(Node, Unit, override: Units.Override?)
    indirect case percentShare(Node, Node)
    indirect case percentOff(Node, Node)
    indirect case percentPortion(Node)
    case date(Dates.Spec)
    case daysUntil(Dates.Spec)
    case weekday(Dates.Weekday, weeks: Int)
    indirect case calendarShift(Node, months: Int)
    case timeOfDay(TimeOfDay, place: TimeZones.Place?)
    indirect case timeOfDayConversion(Node, target: TimeZones.Place)
}

enum NumericOperator {
    case add, subtract, multiply, divide, power
    case bitwiseAnd, bitwiseOr
}

enum ParseError: Error {
    case pending
    case pendingAssignment(String)
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
            position += 1
            let name = normalizeName(names)
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

    mutating func parseAdditive(definedNames: Set<String>) throws -> Node {
        var lhs = try parseMultiplicative(definedNames: definedNames)
        loop: while true {
            switch peek() {
            case .plus, .word("and"):
                position += 1
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
                lhs = try .binary(.multiply, lhs, parsePower(definedNames: definedNames))
            case .in:
                if currencyName(at: position + 1) != nil {
                    break loop
                }
                position += 1
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
                        position += 1
                        lhs = .durationConversion(lhs, unit)
                    } else {
                        throw ParseError.invalid
                    }
                }
            case let .word(leading) where leading.lowercased() == "to":
                guard peekTimespanKeyword() else {
                    throw position + 1 >= tokens.count ? ParseError.pending : .invalid
                }
                position += 2
                lhs = .toTimespan(lhs)
            case .percent:
                lhs = try parsePercentForms(lhs, definedNames: definedNames)
            case .word("as") where matchesPercentRatioKeyword():
                position += 4
                let total = try parsePower(definedNames: definedNames)
                lhs = .representation(.percent, .binary(.divide, lhs, total))
            default:
                break loop
            }
        }
        return lhs
    }

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
            if peek() == .degree {
                position += 1
            }
            if let time = parseTimeOfDay(starting: value) {
                return time
            }
            if case let .word(unitWord) = peek(), let unit = Units.unit(for: unitWord) {
                position += 1
                return .quantity(value, unit)
            }
            if case let .word(unitWord) = peek(), let unit = Duration.unit(for: unitWord) {
                position += 1
                return .duration(value, unit)
            }
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
            if first.lowercased() == "days", case let .word(second) = peek(), second.lowercased() == "until" {
                position += 1
                return try parseDaysUntil()
            }
            if let weekday = Dates.Weekday(keyword: first.lowercased()), peek() == .in {
                position += 1
                return try parseWeekday(weekday)
            }
            if Language.functionNames.contains(first) {
                return try parseFunctionCall(first, definedNames: definedNames)
            }
            var words = [first]
            while case let .word(word) = peek() {
                words.append(word)
                position += 1
            }
            let defined = matchingDefinedName(
                words: words, definedNames: definedNames
            )
            if let match = defined, match.count < words.count {
                position -= words.count - match.count
            }
            return .reference(defined?.joined(separator: " ") ?? first)
        case .minus, .plus, .star, .slash, .caret, .closeParen, .equals, .semicolon, .colon, .times, .in, .percent, .end, .ampersand, .pipe, .degree:
            throw atEnd ? ParseError.pending : .invalid
        }
    }

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
        position += 1
        let value = try parseExpression(definedNames: definedNames)
        guard peek() == .closeParen else {
            throw atEnd ? ParseError.pending : .invalid
        }
        position += 1
        return .call(name: name, arguments: [value, base])
    }

    mutating func parseCall(name: String, definedNames: Set<String>) throws -> Node {
        position += 1
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

    private func peekTimespanKeyword() -> Bool {
        guard position + 1 < tokens.count, case let .word(second) = tokens[position + 1] else {
            return false
        }
        return second.lowercased() == "timespan"
    }

    private mutating func parsePercentForms(
        _ lhs: Node, definedNames: Set<String>
    ) throws -> Node {
        position += 1
        if case let .word(keyword) = peek(), keyword == "of" || keyword == "off" {
            position += 1
            let amount = try parsePower(definedNames: definedNames)
            return keyword == "of" ? .percentShare(lhs, amount) : .percentOff(lhs, amount)
        }
        if case .word = peek() {
            throw ParseError.invalid
        }
        return .percentPortion(lhs)
    }

    private func matchesPercentRatioKeyword() -> Bool {
        position + 4 < tokens.count
            && tokens[position + 1] == .word("a")
            && tokens[position + 2] == .percent
            && tokens[position + 3] == .word("of")
    }

    private mutating func parseConversion(
        _ source: Node, _ target: Unit, definedNames _: Set<String>
    ) throws -> Node {
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

    private mutating func parseDateLiteral(day: Decimal) throws -> Dates.Spec {
        guard let dayNumber = Dates.integer(of: day, range: 1 ... 31), case let .word(monthWord) = peek(), let month = Dates.month(for: monthWord) else {
            throw ParseError.invalid
        }
        position += 1
        return try parseYearSuffix(day: dayNumber, month: month)
    }

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

    private mutating func parseDaysUntil() throws -> Node {
        guard case let .number(day) = peek() else {
            throw atEnd ? ParseError.pending : .invalid
        }
        position += 1
        let spec = try parseDateLiteral(day: day)
        return .daysUntil(spec)
    }

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
