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
        decimalSeparator = decimal
        groupingSeparator = decimal == "." ? "," : "."
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
        let withoutComment: String = if let commentStart {
            String(rawLine[rawLine.startIndex ..< commentStart])
        } else {
            rawLine
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
            var text = String(word)
            // A function call spells its name straight before the
            // parenthesis; the arguments inside carry no signal on their
            // own (`fromunix(seconds)`).
            if let cut = text.firstIndex(of: "(") {
                text = String(text[text.startIndex ..< cut])
            }
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
            if stripped > 0, case let .word(word) = tokens[stripped - 1],
               Language.functionNames.contains(word) || Money.names[word.lowercased()] != nil
            {
                continue
            }
            let remaining = Array(tokens[stripped ..< tokens.count])
            do {
                let node = try Parser.parse(remaining, definedNames: definedNames)
                if let typed = try evaluateMonetary(node) {
                    switch typed {
                    case let .money(value):
                        if let failure = Numeric.rangeDiagnostic(for: value.amount) {
                            throw failure
                        }
                        return ExpressionResult(kind: .expression, value: .monetary(value), display: Money.display(value, context: context))
                    case let .number(number):
                        if let failure = Numeric.rangeDiagnostic(for: number) {
                            throw failure
                        }
                        return ExpressionResult(
                            kind: .expression,
                            value: .decimal(number),
                            display: Numeric.display(number, precision: context.displayPrecision, locale: locale)
                        )
                    }
                }
                // Date forms carry date values and differences, apart
                // from the numeric magnitudes (ADK-229).
                if let dateValue = try evaluateDateForm(node) {
                    return ExpressionResult(
                        kind: .expression,
                        value: dateValue,
                        display: dateDisplay(dateValue, node: node)
                    )
                }
                // Time-of-day forms carry clock readings, apart from the
                // numeric magnitudes and the calendar dates (ADK-249).
                if let timeValue = try evaluateTimeOfDayForm(node) {
                    return ExpressionResult(
                        kind: .expression,
                        value: timeValue,
                        display: timeOfDayDisplay(timeValue)
                    )
                }
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
                // A multi-word currency name is reserved as a whole; reading
                // its first words as a label would define a variable named
                // by the rest.
                if case let .reservedName(name) = lineError.diagnostic, Money.names[name.lowercased()] != nil {
                    return ExpressionResult(kind: .expression, diagnostic: lineError.diagnostic)
                }
                firstFailure = firstFailure ?? lineError.diagnostic
            } catch let diagnostic as Diagnostic {
                firstFailure = firstFailure ?? diagnostic
            } catch ParseError.pending {
                pendingSeen = true
            } catch let ParseError.pendingAssignment(name) {
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
        case let .number(value):
            return value
        case let .quantity(number, unit):
            // A `rem` or `em` quantity counts its pixels at the shared
            // Settings base, or the expression-local substitute (ADK-227).
            return try Units.quantityValue(
                of: number, in: unit, pixelBase: Units.pixelBase(in: context, override: override)
            )
        case let .duration(number, unit):
            // A duration value anchors on the seconds magnitude of its
            // written quantity (ADK-228).
            return try Numeric.multiply(number, unit.factor)
        case let .durationConversion(inner, _):
            // The conversion is representational: the count only shows;
            // the value keeps its seconds magnitude, so chains compose in
            // their written order without rounding (ADK-228).
            return try evaluate(node: inner, overriding: override)
        case let .toTimespan(inner):
            // The timespan form is representational like the conversion
            // (ADK-228).
            return try evaluate(node: inner, overriding: override)
        case let .conversion(inner, target, localOverride):
            let value = try evaluate(node: inner, overriding: localOverride ?? override)
            return try Units.convert(
                value,
                from: Units.sourceUnit(of: inner),
                to: target,
                context: context,
                override: localOverride ?? override
            )
        case let .reference(name):
            return try resolved(name: name)
        case let .unaryMinus(inner):
            return try Numeric.subtract(
                Decimal(0), evaluate(node: inner, overriding: override)
            )
        case let .call(name, arguments):
            var argumentValues: [Decimal] = []
            for functionArgument in arguments {
                try argumentValues.append(
                    evaluate(node: functionArgument, overriding: override)
                )
            }
            return try Functions.apply(name: name, arguments: argumentValues)
        case let .binary(op, lhsNode, rhsNode):
            return try evaluateBinary(op, lhsNode, rhsNode, overriding: override)
        case let .representation(kind, inner):
            // Inside arithmetic, a conversion contributes its value only;
            // the representation shows when the whole line is the
            // conversion (ADK-222).
            let value = try evaluate(node: inner, overriding: override)
            try Display.validate(value, as: kind)
            return value
        case let .percentShare(percent, base):
            return try Percent.share(
                evaluate(node: percent, overriding: override),
                of: evaluate(node: base, overriding: override)
            )
        case let .percentOff(percent, base):
            return try Percent.off(
                evaluate(node: percent, overriding: override),
                of: evaluate(node: base, overriding: override)
            )
        case let .percentPortion(inner):
            return try Percent.portion(evaluate(node: inner, overriding: override))
        case let .assignment(name, value):
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
        case .monetary, .monetaryConversion, .date, .daysUntil, .weekday, .calendarShift,
             .timeOfDay, .timeOfDayConversion:
            // Date and time-of-day forms carry typed values, not
            // magnitudes; they reach the sheet only as a whole line
            // (ADK-229, ADK-249).
            throw Diagnostic.syntax
        }
    }

    /// The form a whole line shows beside itself: a representation
    /// conversion its own form, a bare quantity its unit, a unit
    /// conversion the destination unit, and arithmetic the plain locale
    /// number (ADK-222, ADK-227).
    private func representation(of node: Node, for value: Decimal) -> String {
        let precision = context.displayPrecision
        // A duration form its own representation, count in unit or
        // composed timespan (ADK-228): a call shows the count in the unit
        // its duration-carrying argument holds, so `round(1 month in
        // days)` returns `30 days`.
        if case let .call(_, arguments) = node,
           let argument = arguments.first(where: { Duration.carriesQuantity(of: $0) }),
           let unit = Duration.representativeUnit(of: argument)
        {
            return Duration.count(value, in: unit, precision: precision, locale: locale)
        }
        if let durationDisplay = durationDisplay(of: node, for: value) {
            return durationDisplay
        }
        switch node {
        case let .representation(kind, _):
            return Display.format(value, as: kind, precision: precision, locale: locale)
        case let .quantity(_, unit):
            return Units.quantityDisplay(value, in: unit, precision: precision, locale: locale)
        case let .conversion(_, target, _):
            return Units.display(value, in: target, precision: precision, locale: locale)
        default:
            return Numeric.display(value, precision: precision, locale: locale)
        }
    }

    private mutating func evaluateBinary(
        _ operator: NumericOperator, _ lhsNode: Node, _ rhsNode: Node,
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
            if case let .percentPortion(inner) = rhsNode {
                let portion = try evaluate(node: inner)
                return try Numeric.subtract(lhs, Percent.share(portion, of: lhs))
            }
            return try Numeric.subtract(lhs, rhs)
        case .multiply: return try Numeric.multiply(lhs, rhs)
        case .divide:
            if rhs == 0 {
                throw Diagnostic.divisionByZero
            }
            return try Numeric.divide(lhs, by: rhs)
        case .power:
            if rhs.isNaN {
                throw Diagnostic.outOfRange
            }
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

    /// Typed monetary evaluation; ordinary numeric/date paths remain unchanged.
    /// A nil result means the node holds no monetary value, and the numeric
    /// path evaluates it.
    mutating func evaluateMonetary(_ node: Node) throws -> TypedValue? {
        switch node {
        case let .monetary(value):
            return .money(MonetaryValue(amount: Numeric.retain(value.amount), currency: value.currency))
        case let .monetaryConversion(inner, target):
            guard case let .money(value)? = try evaluateMonetary(inner) else { throw Diagnostic.syntax }
            return try .money(context.exchangeRates.convert(value, to: target))
        case let .unaryMinus(inner):
            guard let typed = try evaluateMonetary(inner) else { return nil }
            guard case var .money(value) = typed else { throw Diagnostic.syntax }
            value.amount = try Numeric.subtract(0, value.amount)
            return .money(value)
        case let .reference(name):
            if case let .monetary(value) = variables.bindings[name] {
                return .money(value)
            }
            return nil
        case let .binary(op, lhsNode, rhsNode):
            return try evaluateMonetaryBinary(op, lhsNode, rhsNode)
        case let .assignment(name, inner):
            do {
                guard let typed = try evaluateMonetary(inner) else { return nil }
                switch typed {
                case let .money(value):
                    if let failure = Numeric.rangeDiagnostic(for: value.amount) {
                        throw failure
                    }
                    variables.define(name, .monetary(value))
                case let .number(number):
                    variables.define(name, .decimal(number))
                }
                return typed
            } catch {
                variables.fail(name)
                throw error
            }
        default:
            return nil
        }
    }

    /// Addition takes the currency of the second value and subtraction that
    /// of the first, converting the other operand; dividing two monetary
    /// values converts the second to the currency of the first and gives a
    /// plain number; multiplying two keeps the currency of the second.
    private mutating func evaluateMonetaryBinary(
        _ op: NumericOperator, _ lhsNode: Node, _ rhsNode: Node
    ) throws -> TypedValue? {
        let typedLeft = try evaluateMonetary(lhsNode)
        let typedRight = try evaluateMonetary(rhsNode)
        if typedLeft == nil, typedRight == nil {
            return nil
        }
        let left = try typedLeft ?? .number(evaluate(node: lhsNode))
        let right = try typedRight ?? .number(evaluate(node: rhsNode))
        switch (op, left, right) {
        case let (.add, .money(lhs), .money(rhs)):
            let converted = try context.exchangeRates.convert(lhs, to: rhs.currency)
            return try .money(MonetaryValue(amount: Numeric.retain(Numeric.add(converted.amount, rhs.amount)), currency: rhs.currency))
        case let (.subtract, .money(lhs), .money(rhs)):
            let converted = try context.exchangeRates.convert(rhs, to: lhs.currency)
            return try .money(MonetaryValue(amount: Numeric.retain(Numeric.subtract(lhs.amount, converted.amount)), currency: lhs.currency))
        case let (.multiply, .money(lhs), .money(rhs)):
            return try .money(MonetaryValue(amount: Numeric.retain(Numeric.multiply(lhs.amount, rhs.amount)), currency: rhs.currency))
        case let (.multiply, .money(lhs), .number(rhs)):
            return try .money(MonetaryValue(amount: Numeric.retain(Numeric.multiply(lhs.amount, rhs)), currency: lhs.currency))
        case let (.multiply, .number(lhs), .money(rhs)):
            return try .money(MonetaryValue(amount: Numeric.retain(Numeric.multiply(lhs, rhs.amount)), currency: rhs.currency))
        case let (.divide, .money(lhs), .money(rhs)):
            let converted = try context.exchangeRates.convert(rhs, to: lhs.currency)
            guard converted.amount != 0 else { throw Diagnostic.divisionByZero }
            return try .number(Numeric.retain(Numeric.divide(lhs.amount, by: converted.amount)))
        case let (.divide, .money(lhs), .number(rhs)):
            guard rhs != 0 else { throw Diagnostic.divisionByZero }
            return try .money(MonetaryValue(amount: Numeric.retain(Numeric.divide(lhs.amount, by: rhs)), currency: lhs.currency))
        default:
            throw Diagnostic.syntax
        }
    }
}

/// An intermediate result of an expression that holds a monetary value.
enum TypedValue: Equatable {
    case money(MonetaryValue)
    case number(Decimal)
}

private extension StringProtocol {
    func trimmingLeft() -> SubSequence {
        drop(while: { $0.isWhitespace })
    }
}
