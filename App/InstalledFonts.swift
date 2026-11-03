// The font faces installed on this Mac, read from the system once (ADK-262).
// Each face carries its CoreText monospace trait and the measured advances
// of a glyph sample, which SolvrCore uses to decide what counts as monospaced.

import AppKit
import CoreText
import SolvrCore

enum InstalledFonts {
    static let faces: [InstalledFace] = readFaces()

    /// Wide and narrow glyphs: equal advances across them mean monospaced.
    private static let sample = "iIlmW0.-"

    private static func readFaces() -> [InstalledFace] {
        let manager = NSFontManager.shared
        var faces: [InstalledFace] = []
        for family in manager.availableFontFamilies {
            for member in manager.availableMembers(ofFontFamily: family) ?? [] {
                guard member.count >= 4,
                      let name = member[0] as? String,
                      let traits = member[3] as? Int,
                      let font = NSFont(name: name, size: 13)
                else { continue }
                let symbolic = CTFontGetSymbolicTraits(font)
                faces.append(InstalledFace(
                    family: family,
                    name: name,
                    isBold: traits & Int(NSFontTraitMask.boldFontMask.rawValue) != 0,
                    isItalic: traits & Int(NSFontTraitMask.italicFontMask.rawValue) != 0,
                    hasMonospaceTrait: symbolic.contains(.traitMonoSpace),
                    advances: advances(of: font)
                ))
            }
        }
        return faces
    }

    private static func advances(of font: NSFont) -> [Double] {
        let characters = Array(sample.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) else { return [] }
        var widths = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &widths, glyphs.count)
        return widths.map { Double($0.width) }
    }
}
