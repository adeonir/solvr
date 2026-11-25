import Foundation

/// The numeric context an evaluation runs in. The caller supplies every
/// regional and temporal value; the evaluator never relies on process
/// defaults.
public struct EvaluationContext: Sendable, Equatable {
    /// Regional number formatting, e.g. `"pt_BR"`.
    public var localeIdentifier: String
    /// The time zone dates and instants resolve against.
    public var timeZone: TimeZone
    /// The injected clock: the current instant for date evaluation.
    public var now: Date
    /// Displayed decimal places.
    public var displayPrecision: Int
    /// Decimal places of a cryptocurrency result, from 5 to 15 (Settings).
    public var cryptoPrecision: Int {
        didSet { cryptoPrecision = Self.clampedCryptoPrecision(cryptoPrecision) }
    }

    /// The shared pixel base for `rem` and `em`, in pixels.
    public var pixelBase: Decimal
    /// The default pixel density for point-to-pixel conversion, in ppi.
    public var ppi: Decimal
    public var exchangeRates: ExchangeRateSnapshot
    /// The city data a time-of-day conversion by city name resolves
    /// against.
    public var cityTimeZones: CityTimeZoneSnapshot

    public init(
        localeIdentifier: String,
        timeZone: TimeZone,
        now: Date,
        displayPrecision: Int,
        pixelBase: Decimal = 16,
        ppi: Decimal = 96,
        exchangeRates: ExchangeRateSnapshot = .shipped,
        cityTimeZones: CityTimeZoneSnapshot = .empty,
        cryptoPrecision: Int = 10
    ) {
        self.localeIdentifier = localeIdentifier
        self.timeZone = timeZone
        self.now = now
        self.displayPrecision = displayPrecision
        self.pixelBase = pixelBase
        self.ppi = ppi
        self.exchangeRates = exchangeRates
        self.cityTimeZones = cityTimeZones
        self.cryptoPrecision = Self.clampedCryptoPrecision(cryptoPrecision)
    }

    private static func clampedCryptoPrecision(_ value: Int) -> Int {
        min(15, max(5, value))
    }
}

/// What one sheet line is.
public enum LineKind: Sendable, Equatable {
    /// A Markdown heading; never evaluated.
    case heading
    /// A whole-line comment; never evaluated.
    case comment
    /// An expression that was evaluated, failed, or could not finish.
    case expression
    /// A line with no number, operator, `=`, or known name: plain text.
    case textLine
    /// The line is the start of a valid expression cut short at its end;
    /// it shows no message and no stale result remains.
    case incomplete
}

/// The value of an evaluated expression, kept strictly separate from its
/// display representation.
public enum ExpressionValue: Sendable, Equatable {
    case decimal(Decimal)
    case monetary(MonetaryValue)
    /// A calendar date, or an instant shown with its time of day.
    case date(Date)
    /// A calendar-day difference in whole days, apart from any numeric
    /// magnitude.
    case difference(Int)
    /// A clock reading such as `11am`, apart from any numeric magnitude
    /// and from a calendar date.
    case timeOfDay(TimeOfDay)
}

/// One line's evaluation outcome: per line a nullable value, its display
/// representation, and a diagnostic or nil.
public struct ExpressionResult: Sendable, Equatable {
    public let kind: LineKind
    /// The numeric value, when the line produced one.
    public let value: ExpressionValue?
    /// The representation shown beside the expression, or nil.
    public let display: String?
    /// What failed, or nil when the line has a result or has none to show.
    public let diagnostic: Diagnostic?
    let unit: Unit?
    let measure: Measure?

    public init(
        kind: LineKind,
        value: ExpressionValue? = nil,
        display: String? = nil,
        diagnostic: Diagnostic? = nil
    ) {
        self.init(kind: kind, value: value, display: display, diagnostic: diagnostic, unit: nil)
    }

    init(
        kind: LineKind,
        value: ExpressionValue?,
        display: String?,
        diagnostic: Diagnostic?,
        unit: Unit?,
        measure: Measure? = nil
    ) {
        self.kind = kind
        self.value = value
        self.display = display
        self.diagnostic = diagnostic
        self.unit = unit
        self.measure = measure
    }
}

enum Measure: Sendable, Equatable {
    case unit(Unit)
    case time(Duration.Unit)
}

/// Evaluate the ordered sheet text with the given context. Each line yields
/// exactly one result. Errors stay local: independent expressions keep
/// evaluating, incomplete expressions leave no usable stale result, and
/// dependents of a failure show that the dependency erred.
public func evaluate(sheetText: String, context: EvaluationContext) -> [ExpressionResult] {
    var evaluator = SheetEvaluator(context: context)
    return evaluator.evaluate(sheetText)
}

