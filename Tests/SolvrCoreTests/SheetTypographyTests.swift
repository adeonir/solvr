import Foundation
@testable import SolvrCore
import Testing

// One value of family, size, and line height gives every font size and line
// metric of the sheet editor. The defaults reproduce the editor's fixed
// metrics.

struct SheetTypographyTests {
    @Test func defaultsMatchTheCurrentSheet() {
        let typography = SheetTypography.default
        #expect(typography.family == "SF Mono")
        #expect(typography.size == 13)
        #expect(typography.lineHeight == 2)
        #expect(typography.textSize == 13)
        #expect(typography.headingSize == 13)
        #expect(typography.lineNumberSize == 11)
        #expect(typography.lineHeightInPixels == 26)
    }

    @Test func lineHeightInPixelsIsSizeTimesMultiplier() {
        #expect(SheetTypography(family: "SF Mono", size: 13, lineHeight: 2).lineHeightInPixels == 26)
        #expect(SheetTypography(family: "SF Mono", size: 20, lineHeight: 1.5).lineHeightInPixels == 30)
        #expect(SheetTypography(family: "SF Mono", size: 9, lineHeight: 1).lineHeightInPixels == 9)
    }

    @Test func lineNumberSizeIsElevenThirteenthsOfTheSize() {
        #expect(SheetTypography(family: "SF Mono", size: 26, lineHeight: 2).lineNumberSize == 22)
        #expect(SheetTypography(family: "SF Mono", size: 13, lineHeight: 2).lineNumberSize == 11)
        let size = SheetTypography(family: "SF Mono", size: 16, lineHeight: 2).lineNumberSize
        #expect(abs(size - 16.0 * 11.0 / 13.0) < 0.000_001)
    }
}
