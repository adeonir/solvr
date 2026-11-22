// One coordinator owns the refresher for the open sheet and translates the
// real system events into the model layer's reevaluation triggers: an edit,
// local midnight in the system time zone, sheet opening, returning to the
// app, and the next daylight-saving transition of a time zone a visible
// conversion uses. The coordinator never evaluates — it supplies the
// system's clock and events, and the reevaluation stays in the SolvrCore
// refresher, where the model-layer integration tests inject controlled ones
// instead.

import AppKit
import Foundation
import SolvrCore
import Observation

/// Sends application lifecycle events to the refresh coordinator.
/// The default source watches NSWorkspace; tests supply a source they can
/// fire deterministically.
@MainActor
protocol ApplicationEventSource: AnyObject {
    /// Start watching for events; call `handler` on the main actor when one
    /// occurs.
    func start(handler: @escaping @MainActor (SheetRefreshTrigger) -> Void)
    /// Stop watching for events.
    func stop()
}

/// Observes NSWorkspace and emits a `.returningToApp` trigger when another
/// application becomes active. This is the coordinator's default event
/// source; it keeps the existing behavior of refreshing when the user
/// returns to Solvr.
@MainActor
final class WorkspaceApplicationEventSource: NSObject, ApplicationEventSource {
    private var handler: ((SheetRefreshTrigger) -> Void)?

    func start(handler: @MainActor @escaping (SheetRefreshTrigger) -> Void) {
        self.handler = handler
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didBecomeActive(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        handler = nil
    }

    @objc private func didBecomeActive(_: Notification) {
        handler?(.returningToApp)
    }
}

@MainActor
@Observable
final class SheetRefreshCoordinator: NSObject {
    /// The visible results, parallel to the sheet's lines, after the last
    /// reevaluation. View layers read these to draw the results beside
    /// their expressions; the changed indexes of each trigger stay on the
    /// outcome the app refreshes from.
    private(set) var results: [ExpressionResult] = []
    /// The sheet total's display text below the content, or nil when no
    /// total is available.
    private(set) var total: String?
    /// The cities the visible time-of-day conversions name. The view keeps
    /// their city data current through the shared service, and a city whose
    /// lookup failed is asked for again on the next trigger.
    private(set) var cityNames: Set<String> = []

    @ObservationIgnored private var refresher: SheetRefresher?
    @ObservationIgnored private var midnightTimer: Timer?
    @ObservationIgnored private var transitionTimer: Timer?
    @ObservationIgnored private var observingWorkspace = false
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let applicationEvents: ApplicationEventSource

    /// Asks the shared city data service for a lookup of the cities the
    /// visible results still cannot resolve. The view sets it; every trigger
    /// but an edit asks again, so a city whose earlier lookup failed turns
    /// from an error into a clock once the connection comes back. The
    /// service throttles repeat lookups itself.
    @ObservationIgnored var requestCityData: ((Set<String>) -> Void)?

    init(
        clock: @escaping () -> Date = Date.init,
        applicationEvents: ApplicationEventSource = WorkspaceApplicationEventSource()
    ) {
        self.clock = clock
        self.applicationEvents = applicationEvents
        super.init()
    }

    /// Opening a sheet evaluates it immediately — the opening evaluation
    /// counts as the sheet-opening trigger — and starts the local-midnight
    /// and daylight-saving observations, which matter only when a result
    /// follows the clock.
    func openSheet(_ sheetText: String, in evaluationContext: EvaluationContext) {
        let refresher = SheetRefresher(sheetText: sheetText, context: evaluationContext)
        self.refresher = refresher
        publish(refresher.results)
        scheduleMidnightTimer()
        scheduleTransitionTimer()
        observeWorkspace()
    }

    /// An edit hands the rewritten text over and reevaluates on the spot,
    /// so a line edited away loses its result immediately.
    func sheetTextEdited(_ newSheetText: String) {
        guard let outcome = refresher?.update(sheetText: newSheetText, now: clock()) else { return }
        publish(outcome.results)
        scheduleMidnightTimer()
        scheduleTransitionTimer()
    }

    func exchangeRatesChanged(_ snapshot: ExchangeRateSnapshot) {
        guard let outcome = refresher?.update(exchangeRates: snapshot, now: clock()) else { return }
        publish(outcome.results)
    }

