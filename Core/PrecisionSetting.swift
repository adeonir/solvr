import Foundation

public enum PrecisionSetting {
    public static let generalDefault = 2
    public static let generalRange = 1 ... 10
    public static let cryptoDefault = 10
    public static let cryptoRange = 5 ... 15

    /// The value a precision field commits when focus leaves it: the text
    /// as an integer in range, otherwise the last valid value.
    public static func committed(_ text: String, in range: ClosedRange<Int>, lastValid: Int) -> Int {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(value) else {
            return lastValid
        }
        return value
    }

    /// The value a stored preference yields: the stored integer when it is
    /// in range, otherwise the default.
    public static func stored(_ value: Int?, in range: ClosedRange<Int>, default fallback: Int) -> Int {
        guard let value, range.contains(value) else { return fallback }
        return value
    }
}
