import Foundation
import Core
@testable import Solvr
import Testing

// AppTests exercises the app-owned refresh coordinator without UI
// automation: a controllable clock and a test event source drive local
// midnight and the return-to-app refresh deterministically.

@MainActor
final class TestApplicationEventSource: ApplicationEventSource {
    private var handler: ((SheetRefreshTrigger) -> Void)?

    func start(handler: @MainActor @escaping (SheetRefreshTrigger) -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func fire(_ trigger: SheetRefreshTrigger) {
        handler?(trigger)
    }
}

struct SheetRefreshCoordinatorTests {
    private func clock(
        _ description: String,
        timeZone: TimeZone = TimeZone(identifier: "America/Sao_Paulo")!
    ) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: description)!
    }

    private func context(now: Date) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: "en_US",
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: now,
            displayPrecision: 2
        )
    }

    @Test @MainActor
    func localMidnightFlipsDaysUntilAndReturningToAppKeepsTheNewCount() {
        let eventSource = TestApplicationEventSource()
        var now = clock("2026-10-30 09:00:00")
        let coordinator = SheetRefreshCoordinator(
            clock: { now },
            applicationEvents: eventSource
        )

        coordinator.openSheet(
            "days until 31 Mar 2027",
            in: context(now: now)
        )
        #expect(coordinator.results[0].display == "152 days")

        now = clock("2026-10-31 00:00:00")
        coordinator.simulateRefresh(.midnight)
        #expect(coordinator.results[0].display == "151 days")

        now = clock("2026-10-31 20:15:00")
        eventSource.fire(.returningToApp)
        #expect(coordinator.results[0].display == "151 days")
    }
}
