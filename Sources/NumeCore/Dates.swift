// Dates (ADK-229): calendar dates, calendar-day differences, weekday
// observances in weeks, calendar-month shifts, and Unix timestamps.
// The context clock fixes the instant; every date resolves in the
// context's calendar and time zone, and a calendar-day difference
// counts whole days from midnight to midnight, independent of the
// hours and of daylight-saving shifts.

import Foundation

enum Dates {
    /// A calendar date as written: `31 Mar`, `31 Mar 2027`; without a
    /// year the current year holds it, and a day the year lacks advances
    /// through the years until one carries the day (ADK-229).
    struct Spec: Equatable, Sendable {
        let day: Int
        let month: Int
        let year: Int?
    }

    /// The weekdays of the calendar with 0 on Monday.
    enum Weekday: Int, CaseIterable, Sendable {
        case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

        /// The weekday name the keyword spells: its full name, or its
        /// three-letter abbreviation, any casing.
        init?(keyword: String) {
            let keyed = keyword.lowercased()
            for weekday in Self.allCases where Self.names(weekday).contains(keyed) {
                self = weekday
                return
            }
            return nil
        }

        /// The weekday's index from Monday, the handling offset of the
        /// Monday-based week.
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

    // MARK: Recognition

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

    /// The month the keyword names (any casing), or nil.
    static func month(for keyword: String) -> Int? {
        monthNumbers[keyword.lowercased()]
    }

    /// Whether the keyword introduces the calendar-month shift; the words
    /// `month` and `months` carry the written sign.
    static func monthShiftUnit(_ keyword: String) -> Bool {
        let keyed = keyword.lowercased()
        return keyed == "month" || keyed == "months"
    }

    /// A whole count from a Decimal value, optionally held inside a range.
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

    /// Whether the node carries the calendar date a month shift applies
    /// to; the shifts chain (`31 Jan + 1 month + 1 month`).
    static func isCalendarDate(_ node: Node) -> Bool {
        switch node {
        case .date, .calendarShift:
            true
        default:
            false
        }
    }

    // MARK: Resolution

    /// The calendar date the spec resolves to: with the explicit year, the
    /// only day it holds; without it the current year, moving through the
    /// years when none carries the day (29 February).
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

    /// The whole calendar days from today to the date in the spec: with an
    /// explicit year the exact date; without it the next occurrence, today
    /// counting zero and a passed day rolling to the next year (ADK-229).
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
                    // The day exists in no year after this one either.
                    break
                }
                year += 1
            }
            guard let found else { throw Diagnostic.invalidDate }
            target = found
        }
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    /// The weekday's calendar date in the week `weeks` away: the day the
    /// Monday-based week holds for the weekday name (ADK-229).
    static func weekdayDate(
        _ weekday: Weekday, weeks: Int, now: Date, calendar: Calendar
    ) throws -> Date {
        let today = calendar.startOfDay(for: now)
        let base = calendar.date(byAdding: .weekOfYear, value: weeks, to: today)!
        // The Foundation weekday number runs 1 through 7 from Sunday;
        // Monday's own index backs the base into its week's Monday.
        let mondayOffset = (calendar.component(.weekday, from: base) + 5) % 7
        return calendar.date(
            byAdding: .day, value: weekday.daysFromMonday - mondayOffset, to: base
        )!
    }

    /// A calendar-month shift: the shift runs through the month ends, so
    /// 31 January + 1 month reaches 28 February common, 29 February leap.
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

// MARK: The sheet's date forms

extension SheetEvaluator {
    /// The evaluation calendar: Gregorian, the context time zone and
    /// locale, weeks starting Monday (ADK-229).
    var dateCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    /// The typed value of a whole-line date form, or nil when the node
    /// carries none; date errors throw their own diagnostic, so the other
    /// lines of the sheet keep evaluating (ADK-229).
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
            // A date or difference assigned to a name keeps its value, so
            // later lines reference it (ADK-258). A numeric or monetary
            // value leaves the name to its own evaluation path.
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

    /// Whether a whole-line form shows the time of day beside its date:
    /// a `fromunix` value does, and so does a name that holds one (ADK-258).
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

    /// `fromunix(N)`: the exact instant N seconds after the Unix epoch,
    /// shown in the context's time zone (ADK-229).
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

    /// The representation beside a date form: the calendar-day
    /// difference, or the date — a Unix timestamp shows its instant of
    /// day, the other forms the day alone (ADK-229).
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
