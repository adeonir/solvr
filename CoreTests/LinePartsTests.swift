@testable import Core
import Foundation
import Testing

// The parts of sheet lines are read through the public SolvrCore API only.

struct LinePartsTests {
    private let context = EvaluationContext(
        localeIdentifier: "en_US",
        timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
        now: Date(timeIntervalSince1970: 1_791_926_400),
        displayPrecision: 10
    )

    struct Part: Equatable, CustomStringConvertible {
        let text: String
        let kind: SyntaxKind
        var description: String {
            "\(text):\(kind)"
        }
    }

    /// The parts of the last line of the sheet text, as the text each covers.
    private func parts(_ sheetText: String) -> [Part] {
        let lines = sheetText.components(separatedBy: "\n")
        let all = lineParts(sheetText: sheetText, context: context)
        #expect(all.count == lines.count)
        let line = lines[lines.count - 1]
        let utf16 = Array(line.utf16)
        return (all.last ?? []).map { part in
            Part(text: String(decoding: utf16[part.range], as: UTF16.self), kind: part.kind)
        }
    }

    @Test func aWholeLineCommentIsOneComment() {
        #expect(parts("// rent") == [Part(text: "// rent", kind: .comment)])
    }

    @Test func aHeadingIsOneHeading() {
        #expect(parts("## Budget") == [Part(text: "## Budget", kind: .heading)])
    }

    @Test func aHashWithoutASpaceOrSevenHashesIsNoHeading() {
        #expect(parts("#Budget").isEmpty)
        #expect(parts("####### Budget").isEmpty)
    }

