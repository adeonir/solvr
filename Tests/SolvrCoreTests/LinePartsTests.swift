import Foundation
#if canImport(Core)
@testable import Core
#else
@testable import SolvrCore
#endif
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
        var description: String { "\(text):\(kind)" }
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
            Part(text: "compras", kind: .label),
            Part(text: "2", kind: .number),
            Part(text: "+", kind: .operator),
            Part(text: "3", kind: .number),
            Part(text: "// split", kind: .comment)
        ])
    }

    @Test func aDefinedNameIsAVariableAndTimesIsAnOperator() {
        let line = parts("price = $8 times 3")
        #expect(line.contains(Part(text: "price", kind: .variable)))
        #expect(line.contains(Part(text: "$8", kind: .monetaryValue)))
        #expect(line.contains(Part(text: "times", kind: .operator)))
        #expect(line.contains(Part(text: "3", kind: .number)))
    }

    @Test func aLaterReferenceToADefinedNameIsAVariable() {
        #expect(parts("price = 5\nprice + 1") == [
            Part(text: "price", kind: .variable),
            Part(text: "+", kind: .operator),
            Part(text: "1", kind: .number)
        ])
    }

    @Test func unitsAndTheInKeyword() {
        #expect(parts("10 ft in m") == [
            Part(text: "10", kind: .number),
            Part(text: "ft", kind: .unit),
            Part(text: "in", kind: .reservedName),
            Part(text: "m", kind: .unit)
        ])
    }

    @Test func functionsAndConstants() {
        #expect(parts("sqrt(16) + pi") == [
            Part(text: "sqrt", kind: .function),
            Part(text: "16", kind: .number),
            Part(text: "+", kind: .operator),
            Part(text: "pi", kind: .constant)
        ])
    }

    @Test func currenciesAndMonetaryValues() {
        #expect(parts("$8 in BRL") == [
            Part(text: "$8", kind: .monetaryValue),
            Part(text: "in", kind: .reservedName),
            Part(text: "BRL", kind: .currency)
        ])
    }

    @Test func aTextLineHasNoParts() {
        #expect(parts("buy milk").isEmpty)
        #expect(parts("").isEmpty)
    }

    @Test func aLineThatCannotBeCalculatedKeepsItsParts() {
        #expect(parts("10 ft in kg") == [
            Part(text: "10", kind: .number),
            Part(text: "ft", kind: .unit),
            Part(text: "in", kind: .reservedName)
        ])
    }

    @Test func anIncompleteLineKeepsItsParts() {
        #expect(parts("10 + ") == [
            Part(text: "10", kind: .number),
            Part(text: "+", kind: .operator)
        ])
    }

    @Test func charactersTheLanguageDoesNotDefineGetNoPart() {
        #expect(parts("10 ? 5") == [
            Part(text: "10", kind: .number),
            Part(text: "5", kind: .number)
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
            LinePart(kind: .number, range: 2 ..< 3),
            LinePart(kind: .operator, range: 4 ..< 5),
            LinePart(kind: .number, range: 6 ..< 7)
        ]])
    }
}
