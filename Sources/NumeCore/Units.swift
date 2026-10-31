// Units (ADK-227): everyday physical, data, temperature, and CSS
// quantity conversion behind `in`. A conversion keeps the numeric value
// of its expression and shows the destination unit's representation
// beside it. The shared Settings values — the `rem` and `em` pixel base
// and the pixel density — arrive through the evaluation context, and an
// expression-local `at` override substitutes its value for that
// expression only (ADK-220).
//
// Every unit accepts exactly its standard abbreviation and its full name
// singular and plural; matching is not case-sensitive, because unit
// names are reserved (no user variable can hold them). No other alias.
// The inch abbreviation `in` spells the conversion keyword itself, so
// inches accept only their full names.

import Foundation

/// One convertible unit: the dimension its quantities belong to, its
/// display symbol, its factor into the dimension base (metres or bytes;
/// temperature conversions carry their own affine offsets), and the exact
/// aliases it accepts.
struct Unit: Sendable, Equatable {
    enum Dimension: Sendable, Equatable { case length, data, temperature, text }

    let dimension: Dimension
    /// The symbol shown beside a converted value.
    let symbol: String
    /// One of the unit in the dimension base.
    let factor: Decimal
    /// Lowercased; lookup is case-insensitive.
    let aliases: Set<String>

    /// The `rem` and `em` counts live relative to the shared pixel base:
    /// their quantity values hold the px count the display shows, and
    /// conversions bind through the base (ADK-227).
    var isRelative: Bool {
        symbol == "em" || symbol == "rem"
    }
}

extension Unit {
    // Length: the metre is the base; the inch's factor moves physical
    // quantities into pixels through the pixel density.
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

    // Data: decimal units take factors of 1000, binary units of 1024.
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

    // Temperature: degrees celsius is the base; the offsets carry the
    // affine steps between the three scales.
    static let celsius = Unit(
        dimension: .temperature, symbol: "°C", factor: 1, aliases: ["c", "celsius"]
    )
    static let fahrenheit = Unit(
        dimension: .temperature, symbol: "°F", factor: 1, aliases: ["f", "fahrenheit"]
    )
    static let kelvin = Unit(
        dimension: .temperature, symbol: "K", factor: 1, aliases: ["k", "kelvin"]
    )

    /// CSS text quantities: pixels, points, and the `rem` and `em` counts
    /// relative to the shared pixel base.
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

/// Quantity conversion: unit lookup, cross-references, and the value and
/// representation of a converted quantity.
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

    /// The unit a word names, or nil when no unit accepts it.
    static func unit(for word: String) -> Unit? {
        byAlias[word.lowercased()]
    }

    /// Every alias any unit accepts; assigning to one is a reserved-name
    /// error (ADK-220).
    static var reservedNames: Set<String> {
        Set(byAlias.keys)
    }

    /// The celsius offset of degrees kelvin.
    private static let kelvinOffset = try! Decimal(exact: "273.15")

    /// One `at N <unit>` clause the parser stores with a conversion: its
    /// value substitutes the Settings reference only inside that
    /// expression (ADK-227).
    struct Override: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case pixelBase, ppi }
        let kind: Kind
        let value: Decimal

        /// The kind an `at N <unit>` word names: pixels substitute the
        /// `rem` and `em` base, pixels per inch the pixel density.
        static func kind(for word: String) -> Kind? {
            switch word.lowercased() {
            case "px": .pixelBase
            case "ppi": .ppi
            default: nil
            }
        }
    }

    /// The pixel base a quantity or conversion reads: the `at Npx`
    /// substitute, or the shared Settings value (ADK-220).
    static func pixelBase(in context: EvaluationContext, override: Override?) -> Decimal {
        if let override, override.kind == .pixelBase {
            return override.value
        }
        return context.pixelBase
    }

    /// The pixel density a conversion reads: the `at N ppi` substitute,
    /// or the shared Settings value (ADK-220).
    static func ppi(in context: EvaluationContext, override: Override?) -> Decimal {
        if let override, override.kind == .ppi {
            return override.value
        }
        return context.ppi
    }

    // MARK: Quantity values

    /// The numeric value a bare quantity holds. A `rem` or `em` quantity
    /// counts its pixels at the shared Settings base, so the value equals
    /// what the line displays; every other quantity keeps its own count.
    static func quantityValue(
        of number: Decimal, in unit: Unit, pixelBase: Decimal
    ) throws -> Decimal {
        if unit.isRelative {
            return try Numeric.multiply(number, pixelBase)
        }
        return number
    }

    /// The unit an operand carries, read from the shape of its node: a
    /// quantity's own unit, a negated quantity's unit, or the destination
    /// of a chained conversion.
    static func sourceUnit(of node: Node) -> Unit? {
        switch node {
        case let .quantity(_, unit): unit
        case let .unaryMinus(inner): sourceUnit(of: inner)
        case let .conversion(_, target, _): target
        default: nil
        }
    }

    // MARK: Conversions

    /// Convert a magnitude from its source unit (nil when the value
    /// carries no unit and the destination names it) into the target
    /// unit. Cross-dimension conversions bridge only through pixels; a
    /// dimension pair the language does not define is invalid syntax.
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

    /// A text quantity in pixels: pixels stay, points scale by the pixel
    /// density over 72, and the relative `rem` and `em` counts already
    /// carry their px count through `quantityValue`.
    private static func toPx(
        _ value: Decimal, in unit: Unit, base _: Decimal, ppi: Decimal
    ) throws -> Decimal {
        if unit == .point {
            return try Numeric.divide(Numeric.multiply(value, ppi), by: 72)
        }
        return value
    }

    /// The px count re-expressed in the target text unit: pixels stay,
    /// points scale 72 over the pixel density, and the relative counts
    /// divide by the shared pixel base.
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

    /// A temperature in degrees celsius, with the affine steps the
    /// Fahrenheit and Kelvin scales carry.
    private static func toCelsius(_ value: Decimal, from unit: Unit) throws -> Decimal {
        if unit == .celsius {
            return value
        }
        if unit == .kelvin {
            return try Numeric.subtract(value, kelvinOffset)
        }
        return try Numeric.divide(Numeric.multiply(Numeric.subtract(value, 32), 5), by: 9)
    }

    /// A degrees-celsius value in the target temperature unit.
    private static func fromCelsius(_ value: Decimal, to unit: Unit) throws -> Decimal {
        if unit == .celsius {
            return value
        }
        if unit == .kelvin {
            return try Numeric.add(value, kelvinOffset)
        }
        return try Numeric.add(Numeric.divide(Numeric.multiply(value, 9), by: 5), 32)
    }

    // MARK: Representations

    /// The representation a converted quantity shows: the displayed
    /// decimal places with locale separators, then the destination unit's
    /// symbol. CSS text units attach without a blank; every other unit
    /// reads after one blank.
    static func display(
        _ value: Decimal, in unit: Unit, precision: Int, locale: Locale
    ) -> String {
        suffix(Numeric.display(value, precision: precision, locale: locale), of: unit)
    }

    /// The representation a bare quantity shows beside its expression: a
    /// relative `rem` or `em` count already holds its px count, which
    /// shows in pixels at the shared Settings base; every other quantity
    /// shows its own count and unit.
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
