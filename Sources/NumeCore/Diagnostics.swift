// Diagnostics: the exact user-facing message strings for every language
// error (ADK-221). Tests assert these texts exactly.

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

    /// The exact message shown in place of the result.
    public var message: String {
        switch self {
        case .syntax:
            return "Invalid syntax"
        case .divisionByZero:
            return "Division by zero"
        case .outOfRange:
            return "Out of range"
        case .notARealNumber:
            return "Not a real number"
        case .undefinedVariable(let name):
            return "Undefined variable: \(name)"
        case .reservedName(let name):
            return "Reserved name: \(name)"
        case .invalidDate:
            return "Invalid date"
        case .dependsOnError:
            return "Depends on an error"
        case .argumentCount(let function, let requirement):
            return "\(function) takes \(requirement)"
        }
    }
}
