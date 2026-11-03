// The font families a sheet can use (ADK-262). The app reads the installed
// faces from the system; this file decides which families are monospaced,
// which faces a sheet draws with, and which family it falls back to.

import Foundation

/// One installed font face, as the system reports it.
public struct InstalledFace: Equatable, Sendable {
    public let family: String
    public let name: String
    public let isBold: Bool
    public let isItalic: Bool
    public let hasMonospaceTrait: Bool
    /// The advance widths of a sample of glyphs.
    public let advances: [Double]

    public init(
        family: String,
        name: String,
        isBold: Bool,
        isItalic: Bool,
        hasMonospaceTrait: Bool,
        advances: [Double]
    ) {
        self.family = family
        self.name = name
        self.isBold = isBold
        self.isItalic = isItalic
        self.hasMonospaceTrait = hasMonospaceTrait
        self.advances = advances
    }

    /// A face is monospaced when it carries the CoreText monospace trait or
    /// when its measured glyph advances are equal. CoreText leaves the trait
    /// unset for some monospaced fonts, such as MonoLisa.
    public var isMonospaced: Bool {
        if hasMonospaceTrait {
            return true
        }
        guard let first = advances.first, advances.count > 1 else { return false }
        return advances.allSatisfy { $0 == first }
    }
}

/// The faces a sheet draws a family with.
public struct SheetFontSelection: Equatable, Sendable {
    public let text: InstalledFace
    /// The face for headings: the monospaced bold face, or the regular face
    /// drawn in a synthetic bold.
    public let heading: InstalledFace
    public let isHeadingSynthetic: Bool
}

public enum SheetFonts {
    /// The installed families with at least one monospaced face, SF Mono
    /// first and the rest in alphabetical order.
    public static func monospacedFamilies(in faces: [InstalledFace]) -> [String] {
        let others = Set(faces.filter(\.isMonospaced).map(\.family))
            .subtracting([SheetTypography.defaultFamily])
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return [SheetTypography.defaultFamily] + others
    }

    /// The faces of a family that a sheet uses, or nil when the family has
    /// no monospaced face. The text face is the upright regular face.
    public static func selection(for family: String, in faces: [InstalledFace]) -> SheetFontSelection? {
        let members = faces.filter { $0.family == family && $0.isMonospaced }
        guard let text = members.first(where: { !$0.isBold && !$0.isItalic })
            ?? members.first(where: { !$0.isBold })
            ?? members.first
        else { return nil }
        if let bold = members.first(where: { $0.isBold && !$0.isItalic }) {
            return SheetFontSelection(text: text, heading: bold, isHeadingSynthetic: false)
        }
        return SheetFontSelection(text: text, heading: text, isHeadingSynthetic: true)
    }

    /// The family a sheet shows and the value the stored setting holds: the
    /// chosen family when it is installed with a monospaced face, otherwise
    /// SF Mono. A caller commits the resolved name back to the preference
    /// when the stored family is not installed.
    public static func resolvedFamily(_ chosen: String, in faces: [InstalledFace]) -> String {
        if chosen == SheetTypography.defaultFamily {
            return chosen
        }
        return selection(for: chosen, in: faces) == nil ? SheetTypography.defaultFamily : chosen
    }
}
