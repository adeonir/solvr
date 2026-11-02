// SheetRefresh (ADK-230): keeps a sheet's visible results current through
// the reevaluation triggers the application supplies — an edit, local
// midnight, sheet opening, returning to the app, and a daylight-saving
// transition of a time zone a conversion uses (ADK-251). The clock arrives
// with every trigger; nothing here reads the process clock (ADR-005), so
// the same lifecycle runs for the app and the integration tests. The
// triggers themselves stay outside the evaluator: a refresh only repeats
// the sheet evaluation of the contract with a fresh instant.

import Foundation

/// What made the visible results refresh, apart from an edit (ADK-230).
public enum SheetRefreshTrigger: Sendable, Equatable {
    /// Local midnight in the system time zone.
    case midnight
    /// The sheet became active.
    case sheetOpening
    /// The user returned to the app.
    case returningToApp
    /// A source or destination time zone of a visible conversion reached
    /// its next daylight-saving transition (ADK-251).
    case daylightSavingTransition
}

/// The outcome of one refresh: the visible results, parallel to the
/// sheet's lines, and the indexes whose visible result the refresh touched.
public struct SheetRefreshOutcome: Sendable, Equatable {
    public let results: [ExpressionResult]
    public let changedIndexes: Set<Int>
}

/// Keeps one sheet's visible results current (ADK-230). The refresher
/// holds the sheet text, the evaluation context, and the results from the
/// last evaluation; every trigger reevaluates the text with the instant it
/// carries, so a changed date refreshes the visible results and a line
/// that no longer produces a result loses it — no stale value remains.
public struct SheetRefresher: Sendable {
    public private(set) var sheetText: String
    public private(set) var context: EvaluationContext
    /// The visible results, one per line, from the last evaluation.
    public private(set) var results: [ExpressionResult]
    /// The lines whose results depend on the current date; the empty set
    /// when nothing on the sheet follows the clock.
    public private(set) var dateDependentIndexes: Set<Int>
    /// The time zones the visible time-of-day conversions use, source and
    /// destination (ADK-251); the empty set when no visible result converts
    /// a time between zones.
    public private(set) var conversionTimeZones: Set<TimeZone>
    /// The cities the visible time-of-day conversions name (ADK-250),
    /// whether resolved, unknown, ambiguous, or never looked up; the
    /// application keeps each one's city data current from this set.
    public private(set) var cityNames: Set<String>

    /// Whether any visible result depends on the current date, so local
    /// midnight and the return-to-app recheck matter for it.
    public var hasDateDependentResults: Bool {
        !dateDependentIndexes.isEmpty
    }

    /// Whether any visible result follows a time zone's daylight-saving
    /// rules, so that zone's next transition needs a reevaluation.
    public var hasTimeZoneDependentResults: Bool {
        !conversionTimeZones.isEmpty
    }

    /// The sheet total's display text at the current precision, or nil when
    /// no total is available (ADK-256). The line results stay as they are.
    public var total: String? {
        sheetTotal(of: results, context: context)?.display
    }

    /// The first instant after `instant` at which a time zone a visible
    /// conversion uses changes its offset, or nil when no zone it uses
    /// changes again (ADK-251). The earliest transition decides, so a
    /// conversion between two zones follows whichever moves first.
    public func nextDaylightSavingTransition(after instant: Date) -> Date? {
        conversionTimeZones
            .compactMap { $0.nextDaylightSavingTimeTransition(after: instant) }
            .min()
    }

    /// Opens the sheet: the immediate first evaluation counts as the
    /// opening evaluation.
    public init(sheetText: String, context: EvaluationContext) {
        self.sheetText = sheetText
        self.context = context
        results = []
        dateDependentIndexes = []
        conversionTimeZones = []
        cityNames = []
        _ = reevaluate(now: context.now)
        dateDependentIndexes = Self.detectDateDependence(
            sheetText: sheetText, context: context
        )
    }

    /// An edit rewrites the text and evaluates it immediately, so a line
    /// edited into an incomplete or plain-text form loses its previous
    /// result on the spot.
    @discardableResult
    public mutating func update(sheetText newSheetText: String, now: Date) -> SheetRefreshOutcome {
        sheetText = newSheetText
        context.now = now
        dateDependentIndexes = Self.detectDateDependence(
            sheetText: newSheetText, context: context
        )
        return reevaluate(now: now)
    }

