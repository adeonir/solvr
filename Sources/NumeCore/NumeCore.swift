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

    public init(
        kind: LineKind,
        value: ExpressionValue? = nil,
        display: String? = nil,
        diagnostic: Diagnostic? = nil
    ) {
        self.kind = kind
        self.value = value
        self.display = display
        self.diagnostic = diagnostic
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

/// The sheet total over monetary results (ADK-246): every monetary result
/// converts into the currency of the last one and sums at full precision.
/// Results that are not monetary stay out of the sum; a sheet with a date
/// among its results, or with no monetary result, has no total. A rate the
/// total needs but lacks shows its diagnostic.
public func sheetTotal(of results: [ExpressionResult], context: EvaluationContext) -> ExpressionResult? {
    var monetary: [MonetaryValue] = []
    for result in results {
        switch result.value {
        case let .monetary(value):
            monetary.append(value)
        case .date, .difference, .timeOfDay:
            return nil
        case .decimal, .none:
            continue
        }
    }
    guard let currency = monetary.last?.currency else { return nil }
    do {
        var amount = Decimal(0)
        for value in monetary {
            amount = try Numeric.add(amount, context.exchangeRates.convert(value, to: currency).amount)
        }
        let total = MonetaryValue(amount: Numeric.retain(amount), currency: currency)
        return ExpressionResult(kind: .expression, value: .monetary(total), display: Money.display(total, context: context))
    } catch let diagnostic as Diagnostic {
        return ExpressionResult(kind: .expression, diagnostic: diagnostic)
    } catch {
        return ExpressionResult(kind: .expression, diagnostic: .syntax)
    }
}
