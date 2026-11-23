// `15 min` is a duration of 15 minutes, distinct from a minimum-function
// call, and each unit accepts exactly its standard abbreviation and its
// full name singular and plural; no other alias.
//
// A duration value anchors on the seconds magnitude of the written
// quantity. A conversion through `in` and the timespan form are
// representational — they never round the value — so chains compose in
// their written order: `1500 mins in days to timespan` still holds the
// full value and shows `1 day 1 hour`. A date-free month counts exactly
// 30 days and a date-free year 365, independent of the current month.
//
// Duration unit words bind to the number that precedes them, so they
// never collide with variable names spelled alike; unlike the physical
// and CSS units they carry no reserved names.

import Foundation

enum Duration {
    /// One duration unit: the factor of the unit in seconds, the word the
    /// quantity and its conversions show after their value, and the
    /// aliases (lowercased) it accepts at number and keyword positions.
    struct Unit: Sendable, Equatable {
        /// The factor of the unit in the base unit seconds.
        let factor: Decimal
        /// The singular label a count of one shows.
        let singular: String
        /// The plural label any other count shows.
        let plural: String
        /// Lowercased; lookup is not case-sensitive.
        let aliases: Set<String>

        /// The label a count shows: the singular only for exactly one.
        func label(for count: Decimal) -> String {
            count == 1 ? singular : plural
        }
    }

    static let second = Unit(
        factor: 1, singular: "s", plural: "s", aliases: ["s", "second", "seconds"]
    )
    static let minute = Unit(
        factor: 60, singular: "min", plural: "min", aliases: ["min", "mins", "minute", "minutes"]
    )
    static let hour = Unit(
        factor: 3600, singular: "hour", plural: "hours", aliases: ["h", "hour", "hours"]
    )
    static let day = Unit(
        factor: 86400, singular: "day", plural: "days", aliases: ["d", "day", "days"]
    )
    static let week = Unit(
        factor: 604_800, singular: "week", plural: "weeks", aliases: ["week", "weeks"]
    )
    /// A date-free month counts exactly 30 days.
    static let month = Unit(
        factor: 2_592_000, singular: "month", plural: "months", aliases: ["month", "months"]
    )
    /// A date-free year counts 365 days: like the month, no reference
    /// date applies.
    static let year = Unit(
        factor: 31_536_000, singular: "year", plural: "years", aliases: ["year", "years"]
    )

    static let allUnits: [Unit] = [
        Duration.second, Duration.minute, Duration.hour, Duration.day,
        Duration.week, Duration.month, Duration.year
    ]

    private static let byAlias: [String: Unit] = {
        var index: [String: Unit] = [:]
        for unit in allUnits {
            for alias in unit.aliases {
                index[alias] = unit
            }
        }
        return index
    }()

    /// The unit a word names, or nil when none accepts it.
    static func unit(for word: String) -> Unit? {
        byAlias[word.lowercased()]
    }

    // MARK: Representations

    /// The count of seconds shown in a unit: the displayed decimal places
    /// with locale separators, then the unit label for the count.
    static func count(
        _ seconds: Decimal, in unit: Unit, precision: Int, locale: Locale
    ) -> String {
        let count = seconds / unit.factor
        return labeled(count, in: unit, precision: precision, locale: locale)
    }

    /// A count already carried in its unit's own terms, with the unit
    /// label the count shows.
    private static func labeled(
        _ count: Decimal, in unit: Unit, precision: Int, locale: Locale
    ) -> String {
        Numeric.display(count, precision: precision, locale: locale)
            + " " + unit.label(for: count)
    }

    /// The timespan composition of a duration value: whole days, hours,
    /// and minutes, then the remaining seconds with their fraction
    /// preserved. Leading and all-zero parts drop, one negative sign
    /// covers the whole duration, and a fully zero duration shows
    /// `0 s`. The written order of the composed parts follows the
    /// decomposition, larger units first.
    static func timespan(of seconds: Decimal, precision: Int, locale: Locale) -> String {
        let negative = seconds < 0
        var remaining = negative ? -seconds : seconds
        var parts: [String] = []
        for unit in [Duration.day, Duration.hour, Duration.minute] {
            let wholeCount = wholeFloor(remaining / unit.factor)
            if wholeCount != 0 {
                parts.append(labeled(wholeCount, in: unit, precision: precision, locale: locale))
            }
            remaining -= wholeCount * unit.factor
        }
        if parts.isEmpty {
            return (negative ? "-" : "")
                + labeled(remaining, in: Duration.second, precision: precision, locale: locale)
        }
        if remaining != 0 {
            parts.append(
                labeled(remaining, in: Duration.second, precision: precision, locale: locale)
            )
        }
        return (negative ? "-" : "") + parts.joined(separator: " ")
    }

    /// The largest whole number counting no more than a value: exact ties
    /// round away from zero on the positive side, so the largest whole
    /// number is the rounded one unless it exceeds the value.
    private static func wholeFloor(_ value: Decimal) -> Decimal {
        var rounded = Numeric.roundPlain(value, scale: 0)
        if rounded > value {
            rounded -= 1
        }
        return rounded
    }
}

// MARK: The sheet's duration forms

extension SheetEvaluator {
    /// The representation a duration form shows, or nil when the node
    /// carries none: a quantity or a conversion shows the count in its
    /// unit, a timespan form the composed duration, a negation the count
    /// of its inner form with the sign of the value, and a call the count
    /// in the unit of its first duration-carrying argument (the rounding
    /// of `round(1 month in days)` keeps the quantity).
    func durationDisplay(of node: Node, for value: Decimal) -> String? {
        let precision = context.displayPrecision
        switch node {
        case let .duration(_, unit):
            return Duration.count(value, in: unit, precision: precision, locale: locale)
        case let .durationConversion(_, target):
            return Duration.count(value, in: target, precision: precision, locale: locale)
        case .toTimespan:
            return Duration.timespan(of: value, precision: precision, locale: locale)
        case let .unaryMinus(inner):
            return durationDisplay(of: inner, for: value)
        default:
            return nil
        }
    }
}

extension Duration {
    /// The unit a duration form's count shows in: a quantity its written
    /// unit, a conversion its destination, a negation or a timespan the
    /// unit its inner form shows.
    static func representativeUnit(of node: Node) -> Unit? {
        switch node {
        case let .duration(_, unit):
            unit
        case let .durationConversion(_, target):
            target
        case let .toTimespan(inner):
            representativeUnit(of: inner)
        case let .unaryMinus(inner):
            representativeUnit(of: inner)
        default:
            nil
        }
    }

    /// Whether a node carries a duration quantity its value counts in
    /// seconds: the forms, their negation, and their composition
    /// recursively.
    static func carriesQuantity(of node: Node) -> Bool {
        switch node {
        case .duration, .durationConversion, .toTimespan:
            true
        case let .unaryMinus(inner):
            carriesQuantity(of: inner)
        default:
            false
        }
    }
}