    /// Reevaluation by a lifecycle trigger — local midnight, sheet
    /// opening, returning to the app, or a daylight-saving transition. The
    /// trigger carries the current instant; the text stays untouched.
    @discardableResult
    public mutating func refresh(_: SheetRefreshTrigger, now: Date) -> SheetRefreshOutcome {
        reevaluate(now: now)
    }

    /// The city names the visible results could not resolve because the
    /// city data held no outcome for them yet (ADK-250); the application
    /// looks them up and hands the fresh data back.
    public var uncachedCityNames: Set<String> {
        Set(results.compactMap { result in
            guard case let .cityNotCached(name) = result.diagnostic else { return nil }
            return name
        })
    }

    // MARK: Reevaluation

    @discardableResult
    public mutating func update(exchangeRates: ExchangeRateSnapshot, now: Date) -> SheetRefreshOutcome {
        context.exchangeRates = exchangeRates
        return reevaluate(now: now)
    }

    /// A precision change from Settings reaches the visible results at
    /// once, with the sheet text untouched (ADK-255).
    @discardableResult
    public mutating func update(displayPrecision: Int, cryptoPrecision: Int, now: Date) -> SheetRefreshOutcome {
        context.displayPrecision = displayPrecision
        context.cryptoPrecision = cryptoPrecision
        return reevaluate(now: now)
    }

    /// Fresh city data reaches the visible results without a text edit
    /// (ADK-250): a city resolved after the sheet opened turns its error
    /// into a clock.
    @discardableResult
    public mutating func update(cityTimeZones: CityTimeZoneSnapshot, now: Date) -> SheetRefreshOutcome {
        context.cityTimeZones = cityTimeZones
        return reevaluate(now: now)
    }

    private mutating func reevaluate(now: Date) -> SheetRefreshOutcome {
        context.now = now
        let fresh = evaluate(sheetText: sheetText, context: context)
        var changedIndexes: Set<Int> = []
        for index in fresh.indices where results.indices.contains(index) {
            if fresh[index] != results[index] {
                changedIndexes.insert(index)
            }
        }
        // Lines the older text no longer holds count as changed too.
        if fresh.count != results.count {
            changedIndexes.formUnion(fresh.indices)
        }
        results = fresh
        // A conversion follows both zones it names, so its transitions
        // steer the next reevaluation (ADK-251), and the cities it names
        // steer the city data lookup (ADK-250). A sheet without a visible
        // time-of-day result uses no zone and no city.
        let places = fresh.contains(where: Self.usesPlace)
            ? TimeZones.used(inSheetText: sheetText, context: context)
            : TimeZones.SheetPlaces()
        conversionTimeZones = places.zones
        cityNames = places.cities
        return SheetRefreshOutcome(results: fresh, changedIndexes: changedIndexes)
    }

    /// Whether a visible result comes from a time-of-day form, so the sheet
    /// uses the time zones and cities that form names.
    private static func usesPlace(_ result: ExpressionResult) -> Bool {
        if case .timeOfDay = result.value {
            return true
        }
        switch result.diagnostic {
        case .unknownCity, .ambiguousCity, .cityNotCached:
            return true
        default:
            return false
        }
    }

    // MARK: Date-dependence detection

    /// The lines whose results depend on the current date, found by
    /// evaluating the text at the same month, day, and time of one and
    /// four years ahead of the context's calendar: every date form that
    /// follows the clock changes its result across those probes, while
    /// every other line — arithmetic, explicit-year dates, Unix
    /// timestamps — keeps its result exactly.
    private static func detectDateDependence(
        sheetText: String, context: EvaluationContext
    ) -> Set<Int> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        let base = evaluate(sheetText: sheetText, context: context)
        var dependent: Set<Int> = []
        for years in [1, 4] {
            var probe = context
            probe.now = calendar.date(byAdding: .year, value: years, to: context.now)!
            let probed = evaluate(sheetText: sheetText, context: probe)
            for index in base.indices where base[index] != probed[index] {
                dependent.insert(index)
            }
        }
        return dependent
    }
}
