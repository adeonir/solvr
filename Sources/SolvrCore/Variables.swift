// Names start with a letter and accept accented letters, underscores, and
// subsequent digits (`salário`, `despesa_mensal`, `item2`); they are
// case-sensitive. Any run of spaces, tabs, and non-breaking spaces between
// the words of a name counts as one space. Every reference resolves to its
// nearest preceding definition in sheet order, so reassignment affects only
// later expressions, and a defined name whose defining expression failed
// or never finished leaves its dependents without a usable result.

import Foundation

/// Names the language keeps for itself; assigning to one is a reserved-name
/// error. Units register their own reserved names alongside these sets.
enum Language {
    static let functionNames: Set<String> = ["min", "max", "sqrt", "fact", "sin", "round", "log", "fromunix"]
    static let constantNames: Set<String> = ["pi"]
    /// The word forms of the operators (`times`, `and`, `or`); their symbol
    /// forms cannot spell a name.
    static let operatorNames: Set<String> = ["and", "or", "times"]
    static var reservedNames: Set<String> {
        functionNames.union(constantNames).union(operatorNames).union(Units.reservedNames).union(Money.names.keys).union(["to", "at", "until", "of", "off", "as", "timespan", "am", "pm", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"])
    }
}

/// Names normalize runs of spaces, tabs, and non-breaking spaces between
/// the words of a name into one space.
func normalizeName(_ words: [String]) -> String {
    words.joined(separator: " ")
}

/// The longest complete defined name that the word run spells, looked up by
/// whole name, from the longest candidate to the shortest. The
/// word run reaching the parser carries the words as one token each, so the
/// gaps between them are already normalized away.
func matchingDefinedName(words: [String], definedNames: Set<String>) -> [String]? {
    guard !definedNames.isEmpty, !words.isEmpty else { return nil }
    for length in stride(from: words.count, through: 1, by: -1) {
        let candidate = Array(words.prefix(length))
        let name = normalizeName(candidate)
        if definedNames.contains(name) {
            return candidate
        }
    }
    return nil
}

/// The values the sheet has defined so far, resolved by nearest preceding
/// definition. Names whose defining expression failed or never
/// finished stay defined for name recognition but yield the
/// dependency error, never a stale value.
struct VariableTable {
    private(set) var bindings: [String: ExpressionValue] = [:]
    /// Names whose defining expression erred or never finished.
    private(set) var erredNames: Set<String> = []
    /// The quantity a name's value counts in, for the names defined with one.
    private(set) var measures: [String: Measure] = [:]
    /// The pixel base a name's relative value was counted at, for the names
    /// whose value is a relative count rather than pixels.
    private(set) var countBases: [String: Decimal] = [:]
    /// The names whose calendar date shows its time of day, as `fromunix`
    /// values do.
    private(set) var showsTimeOfDay: Set<String> = []

    /// The names visible for longest-name recognition at the current point
    /// of the sheet.
    var definedNames: Set<String> {
        Set(bindings.keys).union(erredNames)
    }

    /// Defines a name for every later expression in sheet order.
    mutating func define(
        _ name: String, _ value: ExpressionValue, measure: Measure? = nil, countBase: Decimal? = nil,
        showsTimeOfDay: Bool = false
    ) {
        bindings[name] = value
        erredNames.remove(name)
        measures[name] = measure
        countBases[name] = countBase
        if showsTimeOfDay {
            self.showsTimeOfDay.insert(name)
        } else {
            self.showsTimeOfDay.remove(name)
        }
    }

    /// The defining expression erred or never finished: no stale value
    /// remains available, and dependents show that the dependency erred.
    mutating func fail(_ name: String) {
        bindings.removeValue(forKey: name)
        measures.removeValue(forKey: name)
        countBases.removeValue(forKey: name)
        showsTimeOfDay.remove(name)
        erredNames.insert(name)
    }

    func resolve(_ name: String) throws -> Decimal {
        if let constant = Constants.values[name] {
            return constant
        }
        if let value = bindings[name], case let .decimal(number) = value {
            return number
        }
        if erredNames.contains(name) {
            throw Diagnostic.dependsOnError
        }
        throw Diagnostic.undefinedVariable(name: name)
    }

    /// Names the language defines values for.
    enum Constants {
        /// pi carries enough digits that approximations stay within the
        /// error budget of one unit in the 34th significant digit.
        static let values: [String: Decimal] = [
            "pi": Decimal(string: "3.1415926535897932384626433832795028842", locale: Locale(identifier: "en_US_POSIX"))!
        ]
    }
}
