// The application side of the date-dependent results lifecycle (ADK-230).
// One coordinator owns the refresher for the open sheet and translates the
// real system events into the model layer's reevaluation triggers: an edit,
// local midnight in the system time zone, sheet opening, and returning to
// the app. The coordinator never evaluates — it supplies the system's
// clock and events, and the reevaluation stays in the NumeCore refresher,
// where the model-layer integration tests inject controlled ones instead.

import AppKit
import Foundation
import NumeCore
import Observation

@MainActor
@Observable
final class SheetRefreshCoordinator: NSObject {
    /// The visible results, parallel to the sheet's lines, after the last
    /// reevaluation. View layers read these to draw the results beside
    /// their expressions; the changed indexes of each trigger stay on the
    /// outcome the app refreshes from.
    private(set) var results: [ExpressionResult] = []
    /// The city names the visible results could not resolve because the
    /// city data held no answer for them yet (ADK-250). The view looks them
    /// up through the shared city data service.
    private(set) var uncachedCityNames: Set<String> = []

    @ObservationIgnored private var refresher: SheetRefresher?
    @ObservationIgnored private var midnightTimer: Timer?
    @ObservationIgnored private var observingWorkspace = false

    /// Opening a sheet evaluates it immediately — the opening evaluation
    /// counts as the sheet-opening trigger — and starts the local-midnight
    /// observation, which matters only when a result follows the clock.
    func openSheet(_ sheetText: String, in evaluationContext: EvaluationContext) {
        let refresher = SheetRefresher(sheetText: sheetText, context: evaluationContext)
        self.refresher = refresher
        publish(refresher.results)
        scheduleMidnightTimer()
        observeWorkspace()
    }

    /// An edit hands the rewritten text over and reevaluates on the spot,
    /// so a line edited away loses its result immediately.
    func sheetTextEdited(_ newSheetText: String) {
        guard let outcome = refresher?.update(sheetText: newSheetText, now: Date()) else { return }
        publish(outcome.results)
        scheduleMidnightTimer()
    }

    func exchangeRatesChanged(_ snapshot: ExchangeRateSnapshot) {
        guard let outcome = refresher?.update(exchangeRates: snapshot, now: Date()) else { return }
        publish(outcome.results)
    }

    /// Fresh city data reaches the visible results without a text edit
    /// (ADK-250).
    func cityTimeZonesChanged(_ snapshot: CityTimeZoneSnapshot) {
        guard let outcome = refresher?.update(cityTimeZones: snapshot, now: Date()) else { return }
        publish(outcome.results)
    }

    /// The sheet closed; the coordinator releases the sheet's refresher
    /// and the local-midnight timer.
    func closeSheet() {
        refresher = nil
        publish([])
        midnightTimer?.invalidate()
        midnightTimer = nil
    }

    /// Whether any visible result follows the clock, so a fresh context
    /// (a display-precision change, say) is worth reevaluating for too.
    var hasDateDependentResults: Bool {
        refresher?.hasDateDependentResults ?? false
    }

    // MARK: System events to reevaluation triggers

    private func observeWorkspace() {
        guard !observingWorkspace else { return }
        observingWorkspace = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidBecomeActive(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    /// Returning to the app recalculates the date-dependent results
    /// without a text edit.
    @objc private func workspaceDidBecomeActive(_: Notification) {
        MainActor.assumeIsolated {
            fire(.returningToApp)
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

    private func scheduleMidnightTimer() {
        midnightTimer?.invalidate()
        midnightTimer = nil
        guard let refresher, refresher.hasDateDependentResults else { return }
        let nextMidnight = refresher.dateCalendarContext.nextDate(
            after: Date(),
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

    private func fire(_ trigger: SheetRefreshTrigger) {
        guard refresher != nil, let outcome = refresher?.refresh(trigger, now: Date()) else { return }
        publish(outcome.results)
    }

    /// Hands the fresh results to the view, with the cities they could not
    /// resolve yet so the view can look them up (ADK-250).
    private func publish(_ fresh: [ExpressionResult]) {
        results = fresh
        uncachedCityNames = refresher?.uncachedCityNames ?? []
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
