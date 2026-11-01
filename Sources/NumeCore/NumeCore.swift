// The public sheet-evaluation boundary (ADK-221). Sheets evaluate as the
// user types: `evaluate` receives the ordered sheet text and the explicit
// evaluation context and returns one result per line, per the evaluation
// contract in the product specification.

import Foundation

/// The numeric context an evaluation runs in. The caller supplies every
/// regional and temporal value; the evaluator never relies on process
/// defaults (ADR-005).
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
    /// against (ADK-250).
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
    /// A calendar date, or an instant shown with its time of day
    /// (ADK-229).
    case date(Date)
    /// A calendar-day difference in whole days, apart from any numeric
    /// magnitude (ADK-229).
    case difference(Int)
    /// A clock reading such as `11am`, apart from any numeric magnitude
    /// and from a calendar date (ADK-249).
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
    /// The unit a quantity line carries: its own unit, or the destination
    /// of a conversion (ADK-253). Nil for every other result.
    let unit: Unit?

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
        unit: Unit?
    ) {
        self.kind = kind
        self.value = value
        self.display = display
        self.diagnostic = diagnostic
        self.unit = unit
    }
}

/// Evaluate the ordered sheet text with the given context. Each line yields
/// exactly one result. Errors stay local: independent expressions keep
/// evaluating, incomplete expressions leave no usable stale result, and
/// dependents of a failure show that the dependency erred.
public func evaluate(sheetText: String, context: EvaluationContext) -> [ExpressionResult] {
    var evaluator = SheetEvaluator(context: context)
    return evaluator.evaluate(sheetText)
}

/// The sheet total (ADK-246, ADK-254). The last eligible result with an
/// explicit unit or currency selects the group; every eligible result in that
/// group adds to the total, and plain numbers join it without selecting it.
/// The total takes the group's selecting unit or currency and sums at full
/// precision. A calendar date or time of day among the eligible results, a
/// missing rate, or a sum out of range shows no total.
public func sheetTotal(of results: [ExpressionResult], context: EvaluationContext) -> ExpressionResult? {
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

/// The unit or currency a result selects a group with. A CSS relative unit
/// selects nothing: its stored count is not in its own unit (ADK-253).
private enum TotalGroup {
    case currency(String)
    case unit(Unit)

    init?(_ result: ExpressionResult) {
        if case let .monetary(value)? = result.value {
            self = .currency(value.currency)
        } else if let unit = result.unit, !unit.isRelative {
            self = .unit(unit)
        } else {
            return nil
        }
    }
}

private func totalOfGroup(of eligible: [ExpressionResult], context: EvaluationContext) throws -> ExpressionResult? {
    guard let group = eligible.compactMap(TotalGroup.init).last else {
        let sum = try sum(eligible.compactMap { plainAmount($0.value) })
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
            } else if result.unit == nil, let amount = plainAmount(result.value) {
                amounts.append(amount)
            }
        }
        let sum = try sum(amounts)
        let total = MonetaryValue(amount: Numeric.retain(sum), currency: currency)
        return ExpressionResult(kind: .expression, value: .monetary(total), display: Money.display(total, context: context))
    case let .unit(target):
        var amounts: [Decimal] = []
        for result in eligible {
            if case let .decimal(number)? = result.value, let unit = result.unit, !unit.isRelative, unit.dimension == target.dimension {
                try amounts.append(Units.convert(number, from: unit, to: target, context: context, override: nil))
            } else if result.unit == nil, let amount = plainAmount(result.value) {
                amounts.append(amount)
            }
        }
        let sum = try sum(amounts)
        let retained = Numeric.retain(sum)
        let precision = context.displayPrecision
        return ExpressionResult(
            kind: .expression,
            value: .decimal(retained),
            display: Units.display(Numeric.roundPlain(retained, scale: precision), in: target, precision: precision, locale: Locale(identifier: context.localeIdentifier)),
            diagnostic: nil,
            unit: target
        )
    }
}

private func plainAmount(_ value: ExpressionValue?) -> Decimal? {
    switch value {
    case let .decimal(number)?: number
    case let .difference(days)?: Decimal(days)
    default: nil
    }
}

private func sum(_ amounts: [Decimal]) throws -> Decimal {
    let total = try amounts.reduce(Decimal(0)) { try Numeric.add($0, $1) }
    guard Numeric.rangeDiagnostic(for: total) == nil else { throw Diagnostic.outOfRange }
    return total
}
