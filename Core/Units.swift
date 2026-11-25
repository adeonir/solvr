import Foundation

struct Unit: Sendable, Equatable {
    enum Dimension: Sendable, Equatable { case length, data, temperature, text }

    let dimension: Dimension
    let symbol: String
    let factor: Decimal
    let aliases: Set<String>

    var isRelative: Bool {
        symbol == "em" || symbol == "rem"
    }
}

extension Unit {
    static let metre = Unit(
        dimension: .length, symbol: "m", factor: 1, aliases: ["m", "meter", "meters"]
    )
    static let millimetre = Unit(
        dimension: .length, symbol: "mm", factor: try! Decimal(exact: "0.001"),
        aliases: ["mm", "millimeter", "millimeters"]
    )
    static let centimetre = Unit(
        dimension: .length, symbol: "cm", factor: try! Decimal(exact: "0.01"),
        aliases: ["cm", "centimeter", "centimeters"]
    )
    static let kilometre = Unit(
        dimension: .length, symbol: "km", factor: 1000, aliases: ["km", "kilometer", "kilometers"]
    )
    static let inch = Unit(
        dimension: .length, symbol: "in", factor: try! Decimal(exact: "0.0254"),
        aliases: ["inch", "inches"]
    )
    static let foot = Unit(
        dimension: .length, symbol: "ft", factor: try! Decimal(exact: "0.3048"),
        aliases: ["ft", "foot", "feet"]
    )
    static let yard = Unit(
        dimension: .length, symbol: "yd", factor: try! Decimal(exact: "0.9144"),
        aliases: ["yd", "yard", "yards"]
    )
    static let mile = Unit(
        dimension: .length, symbol: "mi", factor: try! Decimal(exact: "1609.344"),
        aliases: ["mi", "mile", "miles"]
    )

    static let byte = Unit(
        dimension: .data, symbol: "B", factor: 1, aliases: ["b", "byte", "bytes"]
    )
    static let kilobyte = Unit(
        dimension: .data, symbol: "KB", factor: 1000, aliases: ["kb", "kilobyte", "kilobytes"]
    )
    static let megabyte = Unit(
        dimension: .data, symbol: "MB", factor: try! Decimal(exact: "1e6"),
        aliases: ["mb", "megabyte", "megabytes"]
    )
    static let gigabyte = Unit(
        dimension: .data, symbol: "GB", factor: try! Decimal(exact: "1e9"),
        aliases: ["gb", "gigabyte", "gigabytes"]
    )
    static let terabyte = Unit(
        dimension: .data, symbol: "TB", factor: try! Decimal(exact: "1e12"),
        aliases: ["tb", "terabyte", "terabytes"]
    )
    static let kibibyte = Unit(
        dimension: .data, symbol: "KiB", factor: 1024, aliases: ["kib", "kibibyte", "kibibytes"]
    )
    static let mebibyte = Unit(
        dimension: .data, symbol: "MiB", factor: 1024 * 1024, aliases: ["mib", "mebibyte", "mebibytes"]
    )
    static let gibibyte = Unit(
        dimension: .data, symbol: "GiB", factor: 1024 * 1024 * 1024, aliases: ["gib", "gibibyte", "gibibytes"]
    )
    static let tebibyte = Unit(
        dimension: .data, symbol: "TiB", factor: 1024 * 1024 * 1024 * 1024,
        aliases: ["tib", "tebibyte", "tebibytes"]
    )

    static let celsius = Unit(
        dimension: .temperature, symbol: "°C", factor: 1, aliases: ["c", "celsius"]
    )
    static let fahrenheit = Unit(
        dimension: .temperature, symbol: "°F", factor: 1, aliases: ["f", "fahrenheit"]
    )
    static let kelvin = Unit(
        dimension: .temperature, symbol: "K", factor: 1, aliases: ["k", "kelvin"]
    )

    static let pixel = Unit(
        dimension: .text, symbol: "px", factor: 1, aliases: ["px", "pixel", "pixels"]
    )
    static let point = Unit(
        dimension: .text, symbol: "pt", factor: 1, aliases: ["pt", "point", "points"]
    )
    static let em = Unit(
        dimension: .text, symbol: "em", factor: 1, aliases: ["em"]
    )
    static let rem = Unit(
        dimension: .text, symbol: "rem", factor: 1, aliases: ["rem"]
    )
}

enum Units {
    static let allUnits: [Unit] = [
        .metre, .millimetre, .centimetre, .kilometre, .inch, .foot, .yard, .mile,
        .byte, .kilobyte, .megabyte, .gigabyte, .terabyte,
        .kibibyte, .mebibyte, .gibibyte, .tebibyte,
        .celsius, .fahrenheit, .kelvin,
        .pixel, .point, .em, .rem
    ]

    private static let byAlias: [String: Unit] = {
        var index: [String: Unit] = [:]
        for unit in allUnits {
            for alias in unit.aliases {
                index[alias] = unit
            }
        }
        return index
    }()

    static func unit(for word: String) -> Unit? {
        byAlias[word.lowercased()]
    }

    static var reservedNames: Set<String> {
        Set(byAlias.keys)
    }

    private static let kelvinOffset = try! Decimal(exact: "273.15")

