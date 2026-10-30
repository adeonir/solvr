// Sheet (ADK-221): per-line evaluation. Errors stay local to their line, an
// incomplete line leaves no result and no message, text lines and
// non-evaluated lines show neither, names resolve against the nearest
// preceding definitions (ADR-001), and a reference to a name whose
// defining expression failed shows that it depends on an error.

import Foundation

struct SheetEvaluator {
    let context: EvaluationContext
    /// The variable bindings the sheet has defined so far (ADK-223).
    var variables = VariableTable()

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
        // the language reserves it. A blank run inside a name collides with
        // the plain-space spelling the name normalizes to (ADR-002).
        for word in line.map({ Tokenizer.isBlank($0) ? " " : $0 }).split(separator: " ") {
            let text = String(word)
            if variables.definedNames.contains(where: { name in nameKnown(name, word: text) })
                || Language.functionNames.contains(text)
                || Language.constantNames.contains(text)
                || text == "times"
                || text == "%"
            {
                return true
            }
            // A call whose arguments are still empty carries only the
            // name and its parentheses: `sqrt()` and `log()` read their
            // function name, and the empty call belongs to an expression.
            var letters = ""
            for character in text {
                guard character.isLetter else { break }
                letters.append(character)
            }
            if letters != text, Language.functionNames.contains(letters) {
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
    /// staying silent. Every attempt sees the names defined so far, so a
    /// reference recognizes the longest complete visible name (ADR-002).
    private mutating func attempt(lineTokens tokens: [Token]) -> ExpressionResult {
        var leadingWords = 0
        while leadingWords < tokens.count, case .word = tokens[leadingWords] {
            leadingWords += 1
        }

        let definedNames = variables.definedNames
        var pendingSeen = false
        var pendingAssignment: String?
        var firstFailure: Diagnostic?

        for stripped in 0 ... leadingWords {
            // A function name is never a stray label: the prefix call form
            // parses it with its operand, and stripping would evaluate the
            // bare operand alone (ADK-225).
            if stripped > 0, case .word(let word) = tokens[stripped - 1],
                Language.functionNames.contains(word)
            {
                continue
            }
            let remaining = Array(tokens[stripped ..< tokens.count])
            do {
                let node = try Parser.parse(remaining, definedNames: definedNames)
                let value = try evaluate(node: node)
                if let failure = Numeric.rangeDiagnostic(for: value) {
                    return ExpressionResult(kind: .expression, diagnostic: failure)
                }
                let retained = Numeric.retain(value)
                let display = representation(of: node, for: retained)
                return ExpressionResult(
                    kind: .expression,
                    value: .decimal(retained),
                    display: display
                )
            } catch let lineError as LineError {
                firstFailure = firstFailure ?? lineError.diagnostic
            } catch let diagnostic as Diagnostic {
                firstFailure = firstFailure ?? diagnostic
            } catch ParseError.pending {
                pendingSeen = true
            } catch ParseError.pendingAssignment(let name) {
                pendingSeen = true
                // The deepest attempt names the assignment the line still
                // means: `compras price =` stays short for `price =`.
                pendingAssignment = name
            } catch {
                // The line parses no further: an invalid-syntax candidate.
            }
        }
        if let failure = firstFailure {
            return ExpressionResult(kind: .expression, diagnostic: failure)
        }
        if pendingSeen {
            // An assigned name whose expression never finished stays erred,
            // with no stale value its dependents could use (ADK-223).
            if let name = pendingAssignment {
                variables.fail(name)
            }
            return ExpressionResult(kind: .incomplete)
        }
        return ExpressionResult(kind: .expression, diagnostic: .syntax)
    }

    // MARK: Value evaluation; failures throw the line's diagnostic.

    mutating func evaluate(node: Node, overriding override: Units.Override? = nil) throws -> Decimal {
        switch node {
        case .number(let value):
            return value
        case .quantity(let number, let unit):
            // A `rem` or `em` quantity counts its pixels at the shared
            // Settings base, or the expression-local substitute (ADK-227).
            return try Units.quantityValue(
                of: number, in: unit, pixelBase: Units.pixelBase(in: context, override: override)
            )
        case .conversion(let inner, let target, let localOverride):
            let value = try evaluate(node: inner, overriding: localOverride ?? override)
            return try Units.convert(
                value,
                from: Units.sourceUnit(of: inner),
                to: target,
                context: context,
                override: localOverride ?? override
            )
        case .reference(let name):
            return try resolved(name: name)
        case .unaryMinus(let inner):
            return try Numeric.subtract(
                Decimal(0), try evaluate(node: inner, overriding: override)
            )
        case .call(let name, let arguments):
            var argumentValues: [Decimal] = []
            for functionArgument in arguments {
                argumentValues.append(
                    try evaluate(node: functionArgument, overriding: override)
                )
            }
            return try Functions.apply(name: name, arguments: argumentValues)
        case .binary(let op, let lhsNode, let rhsNode):
            return try evaluateBinary(op, lhsNode, rhsNode, overriding: override)
        case .representation(let kind, let inner):
            // Inside arithmetic, a conversion contributes its value only;
            // the representation shows when the whole line is the
            // conversion (ADK-222).
            let value = try evaluate(node: inner, overriding: override)
            try Display.validate(value, as: kind)
            return value
        case .percentShare(let percent, let base):
            return try Percent.share(
                try evaluate(node: percent, overriding: override),
                of: try evaluate(node: base, overriding: override)
            )
        case .percentOff(let percent, let base):
            return try Percent.off(
                try evaluate(node: percent, overriding: override),
                of: try evaluate(node: base, overriding: override)
            )
        case .percentPortion(let inner):
            return try Percent.portion(try evaluate(node: inner, overriding: override))
        case .assignment(let name, let value):
            do {
                let result = try evaluate(node: value, overriding: override)
                let retained = Numeric.retain(result)
                variables.define(name, .decimal(retained))
                return retained
            } catch let diagnostic as Diagnostic {
                // Neither a stale value nor a silent one: dependents show
                // that the dependency erred.
                variables.fail(name)
                throw diagnostic
            } catch let lineError as LineError {
                variables.fail(name)
                throw lineError.diagnostic
            }
        }
    }

    /// The form a whole line shows beside itself: a representation
    /// conversion its own form, a bare quantity its unit, a unit
    /// conversion the destination unit, and arithmetic the plain locale
    /// number (ADK-222, ADK-227).
    private func representation(of node: Node, for value: Decimal) -> String {
        let precision = context.displayPrecision
        switch node {
        case .representation(let kind, _):
            return Display.format(value, as: kind, precision: precision, locale: locale)
        case .quantity(_, let unit):
            return Units.quantityDisplay(value, in: unit, precision: precision, locale: locale)
        case .conversion(_, let target, _):
            return Units.display(value, in: target, precision: precision, locale: locale)
        default:
            return Numeric.display(value, precision: precision, locale: locale)
        }
    }

    private mutating func evaluateBinary(
        _ `operator`: NumericOperator, _ lhsNode: Node, _ rhsNode: Node,
        overriding override: Units.Override? = nil
    ) throws -> Decimal {
        let lhs = try evaluate(node: lhsNode, overriding: override)
        let rhs = try evaluate(node: rhsNode, overriding: override)
        switch `operator` {
        case .add: return try Numeric.add(lhs, rhs)
        case .bitwiseAnd: return try Functions.bitwiseAnd(lhs, rhs)
        case .bitwiseOr: return try Functions.bitwiseOr(lhs, rhs)
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
        try variables.resolve(name)
    }
}

private extension StringProtocol {
    func trimmingLeft() -> SubSequence {
        drop(while: { $0.isWhitespace })
    }
}
