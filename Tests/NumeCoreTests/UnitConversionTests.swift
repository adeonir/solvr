import Foundation
@testable import NumeCore
import Testing

// Complete-sheet tests for physical, data, and temperature quantity
// conversions (ADK-227). A quantity converted through `in` shows its
// value in the destination unit beside its expression, and keeps its
// numeric value reusable inside arithmetic. Each unit accepts only its
// standard abbreviation and its full name singular and plural; no other
// alias. Locale, display precision, time zone, and clock are fixed per
// fixture through the EvaluationContext, per ADR-005. The inch
// abbreviation `in` spells the conversion keyword itself, so inches
// accept only `inch` and `inches`.

struct UnitConversionTests {
    private func context(
        locale identifier: String = "pt_BR",
        precision: Int = 10
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: Date(timeIntervalSince1970: 1_791_926_400), // 2026-10-30 00:00 UTC
            displayPrecision: precision
        )
    }

    private func display(_ source: String) -> String? {
        evaluate(sheetText: source, context: context())[0].display
    }

    // MARK: Acceptance examples

    @Test
    func feetConvertToMetresWithBrazilianFormatting() throws {
        let result = evaluate(sheetText: "10 ft in m", context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.diagnostic == nil)
        #expect(try result.value == .decimal(Decimal(exact: "3.048")))
        #expect(result.display == "3,048 m")
    }

    @Test
    func negativeQuantitiesConvertWithTheirSign() {
        #expect(display("-10 ft in m") == "-3,048 m")
    }

    // MARK: Length conversions with exact factors

    @Test(arguments: [
        ("36 inches in feet", "3 ft"),
        ("1 inch in cm", "2,54 cm"),
        ("1 mile in yards", "1.760 yd"),
        ("5 miles in feet", "26.400 ft"),
        ("2 km in m", "2.000 m"),
    ])
    func lengthConversions(_ source: String, _ expected: String) {
        #expect(display(source) == expected)
    }

    // MARK: Abbreviation and full-name aliases convert alike

    @Test
    func abbreviationsAndFullNamesConvertAlike() {
        let equivalences: [(sheets: [String], display: String, precision: Int)] = [
            (["10 ft in m", "10 foot in m", "10 feet in m"], "3,048 m", 10),
            (["36 inches in feet", "36 inch in foot", "36 inches in feet"], "3 ft", 10),
            (["100 cm in m", "100 centimeter in m", "100 centimeters in m"], "1 m", 10),
            (["4 yd in feet", "4 yards in feet", "4 yard in feet"], "12 ft", 10),
            (["1 mi in yards", "1 mile in yards", "1 miles in yards"], "1.760 yd", 10),
            (["1000 mm in m", "1000 millimeter in m", "1000 millimeters in m"], "1 m", 10),
            (["1 KB in bytes", "1 kilobyte in bytes", "1 kilobytes in bytes"], "1.000 B", 10),
            (["1 KiB in bytes", "1 kibibyte in bytes", "1 kibibytes in bytes"], "1.024 B", 10),
            (
                ["1 MiB in KiB", "1 mebibyte in kibibyte", "1 mebibytes in KiB"],
                "1.024 KiB", 10
            ),
            (["0 c in f", "0 celsius in fahrenheit", "0 celsius in f"], "32 °F", 2),
            (
                ["100 f in c", "100 fahrenheit in celsius", "100 fahrenheit in c"],
                "37,78 °C", 2
            ),
            (["1 kilometer in m", "1 kilometers in m"], "1.000 m", 10)
        ]
        for equivalence in equivalences {
            for sheet in equivalence.sheets {
                let result = evaluate(sheetText: sheet, context: context(precision: equivalence.precision))[0]
                #expect(result.diagnostic == nil)
                #expect(result.display == equivalence.display)
            }
        }
    }

    // MARK: Decimal data units take factors of 1000

    @Test(arguments: [
        ("1 KB in bytes", "1.000 B"),
        ("1 MB in KB", "1.000 KB"),
        ("1 GB in MB", "1.000 MB"),
        ("1 TB in GB", "1.000 GB"),
        ("1 KB in KiB", "0,9765625 KiB"),
    ])
    func decimalDataUnitConversions(_ source: String, _ expected: String) {
        #expect(display(source) == expected)
    }

    @Test
    func decimalDataUnitFactorsAreExactlyOneThousand() throws {
        let oneThousand = try Decimal(exact: "1000")
        let oneMillion = try Decimal(exact: "1000000")
        let oneBillion = try Decimal(exact: "1000000000")
        let oneTrillion = try Decimal(exact: "1000000000000")
        let results = evaluate(
            sheetText: "1 KB in bytes\n1 MB in bytes\n1 GB in bytes\n1 TB in bytes",
            context: context()
        )
        #expect(results[0].value == .decimal(oneThousand))
        #expect(results[1].value == .decimal(oneMillion))
        #expect(results[2].value == .decimal(oneBillion))
        #expect(results[3].value == .decimal(oneTrillion))
        let steps = evaluate(
            sheetText: "1 MB in KB\n1 GB in MB\n1 TB in GB\n1 TB in bytes",
            context: context()
        )
        for result in steps {
            #expect(result.diagnostic == nil)
        }
        #expect(steps[0].value == .decimal(oneThousand))
        #expect(steps[1].value == .decimal(oneThousand))
        #expect(steps[2].value == .decimal(oneThousand))
        #expect(steps[3].value == .decimal(oneTrillion))
    }

    // MARK: Binary data units take factors of 1024

    @Test(arguments: [
        ("1 KiB in bytes", "1.024 B"),
        ("1 MiB in KiB", "1.024 KiB"),
        ("1 GiB in MiB", "1.024 MiB"),
        ("1 TiB in GiB", "1.024 GiB"),
        ("1024 bytes in KiB", "1 KiB")
    ])
    func binaryDataUnitConversions(_ source: String, _ expected: String) {
        #expect(display(source) == expected)
    }

    @Test
    func binaryDataUnitFactorsAreExactlyOneThousandTwentyFour() throws {
        let results = evaluate(
            sheetText: "1 KiB in bytes\n1 MiB in bytes\n1 GiB in bytes\n1 TiB in bytes",
            context: context()
        )
        #expect(results[0].value == .decimal(1024))
        #expect(try results[1].value == .decimal(Decimal(exact: "1048576")))
        #expect(try results[2].value == .decimal(Decimal(exact: "1073741824")))
        #expect(try results[3].value == .decimal(Decimal(exact: "1099511627776")))
        let steps = evaluate(sheetText: "1 MiB in KiB\n1 GiB in MiB\n1 TiB in GiB", context: context())
        for result in steps {
            #expect(result.diagnostic == nil)
            #expect(result.value == .decimal(1024))
        }
    }

    // MARK: Temperature conversions with two displayed decimal places

    @Test(arguments: [
        ("100 F in C", "37,78 °C"),
        ("32 fahrenheit in celsius", "0 °C"),
        ("0 celsius in fahrenheit", "32 °F"),
        ("212 f in c", "100 °C"),
        ("0 celsius in kelvin", "273,15 K")
    ])
    func temperatureConversions(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context(precision: 2))[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    @Test
    func fahrenheitDifferenceIsExactAtBoilingPoint() {
        let result = evaluate(sheetText: "212 f in c", context: context(precision: 40))[0]
        #expect(result.value == .decimal(100))
        #expect(result.display == "100 °C")
    }

    // MARK: Conversions contribute their value inside arithmetic only

    @Test
    func convertedValuesKeepTheirNumericMeaningInsideArithmetic() throws {
        let results = evaluate(sheetText: "10 ft in m times 2", context: context())
        #expect(results[0].diagnostic == nil)
        #expect(try results[0].value == .decimal(Decimal(exact: "6.096")))
        #expect(results[0].display == "6,096")
    }

    // MARK: A converted quantity shows its destination unit

    @Test
    func sheetShowsConvertedQuantitiesBesideTheirExpressions() throws {
        let sheet = """
        # Conversões
        10 ft in m
        1 KB in bytes
        212 f in c
        -2 inches in cm
        """
        let results = evaluate(sheetText: sheet, context: context(precision: 2))
        // The heading holds no result; each expression shows its value in
        // the destination unit beside itself.
        #expect(results[0].kind == .heading)
        #expect(results[3].display == "100 °C")
        #expect(results[4].display == "-5,08 cm")
        // The other two examples hold two decimal places only at higher
        // precision; their values stay exact.
        #expect(try results[1].value == .decimal(Decimal(exact: "3.048")))
        #expect(try results[2].value == .decimal(Decimal(exact: "1000")))
        #expect(results[1].display == "3,05 m")
        #expect(results[2].display == "1.000 B")
    }

    // MARK: Quantities alone display their value with their unit

    @Test
    func quantitiesDisplayTheirOwnValueAndUnit() {
        let results = evaluate(sheetText: "10 ft\n1 KB\n100 F", context: context())
        #expect(results[0].diagnostic == nil)
        #expect(results[0].display == "10 ft")
        #expect(results[1].display == "1 KB")
        #expect(results[2].display == "100 °F")
    }

    // MARK: Unknown aliases and incompatible dimensions stay invalid

    @Test(arguments: [
        "5 furlongs in feet",
        "1 KB in kilo",
        "10 ft in leagues",
        "16px in degrees",
        "1 KB in px",
        "16px in bytes",
    ])
    func unsupportedConversionsShowInvalidSyntax(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.value == nil)
        #expect(result.diagnostic == .syntax)
        #expect(result.diagnostic?.message == "Invalid syntax")
    }

    // MARK: Unit names are reserved

    @Test(arguments: [
        ("feet = 2", "Reserved name: feet"),
        ("KB = 2", "Reserved name: KB"),
        ("em = 2", "Reserved name: em"),
    ])
    func assigningAUnitNameIsAReservedNameError(_ source: String, _ message: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.diagnostic?.message == message)
    }

    // MARK: Retained units

    @Test
    func bareQuantityRetainsItsUnitAndDisplaysUnchanged() {
        let result = evaluate(sheetText: "10 ft", context: context())[0]
        #expect(result.unit == .foot)
        #expect(result.value == .decimal(10))
        #expect(result.display == "10 ft")
    }

    @Test
    func conversionRetainsItsDestinationUnit() {
        let result = evaluate(sheetText: "10 ft in m", context: context(locale: "en_US", precision: 3))[0]
        #expect(result.unit == .metre)
        #expect(result.display == "3.048 m")
    }

    @Test
    func negatedQuantityRetainsItsUnit() {
        #expect(evaluate(sheetText: "-10 ft", context: context())[0].unit == .foot)
    }

    @Test(arguments: [
        "10 ft + 2 ft",
        "10 ft * 2",
        "x = 10 ft",
    ])
    func arithmeticAndAssignmentDoNotRetainAUnit(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.unit == nil)
        #expect(result.diagnostic == nil)
    }
}