    /// Fresh city data reaches the visible results without a text edit, and
    /// the zones the new conversions use begin following their
    /// daylight-saving transitions.
    func cityTimeZonesChanged(_ snapshot: CityTimeZoneSnapshot) {
        guard let outcome = refresher?.update(cityTimeZones: snapshot, now: clock()) else { return }
        publish(outcome.results)
        scheduleTransitionTimer()
    }

    /// A precision change from Settings reaches the open sheet at once; the
    /// sheet text stays untouched.
    func precisionChanged(displayPrecision: Int, cryptoPrecision: Int) {
        guard let outcome = refresher?.update(
            displayPrecision: displayPrecision,
            cryptoPrecision: cryptoPrecision,
            now: clock()
        ) else { return }
        publish(outcome.results)
    }

    /// The sheet closed; the coordinator releases the sheet's refresher
    /// and the local-midnight and daylight-saving timers.
    func closeSheet() {
        refresher = nil
        publish([])
        midnightTimer?.invalidate()
        midnightTimer = nil
        transitionTimer?.invalidate()
        transitionTimer = nil
    }

    /// Whether any visible result follows the clock, so a fresh context
    /// (a display-precision change, say) is worth reevaluating for too.
    var hasDateDependentResults: Bool {
        refresher?.hasDateDependentResults ?? false
    }

    /// Fires a refresh trigger using the coordinator's clock. Tests use
    /// this to drive local midnight and other lifecycle triggers
    /// deterministically without waiting for timers.
    func simulateRefresh(_ trigger: SheetRefreshTrigger) {
        fire(trigger)
    }

    // MARK: System events to reevaluation triggers

    private func observeWorkspace() {
        guard !observingWorkspace else { return }
        observingWorkspace = true
        applicationEvents.start { [weak self] trigger in
            guard let self else { return }
            MainActor.assumeIsolated { self.fire(trigger) }
        }
    }

    /// Local midnight in the system time zone: the refresher's context
    /// carries that zone, so the calendar matches the timer.
    @objc private func midnightFell(_: Timer) {
        MainActor.assumeIsolated {
            fire(.midnight)
            scheduleMidnightTimer()
        }
    }

    /// A time zone a visible conversion uses reached its next
    /// daylight-saving transition.
    @objc private func transitionFell(_: Timer) {
        MainActor.assumeIsolated {
            fire(.daylightSavingTransition)
            scheduleTransitionTimer()
        }
    }

    private func scheduleMidnightTimer() {
        midnightTimer?.invalidate()
        midnightTimer = nil
        guard let refresher, refresher.hasDateDependentResults else { return }
        let nextMidnight = refresher.dateCalendarContext.nextDate(
            after: clock(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        guard let nextMidnight else { return }
        let timer = Timer(
            fireAt: nextMidnight,
            interval: 0,
            target: self,
            selector: #selector(midnightFell(_:)),
            userInfo: nil,
            repeats: false
        )
        midnightTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The earliest next transition of the zones the visible conversions
    /// use; the revisits the triggers force keep it current, so a timer
    /// missed while the Mac slept leaves no stale clock.
    private func scheduleTransitionTimer() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        guard let refresher,
              let transition = refresher.nextDaylightSavingTransition(after: clock())
        else { return }
        let timer = Timer(
            fireAt: transition,
            interval: 0,
            target: self,
            selector: #selector(transitionFell(_:)),
            userInfo: nil,
            repeats: false
        )
        transitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fire(_ trigger: SheetRefreshTrigger) {
        guard refresher != nil, let outcome = refresher?.refresh(trigger, now: clock()) else { return }
        publish(outcome.results)
        // A reevaluation at any trigger can move the zones and the next
        // transition they schedule.
        scheduleTransitionTimer()
        // An edit already asked for its cities; a clock or app trigger asks
        // again, so a city whose lookup failed is retried without a text
        // change and a cached city is refreshed when the source answers.
        requestCityData?(cityNames)
    }

    /// Hands the fresh results to the view, with the cities they name, so
    /// the view can look up and refresh their city data.
    private func publish(_ fresh: [ExpressionResult]) {
        results = fresh
        total = refresher?.total
        cityNames = refresher?.cityNames ?? []
    }
}

private extension SheetRefresher {
    /// The evaluation context's calendar, which already carries the
    /// context's time zone — the system's, for the app.
    var dateCalendarContext: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        return calendar
    }
}
