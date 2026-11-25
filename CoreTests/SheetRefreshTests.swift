@testable import Core
import Foundation
import Testing

struct SheetRefreshTests {
    private func context(
        locale identifier: String = "en_US",
        timeZone: TimeZone = TimeZone(identifier: "America/Sao_Paulo")!,
        now: Date
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: timeZone,
            now: now,
            displayPrecision: 2
        )
    }

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

    private func refresher(_ sheetText: String, now: String) -> SheetRefresher {
        SheetRefresher(sheetText: sheetText, context: context(now: clock(now)))
    }

    @Test
    func localMidnightFlipsTheDaysUntil() {
        var refresher = refresher("days until 31 Mar 2027", now: "2026-10-30 09:00:00")
        #expect(refresher.results[0].display == "152 days")

        let outcome = refresher.refresh(.midnight, now: clock("2026-10-31 00:00:00"))
        #expect(outcome.results[0].display == "151 days")
        #expect(outcome.results[0].value == .difference(151))
        #expect(outcome.changedIndexes == Set([0]))
        #expect(outcome.results[0].kind == .expression)
        #expect(outcome.results[0].diagnostic == nil)
    }

    @Test
    func sheetOpeningRefreshesAgainstTheCurrentDate() {
        var refresher = refresher("days until 31 Mar 2027", now: "2026-10-30 09:00:00")
        let outcome = refresher.refresh(.sheetOpening, now: clock("2026-10-31 18:30:00"))
        #expect(outcome.results[0].display == "151 days")
        #expect(outcome.changedIndexes == Set([0]))
    }

    @Test
    func returningToAppRefreshesWithoutATextEdit() {
        var refresher = refresher("days until 31 Mar 2027", now: "2026-10-30 09:00:00")
        let textBefore = refresher.sheetText
        let outcome = refresher.refresh(.returningToApp, now: clock("2026-10-31 20:15:00"))
        #expect(refresher.sheetText == textBefore)
        #expect(outcome.results[0].display == "151 days")
        #expect(outcome.changedIndexes == Set([0]))
    }

    @Test
    func aTriggerAtTheSameLocalDateChangesNothing() {
        var refresher = refresher("days until 31 Mar 2027", now: "2026-10-30 09:00:00")
        let before = refresher.results
        let outcome = refresher.refresh(.midnight, now: clock("2026-10-30 09:00:00"))
        #expect(outcome.changedIndexes.isEmpty)
        #expect(outcome.results == before)
    }

    @Test
    func plainArithmeticNeedsNoMidnightRecheck() {
        var refresher = refresher("4 * 5\n2 + 2", now: "2026-10-30 09:00:00")
        #expect(refresher.hasDateDependentResults == false)

        let outcome = refresher.refresh(.midnight, now: clock("2026-10-31 00:00:00"))
        #expect(outcome.changedIndexes.isEmpty)
    }

    @Test
    func dateDependenceFollowsTheTypedDateForms() {
        let sheet = """
        # Renewals
        compras do mês
        days until 31 Mar
        days until 31 Mar 2027
        31 Mar
        1 Nov 2026
        monday in 3 weeks
        31 Jan + 1 month
        31 Jan 2027 + 1 month
        fromunix(1446587186)
        4 * 5
        """
        let refresher = refresher(sheet, now: "2026-10-30 09:00:00")
        #expect(refresher.hasDateDependentResults == true)
        #expect(refresher.dateDependentIndexes == Set([2, 3, 4, 6, 7]))
    }

    @Test
    func refreshedResultsEqualAFreshEvaluation() {
        var refresher = refresher(
            "days until 31 Mar 2027\n4 * 5\ncompras 31 Mar 2027 + 1 month",
            now: "2026-10-30 09:00:00"
        )
        let outcome = refresher.refresh(.midnight, now: clock("2026-10-31 00:00:00"))
        let context = context(now: clock("2026-10-31 00:00:00"))
        #expect(outcome.results == evaluate(sheetText: refresher.sheetText, context: context))
    }

    @Test
    func anIncompleteEditRemovesTheObsoleteResult() {
        var refresher = refresher("days until 31 Mar 2027", now: "2026-10-30 09:00:00")
        #expect(refresher.results[0].display == "152 days")

        let outcome = refresher.update(sheetText: "days until ", now: clock("2026-10-30 12:00:00"))
        #expect(outcome.changedIndexes == Set([0]))
        #expect(outcome.results[0].value == nil)
        #expect(outcome.results[0].display == nil)

        let after = refresher.refresh(.midnight, now: clock("2026-10-31 00:00:00"))
        #expect(after.results[0].value == nil)
        #expect(after.results[0].display == nil)
        #expect(after.changedIndexes.isEmpty)
    }

    @Test
    func deletingTheLineRemovesItsResult() {
        var refresher = refresher("days until 31 Mar 2027\n4 * 5", now: "2026-10-30 09:00:00")
        #expect(refresher.results.count == 2)

        let outcome = refresher.update(sheetText: "4 * 5", now: clock("2026-10-30 12:00:00"))
        #expect(outcome.results.count == 1)
        #expect(outcome.results[0].display == "20")
        #expect(outcome.changedIndexes == Set([0]))
    }

    @Test
    func anEditedSheetKeepsRefreshingThroughTheTriggers() {
        var refresher = refresher("days until 31 Mar 2027", now: "2026-10-30 09:00:00")
        refresher.update(sheetText: "days until 31 Dec 2027", now: clock("2026-10-30 12:00:00"))
        #expect(refresher.results[0].display == "427 days")

        let outcome = refresher.refresh(.sheetOpening, now: clock("2026-10-31 09:00:00"))
        #expect(refresher.results[0].display == "426 days")
        #expect(outcome.changedIndexes == Set([0]))
    }
}
