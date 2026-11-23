// The font size in px and the line height as a multiplier of the size. An
// empty field commits the default; any other invalid text commits the last
// valid value. A stored value outside its range falls back to the default.

import Foundation

public enum TypographySetting {
    public static let sizeDefault = SheetTypography.defaultSize
    public static let sizeRange = 9 ... 32
    public static let lineHeightDefault = SheetTypography.defaultLineHeight
    public static let lineHeightRange = 1.0 ... 3.0

    /// The size a field commits when its text changes: a whole number in
    /// range, the default for an empty field, otherwise the last valid size.
    /// Digits only: a sign or a leading zero does not produce a value.
    public static func committedSize(_ text: String, lastValid: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return sizeDefault
        }
        guard let value = validSize(of: text) else { return lastValid }
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
        guard let value = validLineHeight(of: text) else { return lastValid }
        return value
    }

    /// The size a field holds while its text is on screen: the size the text
    /// commits when it is valid, otherwise nil. An empty or invalid field
    /// holds its last valid size and commits on focus leave.
    public static func validSize(of text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = wholeNumber(of: trimmed), sizeRange.contains(value) else { return nil }
        return value
    }

    /// The line height a field holds while its text is on screen: the line
    /// height the text commits when it is valid, otherwise nil. An empty or
    /// invalid field holds its last valid line height and commits on focus
    /// leave.
    public static func validLineHeight(of text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let tenths = tenths(of: trimmed), lineHeightRange.contains(Double(tenths) / 10) else { return nil }
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

    /// The number of tenths in line-height text: digits, optionally a dot
    /// and one digit. The dot is the only decimal separator, whatever the
    /// region, and the whole part carries no leading zero.
    private static func tenths(of text: String) -> Int? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = parts.first, !whole.isEmpty, whole.count <= 2,
              whole.count == 1 || whole.first != "0",
              whole.allSatisfy({ $0.isASCII && $0.isNumber }), let wholeValue = Int(whole)
        else { return nil }
        guard parts.count == 2 else { return wholeValue * 10 }
        let fraction = parts[1]
        guard fraction.count == 1, let digit = fraction.first, digit.isASCII, let tenth = digit.wholeNumberValue else { return nil }
        return wholeValue * 10 + tenth
    }

    /// The whole number in size text: at most two ASCII digits, no sign and
    /// no leading zero. The zero alone parses, and the range rules settle it.
    private static func wholeNumber(of text: String) -> Int? {
        guard text.count <= 2, let first = text.first, first != "0" || text.count == 1,
              text.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        return Int(text)
    }
}
