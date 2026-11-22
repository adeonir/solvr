import Foundation
@testable import SolvrCore
import Testing

// `15 min` is a duration of 15 minutes rather than a minimum-function
// call, each unit accepts its standard abbreviation and its full name
// singular and plural, `in` converts numerically with ten displayed
// decimal places, and `to timespan` decomposes in chains that compose in
// their written order, with one sign over the whole duration and
// preserved fractions. A date-free month counts 30 days, on any clock.
// Locale, display precision, time zone, and clock are fixed per fixture.

struct DurationTests {
    private func context(
        locale identifier: String = "pt_BR",
        precision: Int = 10,
        now: Date = Date(timeIntervalSince1970: 1_791_926_400) // 2026-10-30 00:00 UTC
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: now,
            displayPrecision: precision
        )
    }

    private func result(_ source: String, context: EvaluationContext? = nil) -> ExpressionResult {
        evaluate(sheetText: source, context: context ?? self.context())[0]
    }

    private func display(_ source: String, precision: Int = 10) -> String? {
        result(source, context: context(precision: precision)).display
    }

    // MARK: Acceptance examples

    @Test(arguments: [
        ("145 mins to timespan", "2 hours 25 min"),
        ("1500 mins in days", "1,0416666667 days"),
        ("1500 mins to timespan", "1 day 1 hour"),
        ("1500 mins in days to timespan", "1 day 1 hour"),
        ("1500 mins to timespan in days", "1,0416666667 days"),
        ("-1500 mins to timespan", "-1 day 1 hour"),
        ("90,5 s to timespan", "1 min 30,5 s"),
        ("1 month in days", "30 days"),
        ("round(1 month in days)", "30 days"),
    ])
    func acceptanceExamples(_ source: String, _ expected: String) {
        let conversion = result(source)
        #expect(conversion.kind == .expression)
        #expect(conversion.diagnostic == nil)
        #expect(conversion.display == expected)
    }

    // MARK: `15 min` is a duration, not a minimum call

    @Test
    func fifteenMinutesIsADurationTheValueAnchoringOnSeconds() {
        let conversion = result("15 min")
        #expect(conversion.kind == .expression)
        #expect(conversion.diagnostic == nil)
        #expect(conversion.value == .decimal(900))
        #expect(conversion.display == "15 min")
    }

    @Test
    func minimumCallAndDurationStayDistinct() {
        let results = evaluate(sheetText: "min(1,5; 2,5)\n15 min", context: context())
        #expect(results[0].display == "1,5")
        #expect(results[1].display == "15 min")
    }

    // MARK: Abbreviations and full names accept alike

    @Test(arguments: [
        (["15 min", "15 mins", "15 minute", "15 minutes"], "15 min"),
        (["90 s", "90 second", "90 seconds"], "90 s"),
        (["2 h", "2 hour", "2 hours"], "2 hours"),
        (["3 d", "3 day", "3 days"], "3 days"),
        (["1 week", "1 weeks"], "1 week"),
        (["1 month", "1 months"], "1 month"),
        (["5 year", "5 years"], "5 years"),
    ])
    func abbreviationsAndFullNamesAcceptAlike(_ sheets: [String], _ expected: String) {
        for sheet in sheets {
            let conversion = result(sheet)
            #expect(conversion.diagnostic == nil)
            #expect(conversion.display == expected)
        }
    }

    /// Unit lookup is not case-sensitive, like every unit's aliases.
    @Test
    func unitAliasesMatchAnyCase() {
        let results = evaluate(
            sheetText: "15 Minutes to timespan\n90 Seconds to timespan",
            context: context()
        )
        #expect(results[0].display == "15 min")
        #expect(results[1].display == "1 min 30 s")
    }

    /// No alias beyond the standard abbreviation and the full names:
    /// an unaccepted unit word leaves the line with no usable result.
    @Test(arguments: ["15 sec in mins", "2 yrs in days", "1 fortnight in weeks"])
    func wordsNoDurationUnitAcceptsStayInvalidSyntax(_ source: String) {
        let conversion = result(source)
        #expect(conversion.kind == .expression)
        #expect(conversion.value == nil)
        #expect(conversion.diagnostic == .syntax)
        #expect(conversion.diagnostic?.message == "Invalid syntax")
    }

    // MARK: Numeric conversions

    @Test(arguments: [
        ("1500 mins in hours", "25 hours"),
        ("145 mins in hours", "2,4166666667 hours"),
        ("12 months in days", "360 days"),
        ("1 year in days", "365 days"),
        ("2 weeks in hours", "336 hours"),
        ("24 hours in days", "1 day"),
        ("-1500 mins in days", "-1,0416666667 days"),
    ])
    func numericConversions(_ source: String, _ expected: String) {
        #expect(display(source) == expected)
    }

    /// Conversions never round the duration value: a chain that converts
    /// twice still shows the value the written quantity carries.
    @Test
    func chainedConversionsKeepTheSecondsValue() {
        let results = evaluate(sheetText: "1500 mins in days in hours", context: context())
        #expect(results[0].diagnostic == nil)
        #expect(results[0].value == .decimal(90000))
        #expect(results[0].display == "25 hours")
    }

    /// A conversion is numeric and reusable inside arithmetic: the line
    /// counts the seconds magnitude the conversion contributes, and
    /// shows a plain number, like any quantity conversion.
    @Test
    func convertedDurationsKeepTheirNumericMeaningInsideArithmetic() {
        let result = evaluate(sheetText: "1500 mins in hours times 4", context: context())
        #expect(result[0].diagnostic == nil)
        #expect(result[0].value == .decimal(360_000))
        #expect(result[0].display == "360.000")
    }

    // MARK: Display precision changes formatting, not the value

    @Test
    func displayPrecisionChangesTheDurationFormattingNotTheValue() {
        let results = evaluate(
            sheetText: "1500 mins in days\nx = 1500 mins in days\nx to timespan",
            context: context(precision: 2)
        )
        #expect(results[0].display == "1,04 days")
        #expect(results[0].value == .decimal(90000))
        // The value keeps the seconds magnitude, so the timespan form at
        // low precision still holds the day and the hour.
        #expect(results[2].display == "1 day 1 hour")
    }

    // MARK: Duration arithmetic composes into timespans

    @Test(arguments: [
        ("(45 min + 30 s) to timespan", "45 min 30 s"),
        ("(2 h - 30 min) to timespan", "1 hour 30 min"),
        ("3 days in hours to timespan", "3 days"),
    ])
    func arithmeticComposesIntoTheTimespan(_ source: String, _ expected: String) {
        #expect(display(source) == expected)
    }

    // MARK: Timespans of other units

    @Test(arguments: [
        ("90 min to timespan", "1 hour 30 min"),
        ("1 week to timespan", "7 days"),
        ("1 year to timespan", "365 days"),
        ("0,5 min to timespan", "30 s"),
        ("7200 s to timespan", "2 hours"),
    ])
    func timespansOfOtherUnits(_ source: String, _ expected: String) {
        #expect(display(source) == expected)
    }

    // MARK: Signs and fractions

    @Test(arguments: [
        ("-90,5 s to timespan", "-1 min 30,5 s"),
        ("-1 month in days", "-30 days"),
        ("-(145 mins) to timespan", "-2 hours 25 min"),
    ])
    func negativeDurationsKeepOneSignOverTheWholeDuration(_ source: String, _ expected: String) {
        #expect(display(source) == expected)
    }

    @Test
    func fractionalSecondsPreserveTheirFraction() throws {
        let conversion = result("90,5 s to timespan")
        #expect(try conversion.value == .decimal(Decimal(exact: "90.5")))
        #expect(conversion.display == "1 min 30,5 s")
    }

    // MARK: Date-free months count 30 days

    @Test(arguments: [
        (Date(timeIntervalSince1970: 1_791_926_400), "30 days"), // Oct 2026
        (Date(timeIntervalSince1970: 1_767_225_600), "30 days") // Jan 2026
    ])
    func monthConversionsAreClockIndependent(now: Date, _ expected: String) {
        let results = evaluate(
            sheetText: "1 month in days\nround(1 month in days)\n1 month to timespan",
            context: context(now: now)
        )
        for result in results {
            #expect(result.diagnostic == nil)
            #expect(result.display == expected)
        }
    }

    // MARK: Labels ignore their own words

    @Test
    func labelsLeaveTheDurationFormToEvaluate() {
        let result = evaluate(sheetText: "reunião 90 min to timespan", context: context())
        #expect(result[0].diagnostic == nil)
        #expect(result[0].display == "1 hour 30 min")
    }

    // MARK: Incomplete duration forms show no message

    @Test(arguments: ["1500 mins to", "90 s in", "145 mins in days to"])
    func cutShortDurationFormsStayIncomplete(_ source: String) {
        let conversion = result(source)
        #expect(conversion.kind == .incomplete)
        #expect(conversion.value == nil)
        #expect(conversion.display == nil)
        #expect(conversion.diagnostic == nil)
    }

    /// A word the timespan form does not complete is invalid where it fits.
    @Test
    func unfinishableTimespanFormIsInvalidSyntax() {
        let conversion = result("1500 mins to hours")
        #expect(conversion.diagnostic == .syntax)
    }
}