    @Test func aCommentAfterAnExpressionColorsFromTheSlashes() {
        #expect(parts("compras 2 + 3 // split") == [
            Part(text: "compras", kind: .muted),
            Part(text: "2", kind: .value),
            Part(text: "+", kind: .muted),
            Part(text: "3", kind: .value),
            Part(text: "// split", kind: .comment)
        ])
    }

    @Test func aDefinedNameIsAVariableAndTimesIsAnOperator() {
        #expect(parts("price = $8 times 3") == [
            Part(text: "price", kind: .name),
            Part(text: "=", kind: .muted),
            Part(text: "$8", kind: .value),
            Part(text: "times", kind: .muted),
            Part(text: "3", kind: .value)
        ])
    }

    @Test func aLaterReferenceToADefinedNameIsAVariable() {
        #expect(parts("price = 5\nprice + 1") == [
            Part(text: "price", kind: .name),
            Part(text: "+", kind: .muted),
            Part(text: "1", kind: .value)
        ])
    }

    @Test(arguments: [("16px in em", "16px", "em"), ("10 ft in m", "10 ft", "m")])
    func aQuantityIsOneUnitPart(line: String, quantity: String, target: String) {
        #expect(parts(line) == [
            Part(text: quantity, kind: .unit),
            Part(text: "in", kind: .muted),
            Part(text: target, kind: .unit)
        ])
    }

    @Test func functionsAndConstants() {
        #expect(parts("sqrt(16) + pi") == [
            Part(text: "sqrt", kind: .name),
            Part(text: "16", kind: .value),
            Part(text: "+", kind: .muted),
            Part(text: "pi", kind: .name)
        ])
    }

    @Test func minBeforeParenthesesIsAName() {
        #expect(parts("min(3; 7)") == [
            Part(text: "min", kind: .name),
            Part(text: "3", kind: .value),
            Part(text: "7", kind: .value)
        ])
    }

    @Test func aPercentFormMutesTheSignAndItsReservedName() {
        #expect(parts("20% of 50") == [
            Part(text: "20", kind: .value),
            Part(text: "%", kind: .muted),
            Part(text: "of", kind: .muted),
            Part(text: "50", kind: .value)
        ])
    }

    @Test(arguments: ["31 Mar", "31 Mar 2027"])
    func daysUntilACalendarDateReadsAsCalendarDates(date: String) {
        #expect(parts("days until \(date)") == [
            Part(text: "days", kind: .calendarDate),
            Part(text: "until", kind: .muted),
            Part(text: date, kind: .calendarDate)
        ])
    }

    @Test func aMonthShiftKeepsTheCalendarDateKind() {
        #expect(parts("31 Mar + 1 month") == [
            Part(text: "31 Mar", kind: .calendarDate),
            Part(text: "+", kind: .muted),
            Part(text: "1 month", kind: .calendarDate)
        ])
    }

    @Test func aWeekdayExpressionReadsAsCalendarDates() {
        #expect(parts("monday in 3 weeks") == [
            Part(text: "monday", kind: .calendarDate),
            Part(text: "in", kind: .muted),
            Part(text: "3 weeks", kind: .calendarDate)
        ])
    }

    @Test func aWeekdayOutsideAWeekdayExpressionStaysALabel() {
        #expect(parts("monday 2 + 3").first == Part(text: "monday", kind: .muted))
    }

    @Test(arguments: [
        ("5pm ldn in sf", "5pm"),
        ("11 am PST in London", "11 am"),
        ("2:30 pm HKT in London", "2:30 pm"),
        ("5pm Mar del Plata in London", "5pm")
    ])
    func aTimeOfDayIsOnePartAndItsPlacesHaveNone(line: String, time: String) {
        #expect(parts(line) == [
            Part(text: time, kind: .timeOfDay),
            Part(text: "in", kind: .muted)
        ])
    }

    @Test func anHourOutsideTheTwelveHourClockIsNoTimeOfDay() {
        #expect(parts("13pm") == [
            Part(text: "13", kind: .value),
            Part(text: "pm", kind: .muted)
        ])
    }

    @Test func aDurationConversionColorsEachSideByItsUnit() {
        #expect(parts("1500 mins in days") == [
            Part(text: "1500 mins", kind: .timeOfDay),
            Part(text: "in", kind: .muted),
            Part(text: "days", kind: .calendarDate)
        ])
    }

    @Test(arguments: [
        ("15 min", SyntaxKind.timeOfDay),
        ("2h", .timeOfDay),
        ("2 days", .calendarDate)
    ])
    func aDurationIsOnePartOfItsKind(line: String, kind: SyntaxKind) {
        #expect(parts(line) == [Part(text: line, kind: kind)])
    }

    @Test func minAsAConversionTargetIsATimeOfDayUnit() {
        #expect(parts("90 s in min").last == Part(text: "min", kind: .timeOfDay))
    }

    @Test func currenciesAndMonetaryValues() {
        #expect(parts("$8 in BRL") == [
            Part(text: "$8", kind: .value),
            Part(text: "in", kind: .muted),
            Part(text: "BRL", kind: .value)
        ])
    }

    @Test func aTextLineHasNoParts() {
        #expect(parts("buy milk").isEmpty)
        #expect(parts("").isEmpty)
    }

    @Test func aLineThatCannotBeCalculatedKeepsItsParts() {
        #expect(parts("10 ft in kg") == [
            Part(text: "10 ft", kind: .unit),
            Part(text: "in", kind: .muted)
        ])
    }

    @Test func anIncompleteLineKeepsItsParts() {
        #expect(parts("10 + ") == [
            Part(text: "10", kind: .value),
            Part(text: "+", kind: .muted)
        ])
    }

    @Test func charactersTheLanguageDoesNotDefineGetNoPart() {
        #expect(parts("10 ? 5") == [
            Part(text: "10", kind: .value),
            Part(text: "5", kind: .value)
        ])
    }

    @Test func aHeadingKeepsItsCommentApart() {
        #expect(parts("## Budget // q4") == [
            Part(text: "## Budget", kind: .heading),
            Part(text: "// q4", kind: .comment)
        ])
    }

    @Test func rangesCountFromTheStartOfTheLineAsWritten() {
        let all = lineParts(sheetText: "  2 + 3", context: context)
        #expect(all == [[
            LinePart(kind: .value, range: 2 ..< 3),
            LinePart(kind: .muted, range: 4 ..< 5),
            LinePart(kind: .value, range: 6 ..< 7)
        ]])
    }
}
