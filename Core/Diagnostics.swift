// The exact user-facing message strings for every language error.
// Tests assert these texts exactly.

public enum Diagnostic: Error, Equatable, Sendable, Hashable {
    /// The line cannot be recognized as an expression at all.
    case syntax
    /// A division by zero.
    case divisionByZero
    /// A nonzero result outside the supported magnitude range.
    case outOfRange
    /// An operation with no real-number result, such as a negative square root.
    case notARealNumber
    /// A name used before any definition provides it a value.
    case undefinedVariable(name: String)
    /// An assignment to a reserved operator, function, or constant name.
    case reservedName(name: String)
    /// A date that the calendar does not contain.
    case invalidDate
    /// The expression consumes the result of an expression that failed.
    case dependsOnError
    /// A function called with an unexpected number of arguments.
    case argumentCount(function: String, requirement: String)
    case exchangeRateUnavailable(currency: String)
    /// The city data has no place of that name.
    case unknownCity(name: String)
    /// The city name means more than one place, so no conversion picks one
    /// silently.
    case ambiguousCity(name: String)
    /// The city was never looked up and the connection is unavailable.
    case cityNotCached(name: String)

    /// The exact message shown in place of the result.
    public var message: String {
        switch self {
        case let .exchangeRateUnavailable(currency):
            "Exchange rate unavailable: \(currency)"
        case let .unknownCity(name):
            "Unknown city: \(name)"
        case let .ambiguousCity(name):
            "Ambiguous city: \(name)"
        case let .cityNotCached(name):
            "City not cached: \(name)"
        case .syntax:
            "Invalid syntax"
        case .divisionByZero:
            "Division by zero"
        case .outOfRange:
            "Out of range"
        case .notARealNumber:
            "Not a real number"
        case let .undefinedVariable(name):
            "Undefined variable: \(name)"
        case let .reservedName(name):
            "Reserved name: \(name)"
        case .invalidDate:
            "Invalid date"
        case .dependsOnError:
            "Depends on an error"
        case let .argumentCount(function, requirement):
            "\(function) takes \(requirement)"
        }
    }
}
