import AppKit
import Core
import Foundation
import Observation

@MainActor
protocol ApplicationEventSource: AnyObject {
    func start(handler: @escaping @MainActor (SheetRefreshTrigger) -> Void)
    func stop()
}

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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        handler = nil
    }

    @objc private func didBecomeActive(_: Notification) {
        handler?(.returningToApp)
    }
}

@MainActor
@Observable
final class SheetRefreshCoordinator: NSObject {
    private(set) var results: [ExpressionResult] = []
    private(set) var total: String?
    private(set) var cityNames: Set<String> = []

    @ObservationIgnored private var refresher: SheetRefresher?
    @ObservationIgnored private var midnightTimer: Timer?
    @ObservationIgnored private var transitionTimer: Timer?
    @ObservationIgnored private var observingWorkspace = false
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let applicationEvents: ApplicationEventSource

    @ObservationIgnored var requestCityData: ((Set<String>) -> Void)?

    init(
        clock: @escaping () -> Date = Date.init,
        applicationEvents: ApplicationEventSource = WorkspaceApplicationEventSource()
    ) {
        self.clock = clock
        self.applicationEvents = applicationEvents
        super.init()
    }

    func openSheet(_ sheetText: String, in evaluationContext: EvaluationContext) {
        let refresher = SheetRefresher(sheetText: sheetText, context: evaluationContext)
        self.refresher = refresher
        publish(refresher.results)
        scheduleMidnightTimer()
        scheduleTransitionTimer()
        observeWorkspace()
    }

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

    func cityTimeZonesChanged(_ snapshot: CityTimeZoneSnapshot) {
        guard let outcome = refresher?.update(cityTimeZones: snapshot, now: clock()) else { return }
        publish(outcome.results)
        scheduleTransitionTimer()
    }

    func precisionChanged(displayPrecision: Int, cryptoPrecision: Int) {
        guard let outcome = refresher?.update(
            displayPrecision: displayPrecision,
            cryptoPrecision: cryptoPrecision,
            now: clock()
        ) else { return }
        publish(outcome.results)
    }

    func closeSheet() {
        refresher = nil
        publish([])
        midnightTimer?.invalidate()
        midnightTimer = nil
        transitionTimer?.invalidate()
        transitionTimer = nil
    }

    var hasDateDependentResults: Bool {
        refresher?.hasDateDependentResults ?? false
    }

    func simulateRefresh(_ trigger: SheetRefreshTrigger) {
        fire(trigger)
    }

    private func observeWorkspace() {
        guard !observingWorkspace else { return }
        observingWorkspace = true
        applicationEvents.start { [weak self] trigger in
            guard let self else { return }
            MainActor.assumeIsolated { self.fire(trigger) }
        }
    }

    @objc private func midnightFell(_: Timer) {
        MainActor.assumeIsolated {
            fire(.midnight)
            scheduleMidnightTimer()
        }
    }

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
        scheduleTransitionTimer()
        requestCityData?(cityNames)
    }

    private func publish(_ fresh: [ExpressionResult]) {
        results = fresh
        total = refresher?.total
        cityNames = refresher?.cityNames ?? []
    }
}

private extension SheetRefresher {
    var dateCalendarContext: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        return calendar
    }
}