    struct Override: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case pixelBase, ppi }
        let kind: Kind
        let value: Decimal

        static func kind(for word: String) -> Kind? {
            switch word.lowercased() {
            case "px": .pixelBase
            case "ppi": .ppi
            default: nil
            }
        }
    }

    static func pixelBase(in context: EvaluationContext, override: Override?) -> Decimal {
        if let override, override.kind == .pixelBase {
            return override.value
        }
        return context.pixelBase
    }

    static func ppi(in context: EvaluationContext, override: Override?) -> Decimal {
        if let override, override.kind == .ppi {
            return override.value
        }
        return context.ppi
    }

    static func quantityValue(
        of number: Decimal, in unit: Unit, pixelBase: Decimal
    ) throws -> Decimal {
        if unit.isRelative {
            return try Numeric.multiply(number, pixelBase)
        }
        return number
    }

    static func sourceUnit(of node: Node) -> Unit? {
        switch node {
        case let .quantity(_, unit): unit
        case let .unaryMinus(inner): sourceUnit(of: inner)
        case let .conversion(_, target, _): target
        case let .binary(op, lhs, rhs): relativeSumUnit(of: op, lhs, rhs)
        default: nil
        }
    }

    static func relativeSumUnit(of op: NumericOperator, _ lhs: Node, _ rhs: Node) -> Unit? {
        guard op == .add || op == .subtract,
              let left = sourceUnit(of: lhs),
              let right = sourceUnit(of: rhs)
        else { return nil }
        if left.isRelative, right == .pixel {
            return left
        }
        if left == .pixel, right.isRelative {
            return right
        }
        if left.isRelative, right.isRelative, isConversion(lhs) != isConversion(rhs) {
            return left
        }
        return nil
    }

    private static func isConversion(_ node: Node) -> Bool {
        switch node {
        case .conversion: true
        case let .unaryMinus(inner): isConversion(inner)
        default: false
        }
    }

    static func convert(
        _ value: Decimal,
        from source: Unit?,
        to target: Unit,
        context: EvaluationContext,
        override: Override?
    ) throws -> Decimal {
        guard let source, source != target else { return value }
        let base = pixelBase(in: context, override: override)
        let density = ppi(in: context, override: override)
        switch (source.dimension, target.dimension) {
        case let (one, other) where one == other:
            switch one {
            case .temperature:
                return try fromCelsius(toCelsius(value, from: source), to: target)
            case .length, .data:
                return try Numeric.divide(
                    Numeric.multiply(value, source.factor), by: target.factor
                )
            case .text:
                return try fromPx(
                    toPx(value, in: source, base: base, ppi: density),
                    to: target, base: base, ppi: density
                )
            }
        case (.length, .text):
            let px = try Numeric.divide(
                Numeric.multiply(Numeric.multiply(value, source.factor), density),
                by: Unit.inch.factor
            )
            return try fromPx(px, to: target, base: base, ppi: density)
        case (.text, .length):
            let metres = try Numeric.divide(
                Numeric.multiply(toPx(value, in: source, base: base, ppi: density), Unit.inch.factor),
                by: density
            )
            return try Numeric.divide(metres, by: target.factor)
        default:
            throw Diagnostic.syntax
        }
    }

    private static func toPx(
        _ value: Decimal, in unit: Unit, base _: Decimal, ppi: Decimal
    ) throws -> Decimal {
        if unit == .point {
            return try Numeric.divide(Numeric.multiply(value, ppi), by: 72)
        }
        return value
    }

    private static func fromPx(
        _ px: Decimal, to unit: Unit, base: Decimal, ppi: Decimal
    ) throws -> Decimal {
        if unit == .point {
            return try Numeric.divide(Numeric.multiply(px, 72), by: ppi)
        }
        if unit.isRelative {
            return try Numeric.divide(px, by: base)
        }
        return px
    }

    private static func toCelsius(_ value: Decimal, from unit: Unit) throws -> Decimal {
        if unit == .celsius {
            return value
        }
        if unit == .kelvin {
            return try Numeric.subtract(value, kelvinOffset)
        }
        return try Numeric.divide(Numeric.multiply(Numeric.subtract(value, 32), 5), by: 9)
    }

    private static func fromCelsius(_ value: Decimal, to unit: Unit) throws -> Decimal {
        if unit == .celsius {
            return value
        }
        if unit == .kelvin {
            return try Numeric.add(value, kelvinOffset)
        }
        return try Numeric.add(Numeric.divide(Numeric.multiply(value, 9), by: 5), 32)
    }

    static func display(
        _ value: Decimal, in unit: Unit, precision: Int, locale: Locale
    ) -> String {
        suffix(Numeric.display(value, precision: precision, locale: locale), of: unit)
    }

    static func quantityDisplay(
        _ value: Decimal, in unit: Unit, precision: Int, locale: Locale
    ) -> String {
        let number = Numeric.display(value, precision: precision, locale: locale)
        if unit.isRelative {
            return number + Unit.pixel.symbol
        }
        return suffix(number, of: unit)
    }

    private static func suffix(_ number: String, of unit: Unit) -> String {
        unit == .pixel || unit.isRelative
            ? number + unit.symbol
            : number + " " + unit.symbol
    }
}
