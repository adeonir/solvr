// Sheet (ADK-221): per-line evaluation. Errors stay local to their line, an
// incomplete line leaves no result and no message, text lines and
// non-evaluated lines show neither, names resolve against the nearest
// preceding definitions (ADR-001), and a reference to a name whose
// defining expression failed shows that it depends on an error.

import Foundation

struct SheetEvaluator {
    let context: EvaluationContext
    /// Names defined so far, with the values their expressions produced.
    var bindings: [String: ExpressionValue] = [:]
    /// Names whose defining expression erred.
    var erredNames: Set<String> = []

    let locale: Locale
    let decimalSeparator: Character
    let groupingSeparator: Character

    static let headingExpression = try! NSRegularExpression(pattern: "^#{1,6} .*$")

    init(context: EvaluationContext) {
        let locale = Locale(identifier: context.localeIdentifier)
        let decimal = locale.decimalSeparator?.first ?? "."
        self.context = context
        self.locale = locale
        self.decimalSeparator = decimal
        self.groupingSeparator = decimal == "." ? "," : "."
    }

    mutating func evaluate(_ sheetText: String) -> [ExpressionResult] {
        sheetText.components(separatedBy: "\n").map { line in
            evaluate(line: line)
        }
    }

    mutating func evaluate(line rawLine: String) -> ExpressionResult {
        // A line beginning with `//` is a Comment; the comment text is
        // never evaluated, inline after an expression or alone.
        if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            return ExpressionResult(kind: .comment)
        }
        let commentStart = rawLine.range(of: "//")?.lowerBound
        let withoutComment: String
        if let commentStart {
            withoutComment = String(rawLine[rawLine.startIndex ..< commentStart])
        } else {
            withoutComment = rawLine
        }
        let line = withoutComment.trimmingCharacters(in: .whitespaces)