/// The sheet total. The last eligible result with an explicit unit,
/// currency, or time unit selects the group; every eligible result
/// compatible with that group adds to the total, and plain numbers join it
/// without selecting it. The total takes the group's selecting unit or
/// currency and sums at full precision. A calendar date or time of day
/// among the eligible results, a missing rate, a line out of range, or a
/// sum out of range shows no total.
public func sheetTotal(of results: [ExpressionResult], context: EvaluationContext) -> ExpressionResult? {
    let suppressesTotal = results.contains { result in
        switch result.diagnostic {
        case .exchangeRateUnavailable?, .outOfRange?: true
        default: false
        }
    }
    guard !suppressesTotal else { return nil }
    let eligible = results.filter { $0.diagnostic == nil && $0.value != nil }
    guard !eligible.isEmpty else { return nil }
    let hasClockOrDate = eligible.contains { result in
        switch result.value {
        case .date?, .timeOfDay?: true
        default: false
        }
    }
    guard !hasClockOrDate else { return nil }
    return try? totalOfGroup(of: eligible, context: context)
}

private enum TotalGroup {
    case currency(String)
    case measure(Measure)

    init?(_ result: ExpressionResult) {
        if case let .monetary(value)? = result.value {
            self = .currency(value.currency)
        } else if let measure = result.measure {
            self = .measure(measure)
        } else {
            return nil
        }
    }
}

private func totalOfGroup(of eligible: [ExpressionResult], context: EvaluationContext) throws -> ExpressionResult? {
    guard let group = eligible.compactMap(TotalGroup.init).last else {
        let sum = try sum(eligible.compactMap(plainAmount))
        let precision = context.displayPrecision
        return ExpressionResult(
            kind: .expression,
            value: .decimal(Numeric.retain(sum)),
            display: Numeric.display(Numeric.roundPlain(sum, scale: precision), precision: precision, locale: Locale(identifier: context.localeIdentifier))
        )
    }
    switch group {
    case let .currency(currency):
        var amounts: [Decimal] = []
        for result in eligible {
            if case let .monetary(value)? = result.value {
                try amounts.append(context.exchangeRates.convert(value, to: currency).amount)
            } else if let amount = plainAmount(result) {
                amounts.append(amount)
            }
        }
        let sum = try sum(amounts)
        let total = MonetaryValue(amount: Numeric.retain(sum), currency: currency)
        return ExpressionResult(kind: .expression, value: .monetary(total), display: Money.display(total, context: context))
    case let .measure(target):
        var amounts: [Decimal] = []
        for result in eligible {
            if let amount = try amount(of: result, in: target, context: context) {
                amounts.append(amount)
            }
        }
        let sum = try sum(amounts)
        let retained = Numeric.retain(sum)
        let precision = context.displayPrecision
        let locale = Locale(identifier: context.localeIdentifier)
        switch target {
        case let .unit(unit):
            return ExpressionResult(
                kind: .expression,
                value: .decimal(retained),
                display: Units.display(Numeric.roundPlain(retained, scale: precision), in: unit, precision: precision, locale: locale),
                diagnostic: nil,
                unit: unit
            )
        case let .time(unit):
            return ExpressionResult(
                kind: .expression,
                value: .decimal(retained),
                display: Duration.count(sum * unit.factor, in: unit, precision: precision, locale: locale)
            )
        }
    }
}

private func amount(of result: ExpressionResult, in target: Measure, context: EvaluationContext) throws -> Decimal? {
    if let plain = plainAmount(result) {
        return plain
    }
    switch (target, result.measure, result.value) {
    case let (.unit(target), .unit(source)?, .decimal(number)?) where source.dimension == target.dimension:
        if source.isRelative {
            let pixels = try Numeric.multiply(number, context.pixelBase)
            return try Units.convert(pixels, from: .pixel, to: target, context: context, override: nil)
        }
        return try Units.convert(number, from: source, to: target, context: context, override: nil)
    case let (.time(target), .time?, .decimal(seconds)?):
        return try Numeric.divide(seconds, by: target.factor)
    case let (.time(target), .time?, .difference(days)?):
        return try Numeric.divide(Numeric.multiply(Decimal(days), Duration.day.factor), by: target.factor)
    default:
        return nil
    }
}

private func plainAmount(_ result: ExpressionResult) -> Decimal? {
    guard result.measure == nil, case let .decimal(number)? = result.value else { return nil }
    return number
}

private func sum(_ amounts: [Decimal]) throws -> Decimal {
    let total = try amounts.reduce(Decimal(0)) { try Numeric.add($0, $1) }
    guard Numeric.rangeDiagnostic(for: total) == nil else { throw Diagnostic.outOfRange }
    return total
}
