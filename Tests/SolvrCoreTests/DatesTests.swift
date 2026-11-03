import Foundation
@testable import SolvrCore
import Testing

// Complete-sheet tests for calendar dates, calendar-day differences,
// weekday weeks, calendar-month shifts, and Unix timestamps (ADK-229).
// Locale, time zone, display precision, and clock are fixed per fixture
// through the EvaluationContext, per ADR-005.

struct DatesTests {
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

    private func calendarDate(
        year: Int, month: Int, day: Int,
        timeZone: TimeZone = TimeZone(identifier: "America/Sao_Paulo")!
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Acceptance examples (30 October 2026, system time zone)

    @Test(arguments: [
        ("days until 31 Mar", "152 days"),
        ("days until 31 Mar 2027", "152 days"),
        ("days until 29 Oct 2026", "-1 day"),
        ("monday in 3 weeks", "16 November 2026"),
        ("31 Mar", "31 March 2026"),
    ])
    func individualExpressions(_ source: String, _ expected: String) {
        let results = evaluate(
            sheetText: source,
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results.count == 1)
        #expect(results[0].kind == .expression)
        #expect(results[0].diagnostic == nil)
        #expect(results[0].display == expected)
    }

    // MARK: Calendar-day differences stay separate from magnitudes

    @Test
    func differenceCarriesItsOwnValue() {
        let results = evaluate(
            sheetText: "days until 31 Mar\ndays until 29 Oct 2026",
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[0].value == .difference(152))
        #expect(results[1].value == .difference(-1))
    }

    @Test
    func weekdayCarriesItsCalendarValue() {
        let result = evaluate(
            sheetText: "monday in 3 weeks",
            context: context(now: clock("2026-10-30 09:00:00"))
        )[0]
        #expect(result.value == .date(calendarDate(year: 2026, month: 11, day: 16)))
    }

    // MARK: Next occurrence, today counts as zero

    @Test
    func todayCountsAsZero() {
        let result = evaluate(
            sheetText: "days until 31 Mar",
            context: context(now: clock("2027-03-31 12:00:00"))
        )[0]
        #expect(result.display == "0 days")
        #expect(result.value == .difference(0))
    }

    @Test
    func passedDateRollsToNextYear() {
        let result = evaluate(
            sheetText: "days until 31 Mar",
            context: context(now: clock("2026-04-01 09:00:00"))
        )[0]
        #expect(result.display == "364 days")
    }

    // MARK: Leap day without a year

    @Test
    func bareLeapDaySelectsTheNextValidLeapDay() {
        let result = evaluate(
            sheetText: "days until 29 Feb",
            context: context(now: clock("2027-03-01 09:00:00"))
        )[0]
        #expect(result.display == "365 days")
    }

    @Test
    func leapDayTodayCountsAsZero() {
        let result = evaluate(
            sheetText: "days until 29 Feb",
            context: context(now: clock("2028-02-29 09:00:00"))
        )[0]
        #expect(result.display == "0 days")
    }

    @Test
    func bareLeapDayDateResolvesToTheNextLeapYear() {
        let result = evaluate(
            sheetText: "29 Feb",
            context: context(now: clock("2026-10-30 09:00:00"))
        )[0]
        #expect(result.display == "29 February 2028")
    }

    @Test
    func invalidExplicitDateStaysLocalToItsLine() {
        let results = evaluate(
            sheetText: "1 + 1\ndays until 29 Feb 2027\n2 * 3",
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[0].display == "2")
        #expect(results[0].diagnostic == nil)
        #expect(results[1].diagnostic?.message == "Invalid date")
        #expect(results[1].value == nil)
        #expect(results[1].display == nil)
        #expect(results[2].display == "6")
        #expect(results[2].diagnostic == nil)
    }

    // MARK: One calendar day away, independent of the hours

    @Test
    func tomorrowStaysOneCalendarDayAwayRegardlessOfTheHours() {
        // 23:00 on 30 October: the next day difference runs midnight to
        // midnight, so the hour of the clock never shows.
        let result = evaluate(
            sheetText: "days until 31 Oct 2026",
            context: context(now: clock("2026-10-30 23:00:00"))
        )[0]
        #expect(result.display == "1 day")
        #expect(result.value == .difference(1))
    }

    @Test
    func daylightSavingShiftKeepsCalendarDays() throws {
        // The New York daylight-saving transition ends 2026-11-01; the
        // difference through that night still counts whole calendar days.
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let results = evaluate(
            sheetText: "days until 1 Nov 2026\ndays until 2 Nov 2026",
            context: context(
                timeZone: zone,
                now: clock("2026-10-30 15:00:00", timeZone: zone)
            )
        )
        #expect(results[0].display == "2 days")
        #expect(results[1].display == "3 days")
    }

    // MARK: Weekdays in weeks

    @Test
    func weekdayEdgeKeepsTheWeekdayOfTheFarWeek() {
        let results = evaluate(
            sheetText: "monday in 1 week\nmonday in 0 weeks",
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[0].display == "2 November 2026")
        #expect(results[1].display == "26 October 2026")
    }

    // MARK: Calendar-month shift with end-of-month clamping

    @Test(arguments: [
        ("2026-05-14 09:00:00", "31 Jan + 1 month", "28 February 2026"),
        ("2024-05-14 09:00:00", "31 Jan + 1 month", "29 February 2024"),
        ("2026-05-14 09:00:00", "31 Jan 2027 + 1 month", "28 February 2027"),
        ("2026-05-14 09:00:00", "31 Mar 2027 - 1 month", "28 February 2027"),
        ("2026-05-14 09:00:00", "31 Jan + 2 months", "31 March 2026"),
    ])
    func monthEndClampsToTheLastDay(_ now: String, _ source: String, _ expected: String) {
        let result = evaluate(
            sheetText: source,
            context: context(now: clock(now))
        )[0]
        #expect(result.display == expected)
        #expect(result.diagnostic == nil)
    }

    @Test
    func dateArithmeticWithAGenericNumberStaysSyntax() {
        let result = evaluate(
            sheetText: "31 Jan + 1",
            context: context(now: clock("2026-05-14 09:00:00"))
        )[0]
        #expect(result.diagnostic?.message == "Invalid syntax")
    }

    // MARK: Unix timestamps in the context time zone

    @Test
    func fromunixCarriesTheInstantAndShowsTheContextZone() throws {
        let saoPaulo = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let result = evaluate(
            sheetText: "fromunix(1446587186)",
            context: context(timeZone: saoPaulo, now: clock("2026-10-30 09:00:00"))
        )[0]
        // The exact UTC instant is the value; the display applies the
        // context's time zone ( São Paulo was at UTC-2 that day).
        #expect(result.value == .date(Date(timeIntervalSince1970: 1_446_587_186)))
        #expect(result.display == "3 November 2015 19:46:26")

        let lisbon = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let lisbonResult = evaluate(
            sheetText: "fromunix(1446587186)",
            context: context(timeZone: lisbon, now: clock("2026-10-30 09:00:00"))
        )[0]
        #expect(lisbonResult.display == "3 November 2015 21:46:26")
    }

    @Test
    func fromunixReadsExpressionsAndErrorsStayLocal() {
        let results = evaluate(
            sheetText: "seconds = 1446587186\nfromunix(seconds)\nx = fromunix(1.5)",
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[0].display == "1,446,587,186")
        #expect(results[1].display == "3 November 2015 19:46:26")
        #expect(results[2].diagnostic?.message == "Invalid syntax")
        #expect(results[2].value == nil)
    }

    // MARK: Complete sheet with results beside the expressions

    @Test
    func sheetShowsDatesBesideTheirExpressions() {
        let sheet = """
        # Renewals
        days until 31 Mar
        monday in 3 weeks
        31 Jan + 1 month
        fromunix(1446587186)
        """
        let results = evaluate(
            sheetText: sheet,
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results.count == 5)
        #expect(results[0].kind == .heading)
        let evaluated = Array(results.dropFirst())
        #expect(evaluated.allSatisfy { $0.kind == .expression && $0.diagnostic == nil })
        #expect(evaluated.map(\.display) == [
            "152 days",
            "16 November 2026",
            "28 February 2026",
            "3 November 2015 19:46:26"
        ])
    }

    @Test
    func habitNoteStaysATextLineAndLabelPrefixWorks() {
        let results = evaluate(
            sheetText: "renovar conta\ndays until 31 Mar\nlabel 31 Jan + 1 month",
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[0].kind == .textLine)
        #expect(results[0].display == nil)
        #expect(results[1].display == "152 days")
        #expect(results[2].display == "28 February 2026")
    }

    // MARK: Assignments and references keep date values (ADK-258)

    @Test(arguments: [
        "x = days until 31 Mar",
        "x = (days until 31 Mar)",
    ])
    func assignedDifferenceShowsTheLineDisplay(_ source: String) {
        let results = evaluate(
            sheetText: source,
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[0].diagnostic == nil)
        #expect(results[0].display == "152 days")
        #expect(results[0].value == .difference(152))
    }

    @Test
    func referencedDifferenceKeepsValueAndDayMeasure() {
        let results = evaluate(
            sheetText: "x = days until 31 Mar\nx",
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[1].diagnostic == nil)
        #expect(results[1].display == "152 days")
        #expect(results[1].value == .difference(152))
        #expect(results[1].measure == .time(Duration.day))
    }

    @Test(arguments: [
        "31 Jan",
        "fromunix(1700000000)",
    ])
    func assignedAndReferencedDatesShowTheLineDisplay(_ source: String) {
        let now = context(now: clock("2026-10-30 09:00:00"))
        let lineDisplay = evaluate(sheetText: source, context: now)[0].display
        let results = evaluate(sheetText: "x = \(source)\nx", context: now)
        #expect(results[0].display == lineDisplay)
        #expect(results[1].display == lineDisplay)
        #expect(results[1].diagnostic == nil)
    }

    @Test
    func failedAssignmentLeavesItsReferenceDependent() {
        let results = evaluate(
            sheetText: "x = days until 30 Feb\nx",
            context: context(now: clock("2026-10-30 09:00:00"))
        )
        #expect(results[0].diagnostic != nil)
        #expect(results[1].diagnostic == .dependsOnError)
    }

    @Test
    func assignedDifferenceCountsInTheTotalOncePerLine() {
        let now = context(now: clock("2026-10-30 09:00:00"))
        let referenced = sheetTotal(
            of: evaluate(sheetText: "x = days until 31 Mar\nx", context: now),
            context: now
        )
        let plain = sheetTotal(
            of: evaluate(sheetText: "days until 31 Mar\ndays until 31 Mar", context: now),
            context: now
        )
        #expect(referenced?.value == plain?.value)
        #expect(referenced?.display == plain?.display)
        let single = sheetTotal(of: evaluate(sheetText: "x = days until 31 Mar", context: now), context: now)
        let singlePlain = sheetTotal(of: evaluate(sheetText: "days until 31 Mar", context: now), context: now)
        #expect(single?.display == singlePlain?.display)
    }
}
