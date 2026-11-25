import Foundation

enum Dates {
    struct Spec: Equatable, Sendable {
        let day: Int
        let month: Int
        let year: Int?
    }

    enum Weekday: Int, CaseIterable, Sendable {
        case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

        init?(keyword: String) {
            let keyed = keyword.lowercased()
            for weekday in Self.allCases where Self.names(weekday).contains(keyed) {
                self = weekday
                return
            }
            return nil
        }

        var daysFromMonday: Int {
            rawValue
        }

        private static func names(_ weekday: Weekday) -> [String] {
            let full = [
                "monday", "tuesday", "wednesday", "thursday",
                "friday", "saturday", "sunday"
            ]
            let abbreviations = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
            return [full[weekday.rawValue], abbreviations[weekday.rawValue]]
        }
    }

    private static let monthNumbers: [String: Int] = {
        let abbreviations = [
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "oct", "nov", "dec"
        ]
        let full = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december"
        ]
        var numbers: [String: Int] = [:]
        for month in 1 ... 12 {
            numbers[abbreviations[month - 1]] = month
            numbers[full[month - 1]] = month
        }
        return numbers
    }()

    static func month(for keyword: String) -> Int? {
        monthNumbers[keyword.lowercased()]
    }

    static func monthShiftUnit(_ keyword: String) -> Bool {
        let keyed = keyword.lowercased()
        return keyed == "month" || keyed == "months"
    }

    static func integer(of value: Decimal, range: ClosedRange<Int>? = nil) -> Int? {
        guard !value.isNaN, value == Numeric.roundPlain(value, scale: 0) else {
            return nil
        }
        let integer = NSDecimalNumber(decimal: value).intValue
        if let range, !range.contains(integer) {
            return nil
        }
        return integer
    }

    static func isCalendarDate(_ node: Node) -> Bool {
        switch node {
        case .date, .calendarShift:
            true
        default:
            false
        }
    }

    static func resolve(_ spec: Spec, now: Date, calendar: Calendar) throws -> Date {
        guard let year = spec.year else {
            let startYear = calendar.component(.year, from: now)
            var candidate = startYear
            while candidate - startYear <= 400 {
                if let date = calendarDate(
                    day: spec.day, month: spec.month, year: candidate, calendar: calendar
                ) {
                    return date
                }
                candidate += 1
            }
            throw Diagnostic.invalidDate
        }
        guard let date = calendarDate(
            day: spec.day, month: spec.month, year: year, calendar: calendar
        ) else {
            throw Diagnostic.invalidDate
        }
        return date
    }

    static func calendarDays(until spec: Spec, now: Date, calendar: Calendar) throws -> Int {
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: today)
        let target: Date
        if let year = spec.year {
            guard let date = calendarDate(
                day: spec.day, month: spec.month, year: year, calendar: calendar
            ) else {
                throw Diagnostic.invalidDate
            }
            target = date
        } else {
            var year = thisYear
            var found: Date?
            while year - thisYear <= 400 {
                if let candidate = calendarDate(
                    day: spec.day, month: spec.month, year: year, calendar: calendar
                ) {
                    if candidate >= today {
                        found = candidate
                        break
                    }
                } else if !(spec.month == 2 && spec.day == 29) {
                    break
                }
                year += 1
            }
            guard let found else { throw Diagnostic.invalidDate }
            target = found
        }
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    static func weekdayDate(
        _ weekday: Weekday, weeks: Int, now: Date, calendar: Calendar
    ) throws -> Date {
        let today = calendar.startOfDay(for: now)
        let base = calendar.date(byAdding: .weekOfYear, value: weeks, to: today)!
        return calendar.date(
            byAdding: .day, value: weekday.daysFromMonday - mondayOffset(for: base, calendar: calendar), to: base
        )!
    }

    private static func mondayOffset(for date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func calendarShift(_ date: Date, months: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: months, to: date)!
    }

    private static func calendarDate(
        day: Int, month: Int, year: Int, calendar: Calendar
    ) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return nil
        }
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        guard (1 ... days).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

extension SheetEvaluator {
    var dateCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    mutating func evaluateDateForm(_ node: Node) throws -> ExpressionValue? {
        let calendar = dateCalendar
        switch node {
        case let .date(spec):
            return try .date(Dates.resolve(spec, now: context.now, calendar: calendar))
        case let .daysUntil(spec):
            return try .difference(
                Dates.calendarDays(until: spec, now: context.now, calendar: calendar)
            )
        case let .weekday(weekday, weeks):
            return try .date(
                Dates.weekdayDate(weekday, weeks: weeks, now: context.now, calendar: calendar)
            )
        case let .calendarShift(base, months):
            guard case let .date(day) = try evaluateDateForm(base) else {
                throw Diagnostic.syntax
            }
            return .date(
                Dates.calendarShift(day, months: months, calendar: calendar)
            )
        case let .call(name, arguments) where name == "fromunix":
            return try .date(fromunixTimestamp(arguments))
        case let .assignment(name, inner):
            do {
                guard let value = try evaluateDateForm(inner) else { return nil }
                variables.define(
                    name, value, measure: dateMeasure(value),
                    showsTimeOfDay: showsTimeOfDay(of: inner)
                )
                return value
            } catch {
                variables.fail(name)
                throw error
            }
        case let .reference(name):
            switch variables.bindings[name] {
            case .date?, .difference?:
                return variables.bindings[name]
            default:
                return nil
            }
        default:
            return nil
        }
    }

    func showsTimeOfDay(of node: Node) -> Bool {
        switch node {
        case let .assignment(_, inner):
            showsTimeOfDay(of: inner)
        case let .call(name, _):
            name == "fromunix"
        case let .reference(name):
            variables.showsTimeOfDay.contains(name)
        default:
            false
        }
    }

    private mutating func fromunixTimestamp(_ arguments: [Node]) throws -> Date {
        guard arguments.count == 1 else {
            throw Diagnostic.argumentCount(function: "fromunix", requirement: "1 argument")
        }
        let seconds = try evaluate(node: arguments[0])
        guard Dates.integer(of: seconds) != nil else {
            throw Diagnostic.syntax
        }
        return Date(timeIntervalSince1970: NSDecimalNumber(decimal: seconds).doubleValue)
    }

    func dateDisplay(_ value: ExpressionValue, showsTimeOfDay: Bool) -> String? {
        switch value {
        case let .difference(days):
            return "\(days) \(abs(days) == 1 ? "day" : "days")"
        case let .date(instant):
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = context.timeZone
            formatter.dateFormat = showsTimeOfDay ? "d MMMM yyyy HH:mm:ss" : "d MMMM yyyy"
            return formatter.string(from: instant)
        default:
            return nil
        }
    }
}
