import Foundation

enum Duration {
    struct Unit: Sendable, Equatable {
        let factor: Decimal
        let singular: String
        let plural: String
        let aliases: Set<String>

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
    static let month = Unit(
        factor: 2_592_000, singular: "month", plural: "months", aliases: ["month", "months"]
    )
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

    static func unit(for word: String) -> Unit? {
        byAlias[word.lowercased()]
    }

    static func count(
        _ seconds: Decimal, in unit: Unit, precision: Int, locale: Locale
    ) -> String {
        let count = seconds / unit.factor
        return labeled(count, in: unit, precision: precision, locale: locale)
    }

    private static func labeled(
        _ count: Decimal, in unit: Unit, precision: Int, locale: Locale
    ) -> String {
        Numeric.display(count, precision: precision, locale: locale)
            + " " + unit.label(for: count)
    }

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

    private static func wholeFloor(_ value: Decimal) -> Decimal {
        var rounded = Numeric.roundPlain(value, scale: 0)
        if rounded > value {
            rounded -= 1
        }
        return rounded
    }
}

extension SheetEvaluator {
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