        // Headings from `#` through `######` followed by a space are never
        // evaluated and show no result and no message.
        if case .some = Self.headingExpression.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ) {
            return ExpressionResult(kind: .heading)
        }

        // A line with no number, operator, `=`, or known name — including
        // an empty line — is a text line: no result and no message.
        if !carriesEvaluationSignal(line) {
            return ExpressionResult(kind: .textLine)
        }

        guard let tokens = try? Tokenizer.tokenize(
            line, decimalSeparator: decimalSeparator, groupingSeparator: groupingSeparator
        ) else {
            return ExpressionResult(kind: .expression, diagnostic: .syntax)
        }
        return attempt(lineTokens: tokens)
    }

    /// Whether the trimmed line holds anything that can evaluate at all.
    private func carriesEvaluationSignal(_ line: String) -> Bool {
        let operatorCharacters: Set<Character> = ["+", "-", "*", "/", "^", "="]
        if line.contains(where: { $0.isNumber || operatorCharacters.contains($0) }) {
            return true
        }
        // A word of the line is known when the sheet defines it already or
        // the language reserves it.
        for word in line.split(separator: " ") {
            let text = String(word)
            if bindings.keys.contains(where: { name in nameKnown(name, word: text) })
                || Language.functionNames.contains(text)
                || Language.constantNames.contains(text)
                || text == "times"
                || text == "%"
            {
                return true
            }
        }
        return false
    }

    /// Known names keep accents, underscores, and later digits; a word
    /// matches when a multiword name starts with it after single spaces.
    private func nameKnown(_ name: String, word: String) -> Bool {
        name == word || name.hasPrefix(word + " ")
    }

    /// Parse attempts that strip 0 through every leading word: the first
    /// attempt that parses and evaluates completes the line; otherwise the
    /// strongest failure decides the outcome, with an unfinished line
    /// staying silent.
    private mutating func attempt(lineTokens tokens: [Token]) -> ExpressionResult {
        var leadingWords = 0
        while leadingWords < tokens.count, case .word = tokens[leadingWords] {
            leadingWords += 1
        }

        var pendingSeen = false
        var firstFailure: Diagnostic?

        for stripped in 0 ... leadingWords {
            let remaining = Array(tokens[stripped ..< tokens.count])
            do {
                let node = try Parser.parse(remaining)
                let value = try evaluate(node: node)
                if let failure = Numeric.rangeDiagnostic(for: value) {
                    return ExpressionResult(kind: .expression, diagnostic: failure)
                }
                let retained = Numeric.retain(value)
                // A whole-line representation conversion shows its own form
                // beside the expression; the numeric value never changes.
                if case let .representation(kind, _) = node {
                    return ExpressionResult(
                        kind: .expression,
                        value: .decimal(retained),
                        display: Display.format(
                            retained, as: kind,
                            precision: context.displayPrecision, locale: locale
                        )
                    )
                }
                return ExpressionResult(
                    kind: .expression,
                    value: .decimal(retained),
                    display: Numeric.display(
                        retained, precision: context.displayPrecision, locale: locale
                    )
                )
            } catch let diagnostic as Diagnostic {
                firstFailure = firstFailure ?? diagnostic
            } catch ParseError.pending {
                pendingSeen = true
            } catch {
                // The line parses no further: an invalid-syntax candidate.
            }
        }
        if let failure = firstFailure {
            return ExpressionResult(kind: .expression, diagnostic: failure)
        }
        if pendingSeen {
            return ExpressionResult(kind: .incomplete)
        }
        return ExpressionResult(kind: .expression, diagnostic: .syntax)
    }

    // MARK: Value evaluation; failures throw the line's diagnostic.

    mutating func evaluate(node: Node) throws -> Decimal {
        switch node {
        case .number(let value):
            return value
        case .reference(let name):
            return try resolved(name: name)
        case .unaryMinus(let inner):
            return try Numeric.subtract(Decimal(0), evaluate(node: inner))
        case .call:
            // Function behavior arrives with the function work; the parser
            // only opens incomplete-call recognition here.
            throw Diagnostic.syntax
        case .binary(let op, let lhsNode, let rhsNode):
            return try evaluateBinary(op, lhsNode, rhsNode)
        case .representation(let kind, let inner):
            // Inside arithmetic, a conversion contributes its value only;
            // the representation shows when the whole line is the
            // conversion (ADK-222).
            let value = try evaluate(node: inner)
            try Display.validate(value, as: kind)
            return value
        case .percentShare(let percent, let base):
            return try Percent.share(
                try evaluate(node: percent), of: try evaluate(node: base)
            )
        case .percentOff(let percent, let base):
            return try Percent.off(
                try evaluate(node: percent), of: try evaluate(node: base)
            )
        case .percentPortion(let inner):
            return try Percent.portion(try evaluate(node: inner))
        case .assignment(let name, let value):
            do {
                let result = try evaluate(node: value)
                let retained = Numeric.retain(result)
                bindings[name] = .decimal(retained)
                erredNames.remove(name)
                return retained
            } catch let diagnostic as Diagnostic {
                // Neither a stale value nor an erred one: dependents show
                // that the dependency erred.
                bindings.removeValue(forKey: name)
                erredNames.insert(name)
                throw diagnostic
            }
        }
    }

    private mutating func evaluateBinary(
        _ `operator`: NumericOperator, _ lhsNode: Node, _ rhsNode: Node
    ) throws -> Decimal {
        let lhs = try evaluate(node: lhsNode)
        let rhs = try evaluate(node: rhsNode)
        switch `operator` {
        case .add: return try Numeric.add(lhs, rhs)
        case .subtract:
            // `X - N%` takes the portion N/100 of X off X (ADK-226).
            if case .percentPortion(let inner) = rhsNode {
                let portion = try evaluate(node: inner)
                return try Numeric.subtract(lhs, try Percent.share(portion, of: lhs))
            }
            return try Numeric.subtract(lhs, rhs)
        case .multiply: return try Numeric.multiply(lhs, rhs)
        case .divide:
            if rhs == 0 { throw Diagnostic.divisionByZero }
            return try Numeric.divide(lhs, by: rhs)
        case .power:
            if rhs.isNaN { throw Diagnostic.outOfRange }
            if rhs != Numeric.roundPlain(rhs, scale: 0) {
                throw Diagnostic.syntax
            }
            let exponent = NSDecimalNumber(decimal: rhs).intValue
            return try Numeric.power(lhs, by: exponent)
        }
    }

    mutating func resolved(name: String) throws -> Decimal {
        if let constant = Constants.values[name] {
            return constant
        }
        if let value = bindings[name], case .decimal(let number) = value {
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

private extension StringProtocol {
    func trimmingLeft() -> SubSequence {
        drop(while: { $0.isWhitespace })
    }
}
