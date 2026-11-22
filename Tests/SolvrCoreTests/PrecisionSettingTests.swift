import Foundation
#if canImport(Core)
@testable import Core
#else
@testable import SolvrCore
#endif
import Testing

// General precision runs from 1 through 10 with default 2, crypto precision
// from 5 through 15 with default 10. A cleared or invalid field restores its
// last valid value.

struct PrecisionSettingTests {
    @Test func defaultsAndRangesMatchTheSpec() {
        #expect(PrecisionSetting.generalDefault == 2)
        #expect(PrecisionSetting.generalRange == 1 ... 10)
        #expect(PrecisionSetting.cryptoDefault == 10)
        #expect(PrecisionSetting.cryptoRange == 5 ... 15)
    }

    @Test func integersInRangeAreCommitted() {
        #expect(PrecisionSetting.committed("7", in: PrecisionSetting.generalRange, lastValid: 4) == 7)
        #expect(PrecisionSetting.committed("1", in: PrecisionSetting.generalRange, lastValid: 4) == 1)
        #expect(PrecisionSetting.committed("10", in: PrecisionSetting.generalRange, lastValid: 4) == 10)
        #expect(PrecisionSetting.committed("15", in: PrecisionSetting.cryptoRange, lastValid: 10) == 15)
    }

    @Test func clearedInvalidOrOutOfRangeTextRestoresTheLastValidValue() {
        for text in ["", "   ", "abc", "2.5", "0", "11", "-3", "1e3"] {
            #expect(PrecisionSetting.committed(text, in: PrecisionSetting.generalRange, lastValid: 4) == 4)
        }
        for text in ["", "4", "16", "10.0"] {
            #expect(PrecisionSetting.committed(text, in: PrecisionSetting.cryptoRange, lastValid: 12) == 12)
        }
    }

    @Test func surroundingSpacesDoNotInvalidateAValue() {
        #expect(PrecisionSetting.committed(" 6 ", in: PrecisionSetting.generalRange, lastValid: 4) == 6)
    }

    @Test func storedValuesOutsideTheRangeFallBackToTheDefault() {
        #expect(PrecisionSetting.stored(nil, in: PrecisionSetting.generalRange, default: 2) == 2)
        #expect(PrecisionSetting.stored(99, in: PrecisionSetting.generalRange, default: 2) == 2)
        #expect(PrecisionSetting.stored(0, in: PrecisionSetting.cryptoRange, default: 10) == 10)
        #expect(PrecisionSetting.stored(6, in: PrecisionSetting.cryptoRange, default: 10) == 6)
    }
}
