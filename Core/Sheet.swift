import Foundation

struct SheetEvaluator {
    let context: EvaluationContext
    var variables = VariableTable()
    var convertedTimeZones: Set<TimeZone> = []
    var convertedCities: Set<String> = []

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

        if case .some = Self.headingExpression.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ) {
            return ExpressionResult(kind: .heading)
        }

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

    func carriesEvaluationSignal(_ line: String) -> Bool {
        let operatorCharacters: Set<Character> = ["+", "-", "*", "/", "^", "="]
        if line.contains(where: { $0.isNumber || operatorCharacters.contains($0) }) {
            return true
        }
        for word in line.map({ Tokenizer.isBlank($0) ? " " : $0 }).split(separator: " ") {
            var text = String(word)
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

    private func nameKnown(_ name: String, word: String) -> Bool {
        name == word || name.hasPrefix(word + " ")
    }

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
                if let dateValue = try evaluateDateForm(node) {
                    return ExpressionResult(
                        kind: .expression,
                        value: dateValue,
                        display: dateDisplay(dateValue, showsTimeOfDay: showsTimeOfDay(of: node)),
                        diagnostic: nil,
                        unit: nil,
                        measure: dateMeasure(dateValue)
                    )
                }
                if let timeValue = try evaluateTimeOfDayForm(node) {
                    return ExpressionResult(
                        kind: .expression,
                        value: timeValue,
                        display: timeOfDayDisplay(timeValue)
                    )
                }
                let value = try lineValue(of: node)
                if let failure = Numeric.rangeDiagnostic(for: value) {
                    return ExpressionResult(kind: .expression, diagnostic: failure)
                }
                let retained = Numeric.retain(value)
                let display = representation(of: node, for: retained)
                let stored = try Numeric.retain(storedValue(retained, of: node))
                return ExpressionResult(
                    kind: .expression,
                    value: .decimal(stored),
                    display: display,
                    diagnostic: nil,
                    unit: Units.sourceUnit(of: node),
                    measure: measure(of: node)
                )
            } catch let lineError as LineError {
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
                pendingAssignment = name
            } catch {}
        }
        if let failure = firstFailure {
            return ExpressionResult(kind: .expression, diagnostic: failure)
        }
        if pendingSeen {
            if let name = pendingAssignment {
                variables.fail(name)
            }
            return ExpressionResult(kind: .incomplete)
        }
        return ExpressionResult(kind: .expression, diagnostic: .syntax)
    }

    mutating func evaluate(node: Node, overriding override: Units.Override? = nil) throws -> Decimal {
        switch node {
        case let .number(value):
            return value
        case let .quantity(number, unit):
            return try Units.quantityValue(
                of: number, in: unit, pixelBase: Units.pixelBase(in: context, override: override)
            )
        case let .duration(number, unit):
            return try Numeric.multiply(number, unit.factor)
        case let .durationConversion(inner, _):
            return try evaluate(node: inner, overriding: override)
        case let .toTimespan(inner):
            return try evaluate(node: inner, overriding: override)
        case let .conversion(inner, target, localOverride):
            let effective = localOverride ?? override
            let value = try evaluate(node: inner, overriding: effective)
            if let base = countBase(of: inner, overriding: effective) {
                return try Units.convert(
                    Numeric.multiply(value, base),
                    from: .pixel,
                    to: target,
                    context: context,
                    override: effective
                )
            }
            return try Units.convert(
                value,
                from: Units.sourceUnit(of: inner),
                to: target,
                context: context,
                override: effective
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
            if case let .binary(.divide, numerator, denominator) = inner,
               kind == .percent,
               let ratio = try monetaryRatio(numerator, denominator)
            {
                try Display.validate(ratio, as: kind)
                return ratio
            }
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
                variables.define(name, .decimal(retained), measure: measure(of: value), countBase: countBase(of: value))
                return retained
            } catch let diagnostic as Diagnostic {
                variables.fail(name)
                throw diagnostic
            } catch let lineError as LineError {
                variables.fail(name)
                throw lineError.diagnostic
            }
        case .monetary, .monetaryConversion, .date, .daysUntil, .weekday, .calendarShift,
             .timeOfDay, .timeOfDayConversion:
            throw Diagnostic.syntax
        }
    }

    private func representation(of node: Node, for value: Decimal) -> String {
        let precision = context.displayPrecision
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
        case let .percentPortion(inner):
            switch inner {
            case .percentShare, .percentOff:
                return Display.format(value, as: .percent, precision: precision, locale: locale)
            default:
                return Numeric.display(value, precision: precision, locale: locale)
            }
        case let .percentShare(_, base), let .percentOff(_, base):
            return shareDisplay(of: base, for: value)
        case let .representation(kind, _):
            return Display.format(value, as: kind, precision: precision, locale: locale)
        case let .quantity(_, unit):
            return Units.quantityDisplay(value, in: unit, precision: precision, locale: locale)
        case let .conversion(_, target, _):
            return Units.display(value, in: target, precision: precision, locale: locale)
        case .binary:
            if let unit = Units.sourceUnit(of: node) {
                return Units.display(value, in: unit, precision: precision, locale: locale)
            }
            return Numeric.display(value, precision: precision, locale: locale)
        default:
            return Numeric.display(value, precision: precision, locale: locale)
        }
    }

    private mutating func lineValue(of node: Node) throws -> Decimal {
        if case let .binary(op, lhsNode, rhsNode) = node,
           Units.relativeSumUnit(of: op, lhsNode, rhsNode) != nil
        {
            return try relativeSumCount(op, lhsNode, rhsNode, overriding: nil)
        }
        return try evaluate(node: node)
    }

    private mutating func relativeSumCount(
        _ op: NumericOperator, _ lhsNode: Node, _ rhsNode: Node,
        overriding override: Units.Override?
    ) throws -> Decimal {
        let lhs = try relativeCount(of: lhsNode, overriding: override)
        let rhs = try relativeCount(of: rhsNode, overriding: override)
        return op == .add ? try Numeric.add(lhs, rhs) : try Numeric.subtract(lhs, rhs)
    }

    private mutating func relativeCount(
        of node: Node, overriding override: Units.Override?
    ) throws -> Decimal {
        switch node {
        case let .unaryMinus(inner):
            return try Numeric.subtract(Decimal(0), relativeCount(of: inner, overriding: override))
        case let .quantity(number, unit) where unit.isRelative:
            return number
        case let .conversion(inner, target, localOverride):
            let scoped = localOverride ?? override
            if target.isRelative {
                if Units.sourceUnit(of: inner)?.isRelative == true {
                    return try relativeCount(of: inner, overriding: scoped)
                }
                return try evaluate(node: node, overriding: override)
            }
            let pixels = try evaluate(node: node, overriding: override)
            return try Numeric.divide(pixels, by: Units.pixelBase(in: context, override: scoped))
        default:
            let pixels = try evaluate(node: node, overriding: override)
            return try Numeric.divide(
                pixels, by: Units.pixelBase(in: context, override: override)
            )
        }
    }

    private mutating func evaluateBinary(
        _ operator: NumericOperator, _ lhsNode: Node, _ rhsNode: Node,
        overriding override: Units.Override? = nil
    ) throws -> Decimal {
        if Units.relativeSumUnit(of: `operator`, lhsNode, rhsNode) != nil {
            let count = try relativeSumCount(
                `operator`, lhsNode, rhsNode, overriding: override
            )
            return try Numeric.multiply(count, Units.pixelBase(in: context, override: override))
        }
        let lhs = try evaluate(node: lhsNode, overriding: override)
        let rhs = try evaluate(node: rhsNode, overriding: override)
        switch `operator` {
        case .add: return try addPortion(lhsNode, rhsNode, lhs, rhs)
        case .bitwiseAnd: return try Functions.bitwiseAnd(lhs, rhs)
        case .bitwiseOr: return try Functions.bitwiseOr(lhs, rhs)
        case .subtract:
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

    private mutating func addPortion(
        _ lhsNode: Node, _ rhsNode: Node, _ lhs: Decimal, _ rhs: Decimal
    ) throws -> Decimal {
        let portion: (Decimal, Decimal)? = switch (lhsNode, rhsNode) {
        case let (lhsNode, .percentPortion(inner)):
            try (lhs, evaluate(node: inner))
        case let (.percentPortion(inner), rhsNode):
            try (rhs, evaluate(node: inner))
        default:
            nil
        }
        if let (base, percent) = portion {
            return try Numeric.add(base, Percent.share(percent, of: base))
        }
        return try Numeric.add(lhs, rhs)
    }

    private mutating func monetaryRatio(
        _ numerator: Node, _ denominator: Node
    ) throws -> Decimal? {
        let typedNumerator = try evaluateMonetary(numerator)
        let typedDenominator = try evaluateMonetary(denominator)
        guard case let .money(money) = typedNumerator else {
            return nil
        }
        let denominatorAmount: Decimal
        if case let .money(other) = typedDenominator {
            denominatorAmount = try context.exchangeRates.convert(other, to: money.currency).amount
        } else {
            guard measure(of: denominator) == nil else {
                return nil
            }
            denominatorAmount = try evaluate(node: denominator)
        }
        return try Numeric.divide(money.amount, by: denominatorAmount)
    }

    private func shareDisplay(of base: Node, for value: Decimal) -> String {
        let precision = context.displayPrecision
        if case .percentPortion = base {
            return Display.format(value, as: .percent, precision: precision, locale: locale)
        }
        if let durationUnit = Duration.representativeUnit(of: base) {
            return Duration.count(value, in: durationUnit, precision: precision, locale: locale)
        }
        if case let .quantity(_, unit) = base {
            return Units.quantityDisplay(value, in: unit, precision: precision, locale: locale)
        }
        return Numeric.display(value, precision: precision, locale: locale)
    }

    func measure(of node: Node) -> Measure? {
        switch node {
        case let .quantity(_, unit):
            .unit(unit)
        case let .conversion(_, target, _):
            .unit(target)
        case let .duration(_, unit):
            .time(unit)
        case let .durationConversion(_, target):
            .time(target)
        case let .toTimespan(inner), let .unaryMinus(inner):
            measure(of: inner)
        case let .binary(op, lhs, rhs):
            if let unit = Units.relativeSumUnit(of: op, lhs, rhs) {
                .unit(unit)
            } else {
                combinedMeasure(op, measure(of: lhs), measure(of: rhs))
            }
        case let .reference(name):
            variables.measures[name]
        case let .assignment(_, inner):
            measure(of: inner)
        case let .percentShare(_, base), let .percentOff(_, base):
            measure(of: base)
        default:
            nil
        }
    }

    func countBase(of node: Node, overriding override: Units.Override? = nil) -> Decimal? {
        switch node {
        case let .unaryMinus(inner), let .assignment(_, inner):
            countBase(of: inner, overriding: override)
        case let .conversion(_, target, localOverride):
            target.isRelative ? Units.pixelBase(in: context, override: localOverride ?? override) : nil
        case let .binary(_, lhs, rhs):
            countBase(of: lhs, overriding: override) ?? countBase(of: rhs, overriding: override)
        case let .reference(name):
            variables.countBases[name]
        default:
            nil
        }
    }

    func storedValue(_ value: Decimal, of node: Node) throws -> Decimal {
        guard case let .unit(unit)? = measure(of: node), unit.isRelative else {
            return value
        }
        if case let .binary(op, lhsNode, rhsNode) = node,
           Units.relativeSumUnit(of: op, lhsNode, rhsNode) != nil
        {
            return value
        }
        guard let base = countBase(of: node) else {
            return try Numeric.divide(value, by: context.pixelBase)
        }
        guard base != context.pixelBase else { return value }
        return try Numeric.divide(Numeric.multiply(value, base), by: context.pixelBase)
    }

    private func combinedMeasure(_ op: NumericOperator, _ lhs: Measure?, _ rhs: Measure?) -> Measure? {
        switch (op, lhs, rhs) {
        case let (.add, left?, right?), let (.subtract, left?, right?):
            if left == right {
                return left
            }
            if case .time = left, case .time = right {
                return right
            }
            return nil
        case let (.add, measure?, nil), let (.subtract, measure?, nil), let (.subtract, nil, measure?), let (.add, nil, measure?):
            return measure
        case let (.multiply, measure?, nil), let (.multiply, nil, measure?), let (.divide, measure?, nil):
            return measure
        default:
            return nil
        }
    }

    func dateMeasure(_ value: ExpressionValue) -> Measure? {
        if case .difference = value {
            return .time(Duration.day)
        }
        return nil
    }

    mutating func resolved(name: String) throws -> Decimal {
        try variables.resolve(name)
    }

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
        case let .percentShare(percent, base):
            guard let typedBase = try evaluateMonetary(base),
                  case let .money(baseMoney) = typedBase
            else { return nil }
            let share = try Percent.share(evaluate(node: percent), of: baseMoney.amount)
            return try .money(MonetaryValue(
                amount: Numeric.retain(share),
                currency: baseMoney.currency
            ))
        case let .percentOff(percent, base):
            guard let typedBase = try evaluateMonetary(base),
                  case let .money(baseMoney) = typedBase
            else { return nil }
            let share = try Percent.share(evaluate(node: percent), of: baseMoney.amount)
            return try .money(MonetaryValue(
                amount: Numeric.retain(Numeric.subtract(baseMoney.amount, share)),
                currency: baseMoney.currency
            ))
        default:
            return nil
        }
    }

    private mutating func portionBaseline(
        operator: NumericOperator, percent: Node, baseNode: Node
    ) throws -> TypedValue? {
        guard let typedBase = try evaluateMonetary(baseNode),
              case let .money(baseMoney) = typedBase
        else { return nil }
        let share = try Percent.share(evaluate(node: percent), of: baseMoney.amount)
        let amount = try `operator` == .add
            ? Numeric.add(baseMoney.amount, share)
            : Numeric.subtract(baseMoney.amount, share)
        return try .money(MonetaryValue(
            amount: Numeric.retain(amount),
            currency: baseMoney.currency
        ))
    }

    private mutating func evaluateMonetaryBinary(
        _ op: NumericOperator, _ lhsNode: Node, _ rhsNode: Node
    ) throws -> TypedValue? {
        if op == .add || op == .subtract {
            if case let .percentPortion(percent) = rhsNode,
               let typed = try portionBaseline(operator: op, percent: percent, baseNode: lhsNode)
            {
                return typed
            }
            if op == .add, case let .percentPortion(percent) = lhsNode,
               let typed = try portionBaseline(operator: op, percent: percent, baseNode: rhsNode)
            {
                return typed
            }
        }
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

enum TypedValue: Equatable {
    case money(MonetaryValue)
    case number(Decimal)
}

private extension StringProtocol {
    func trimmingLeft() -> SubSequence {
        drop(while: { $0.isWhitespace })
    }
}
