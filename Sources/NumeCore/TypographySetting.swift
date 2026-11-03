// Settings values for sheet typography (ADK-261): the font size in px and
// the line height as a multiplier of the size. An empty field commits the
// default; any other invalid text commits the last valid value. A stored
// value outside its range falls back to the default.

import Foundation

public enum TypographySetting {
    public static let sizeDefault = SheetTypography.defaultSize
    public static let sizeRange = 9 ... 32
    public static let lineHeightDefault = SheetTypography.defaultLineHeight
    public static let lineHeightRange = 1.0 ... 3.0

    /// The size a field commits when its text changes: a whole number in
    /// range, the default for an empty field, otherwise the last valid size.
    public static func committedSize(_ text: String, lastValid: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return sizeDefault
        }
        guard let value = Int(trimmed), sizeRange.contains(value) else { return lastValid }
        return value
    }

    /// The line height a field commits when its text changes: a number in
    /// range with at most one decimal place and a dot separator, the default
    /// for an empty field, otherwise the last valid line height.
    public static func committedLineHeight(_ text: String, lastValid: Double) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return lineHeightDefault
        }
        guard let tenths = tenths(of: trimmed), lineHeightRange.contains(Double(tenths) / 10) else { return lastValid }
        return Double(tenths) / 10
    }

    /// The size a stored preference yields: the stored size when it is in
    /// range, otherwise the default.
    public static func storedSize(_ value: Int?) -> Int {
        guard let value, sizeRange.contains(value) else { return sizeDefault }
        return value
    }

    /// The line height a stored preference yields: the stored value when it
    /// is in range with at most one decimal place, otherwise the default.
    public static func storedLineHeight(_ value: Double?) -> Double {
        guard let value, lineHeightRange.contains(value), (value * 10).rounded() / 10 == value else {
            return lineHeightDefault
        }
        return value
    }

    /// The typography a family and a pair of stored preferences yield, with
    /// the stored values within their ranges.
    public static func typography(
        family: String = SheetTypography.defaultFamily,
        size: Int?,
        lineHeight: Double?
    ) -> SheetTypography {
        SheetTypography(
            family: family,
            size: storedSize(size),
            lineHeight: storedLineHeight(lineHeight)
        )
    }

    /// The number of tenths in CSS number text: digits, optionally a dot and
    /// one digit. The dot is the only decimal separator, whatever the region.
    private static func tenths(of text: String) -> Int? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = parts.first, !whole.isEmpty, whole.count <= 2,
              whole.allSatisfy({ $0.isASCII && $0.isNumber }), let wholeValue = Int(whole)
        else { return nil }
        guard parts.count == 2 else { return wholeValue * 10 }
        let fraction = parts[1]
        guard fraction.count == 1, let digit = fraction.first, digit.isASCII, let tenth = digit.wholeNumberValue else { return nil }
        return wholeValue * 10 + tenth
    }
}
