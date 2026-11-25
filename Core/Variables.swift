import Foundation

enum Language {
    static let functionNames: Set<String> = ["min", "max", "sqrt", "fact", "sin", "round", "log", "fromunix"]
    static let constantNames: Set<String> = ["pi"]
    static let operatorNames: Set<String> = ["and", "or", "times"]
    static var reservedNames: Set<String> {
        functionNames.union(constantNames).union(operatorNames).union(Units.reservedNames).union(Money.names.keys).union(["to", "at", "until", "of", "off", "as", "timespan", "am", "pm", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"])
    }
}

func normalizeName(_ words: [String]) -> String {
    words.joined(separator: " ")
}

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

struct VariableTable {
    private(set) var bindings: [String: ExpressionValue] = [:]
    private(set) var erredNames: Set<String> = []
    private(set) var measures: [String: Measure] = [:]
    private(set) var countBases: [String: Decimal] = [:]
    private(set) var showsTimeOfDay: Set<String> = []

    var definedNames: Set<String> {
        Set(bindings.keys).union(erredNames)
    }

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

    enum Constants {
        static let values: [String: Decimal] = [
            "pi": Decimal(string: "3.1415926535897932384626433832795028842", locale: Locale(identifier: "en_US_POSIX"))!
        ]
    }
}
