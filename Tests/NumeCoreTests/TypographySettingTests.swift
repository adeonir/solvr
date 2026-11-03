import Foundation
@testable import NumeCore
import Testing

// Settings values for sheet typography (ADK-261): size from 9 through 32 with
// default 13, line height from 1 through 3 with at most one decimal place and
// default 2. An empty field commits the default; any other invalid text
// commits the last valid value. Line height text uses a dot separator
// whatever the regional number formatting.

struct TypographySettingTests {
    @Test func defaultsAndRangesMatchTheSpec() {
        #expect(TypographySetting.sizeDefault == 13)
        #expect(TypographySetting.sizeRange == 9 ... 32)
        #expect(TypographySetting.lineHeightDefault == 2)
        #expect(TypographySetting.lineHeightRange == 1 ... 3)
    }

    @Test func wholeSizesInRangeAreCommitted() {
        for (text, size) in [("9", 9), ("13", 13), ("20", 20), ("32", 32), (" 14 ", 14)] {
            #expect(TypographySetting.committedSize(text, lastValid: 11) == size)
        }
    }

    @Test func emptySizeCommitsTheDefault() {
        #expect(TypographySetting.committedSize("", lastValid: 20) == 13)
        #expect(TypographySetting.committedSize("   ", lastValid: 20) == 13)
    }

    @Test func invalidSizeCommitsTheLastValidValue() {
        for text in ["8", "33", "13.5", "abc", "-12", "+13", "007", "1e1", "13,5"] {
            #expect(TypographySetting.committedSize(text, lastValid: 20) == 20)
        }
    }

    @Test func aValidSizeIsTheValueTheTextCommits() {
        #expect(TypographySetting.validSize(of: "20") == 20)
        #expect(TypographySetting.validSize(of: " 14 ") == 14)
        for text in ["", "   ", "8", "33", "abc", "+13", "007", "13.5"] {
            #expect(TypographySetting.validSize(of: text) == nil)
        }
    }

    @Test func lineHeightsInRangeWithOneDecimalAreCommitted() {
        let cases: [(String, Double)] = [("1", 1), ("1.5", 1.5), ("2", 2), ("2.0", 2), ("3", 3), ("1.1", 1.1), (" 2.5 ", 2.5)]
        for (text, value) in cases {
            #expect(TypographySetting.committedLineHeight(text, lastValid: 1.7) == value)
        }
    }

    @Test func emptyLineHeightCommitsTheDefault() {
        #expect(TypographySetting.committedLineHeight("", lastValid: 1.5) == 2)
        #expect(TypographySetting.committedLineHeight("  ", lastValid: 1.5) == 2)
    }

    @Test func aValidLineHeightIsTheValueTheTextCommits() {
        #expect(TypographySetting.validLineHeight(of: "2") == 2)
        #expect(TypographySetting.validLineHeight(of: "1.5") == 1.5)
        #expect(TypographySetting.validLineHeight(of: " 2.5 ") == 2.5)
        for text in ["", "   ", "0.9", "3.1", "1.25", "1,5", "abc", "13.5"] {
            #expect(TypographySetting.validLineHeight(of: text) == nil)
        }
    }

    @Test func invalidLineHeightCommitsTheLastValidValue() {
        for text in ["0.9", "3.1", "1.25", "1,5", "abc", "4", "0", "-1.5", "1e0", "1.", ".5"] {
            #expect(TypographySetting.committedLineHeight(text, lastValid: 1.5) == 1.5)
        }
    }

    @Test func lineHeightParsingIgnoresRegionalFormatting() {
        #expect(TypographySetting.committedLineHeight("1.5", lastValid: 2) == 1.5)
        #expect(TypographySetting.committedLineHeight("1,5", lastValid: 2) == 2)
    }

    @Test func storedValuesOutsideTheRangeFallBackToTheDefault() {
        #expect(TypographySetting.storedSize(nil) == 13)
        #expect(TypographySetting.storedSize(8) == 13)
        #expect(TypographySetting.storedSize(33) == 13)
        #expect(TypographySetting.storedSize(9) == 9)
        #expect(TypographySetting.storedLineHeight(nil) == 2)
        #expect(TypographySetting.storedLineHeight(0.9) == 2)
        #expect(TypographySetting.storedLineHeight(3.1) == 2)
        #expect(TypographySetting.storedLineHeight(1.25) == 2)
        #expect(TypographySetting.storedLineHeight(1.5) == 1.5)
    }

    @Test func storedValuesBuildTheSheetTypography() {
        let typography = TypographySetting.typography(size: 20, lineHeight: 1.5)
        #expect(typography == SheetTypography(family: "SF Mono", size: 20, lineHeight: 1.5))
        #expect(typography.lineHeightInPixels == 30)
        #expect(TypographySetting.typography(size: nil, lineHeight: nil) == .default)
        #expect(TypographySetting.typography(size: nil, lineHeight: nil).lineHeightInPixels == 26)
    }

    @Test func theChosenFamilyJoinsTheStoredSizeAndLineHeight() {
        let typography = TypographySetting.typography(family: "Menlo", size: 20, lineHeight: 1.5)
        #expect(typography == SheetTypography(family: "Menlo", size: 20, lineHeight: 1.5))
    }
}
