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
    /// The time zones the visible conversions use, collected as the
    /// evaluation resolves them (ADK-251).
    var convertedTimeZones: Set<TimeZone> = []
    /// The city names the visible conversions use, collected as the
    /// evaluation resolves them (ADK-250), whether or not the city data
    /// holds an outcome for each.
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
                        display: dateDisplay(dateValue, showsTimeOfDay: showsTimeOfDay(of: node)),
                        diagnostic: nil,
                        unit: nil,
                        measure: dateMeasure(dateValue)
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
            let effective = localOverride ?? override
            let value = try evaluate(node: inner, overriding: effective)
            // A relative count of an inner conversion converts from pixels at
            // the base it was counted at, so the outer step stays at the
            // shared base (ADK-254).
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
            // A percent representation over a monetary division is the
            // monetary ratio: the amounts convert and divide, and only the
            // whole-line form shows the percent (ADK-263).
            if case let .binary(.divide, numerator, denominator) = inner,
               kind == .percent,
               let ratio = try monetaryRatio(numerator, denominator)
            {
                try Display.validate(ratio, as: kind)
                return ratio
            }
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
                variables.define(name, .decimal(retained), measure: measure(of: value), countBase: countBase(of: value))
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
        case let .percentPortion(inner):
            // The share forms wrap: a percentage of a percentage comes out
            // as the wrapped share's fraction, so the line shows a percent
            // instead of the bare decimal (ADK-263).
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

    /// The value a whole line holds. A pixel and relative-count sum holds
    /// its relative count, so the line shows in that unit (ADK-257).
    private mutating func lineValue(of node: Node) throws -> Decimal {
        if case let .binary(op, lhsNode, rhsNode) = node,
           Units.relativeSumUnit(of: op, lhsNode, rhsNode) != nil
        {
            return try relativeSumCount(op, lhsNode, rhsNode, overriding: nil)
        }
        return try evaluate(node: node)
    }

    /// A pixel and relative-count sum adds in the relative unit: each
    /// operand counts that unit, and a pixel operand converts at the base
    /// in effect. Its evaluated value is that count in pixels, so an
    /// enclosing conversion reads the same basis as a bare `rem` quantity
    /// (ADK-257).
    private mutating func relativeSumCount(
        _ op: NumericOperator, _ lhsNode: Node, _ rhsNode: Node,
        overriding override: Units.Override?
    ) throws -> Decimal {
        let lhs = try relativeCount(of: lhsNode, overriding: override)
        let rhs = try relativeCount(of: rhsNode, overriding: override)
        return op == .add ? try Numeric.add(lhs, rhs) : try Numeric.subtract(lhs, rhs)
    }

    /// The count an operand holds in its relative unit (ADK-257).
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

    /// The sum two operands make beside a bare `N%`: each percent reads
    /// its base from the value on the other side, so `10 + 40%` adds the
    /// share and `10% + 40` is the same addition (ADK-263). The
    /// subtraction keeps the older right-side form of `X - N%`.
    private mutating func addPortion(
        _ lhsNode: Node, _ rhsNode: Node, _ lhs: Decimal, _ rhs: Decimal
    ) throws -> Decimal {
        let portion: (Decimal, Decimal)?
        switch (lhsNode, rhsNode) {
        case let (lhsNode, .percentPortion(inner)):
            portion = try (lhs, evaluate(node: inner))
        case let (.percentPortion(inner), rhsNode):
            portion = try (rhs, evaluate(node: inner))
        default:
            portion = nil
        }
        if let (base, percent) = portion {
            return try Numeric.add(base, Percent.share(percent, of: base))
        }
        return try Numeric.add(lhs, rhs)
    }

    /// The monetary ratio a percent representation divides: a single
    /// monetary numerator counts as its amount against a plain number, and
    /// two monetary values convert through the exchange rate before the
    /// division (ADK-263). A monetary denominator alone stays outside the
    /// ratio, so plain division keeps its Invalid syntax; the numeric
    /// path evaluates every other pair.
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
            // A denominator carrying a quantity, duration, or any other
            // measure shares nothing with an amount: the numeric path
            // answers with Invalid syntax.
            guard measure(of: denominator) == nil else {
                return nil
            }
            denominatorAmount = try evaluate(node: denominator)
        }
        return try Numeric.divide(money.amount, by: denominatorAmount)
    }

    /// The form the sheet shows for a whole-line percent share or
    /// discount: the base's quantity or duration unit, a percent of a
    /// percent the percent form, otherwise the plain locale number
    /// (ADK-263).
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

    /// The quantity a numeric node adds to a sheet total with (ADK-254).
    /// Arithmetic keeps a quantity only where its value stays in that
    /// quantity's unit: a plain operand joins a unit by addition or
    /// subtraction only for units that count their own magnitude, and by
    /// multiplication or division for any unit.
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
        // A percentage keeps the unit of the base it shares or takes its
        // share off (ADK-263).
        case let .percentShare(_, base), let .percentOff(_, base):
            measure(of: base)
        default:
            nil
        }
    }

    /// The pixel base a relative value was counted at, or nil when the value
    /// holds pixels (ADK-254). A conversion to `rem` or `em` counts at its own
    /// `at` base, or at the shared base; a chain, an arithmetic result, or a
    /// reference keeps the base of the count it carries.
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

    /// The value a numeric result stores, in its measure's unit (ADK-254). A
    /// `rem` or `em` result evaluates to pixels at the shared base (ADK-227),
    /// so it divides by that base. A relative count scales from the base it
    /// was counted at to the shared base first.
    func storedValue(_ value: Decimal, of node: Node) throws -> Decimal {
        guard case let .unit(unit)? = measure(of: node), unit.isRelative else {
            return value
        }
        // A pixel and relative-count sum already holds its count (ADK-257).
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

    /// Two time quantities keep the right operand's time unit, since their
    /// values both hold seconds. A plain operand joins a time or relative
    /// unit by addition or subtraction, since its value sits in the same
    /// seconds or pixels as the quantity's.
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

    /// A calendar-day difference counts its days (ADK-254).
    func dateMeasure(_ value: ExpressionValue) -> Measure? {
        if case .difference = value {
            return .time(Duration.day)
        }
        return nil
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
        case let .percentShare(percent, base):
            // A percentage of a monetary value keeps the currency, and a
            // base without one stays on the numeric path (ADK-263).
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

    /// A bare `N%` beside a monetary value reads the money as its base:
    /// `$100 + 10%` adds the share and `price - 10%` takes it off
    /// (ADK-263). Without money at that base the forms stay on the
    /// numeric path.
    private mutating func portionBaseline(
        `operator`: NumericOperator, percent: Node, baseNode: Node
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

    /// Addition takes the currency of the second value and subtraction that
    /// of the first, converting the other operand; dividing two monetary
    /// values converts the second to the currency of the first and gives a
    /// plain number; multiplying two keeps the currency of the second.
    private mutating func evaluateMonetaryBinary(
        _ op: NumericOperator, _ lhsNode: Node, _ rhsNode: Node
    ) throws -> TypedValue? {
        // The portion form beside money first: the money side holds the
        // base either way (ADK-263).
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
