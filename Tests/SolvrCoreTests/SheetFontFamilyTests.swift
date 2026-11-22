import Foundation
@testable import SolvrCore
import Testing

// A face counts as monospaced by its CoreText trait or by equal glyph
// advances. The fallback family is SF Mono.

struct SheetFontFamilyTests {
    private static func face(
        _ family: String,
        _ name: String? = nil,
        bold: Bool = false,
        italic: Bool = false,
        trait: Bool = false,
        advances: [Double] = [6, 7, 8]
    ) -> InstalledFace {
        InstalledFace(
            family: family,
            name: name ?? "\(family)\(bold ? "-Bold" : "")",
            isBold: bold,
            isItalic: italic,
            hasMonospaceTrait: trait,
            advances: advances
        )
    }

    private static let installed: [InstalledFace] = [
        face("Menlo", trait: true, advances: [7, 7]),
        face("Menlo", bold: true, trait: true, advances: [7, 7]),
        face("Monaco", trait: true, advances: [7, 7]),
        face("Courier New", trait: true, advances: [7, 7]),
        face("FiraCode Nerd Font Mono", trait: true, advances: [7, 7]),
        face("MonoLisa", trait: false, advances: [10, 10, 10]),
        face("Helvetica", advances: [5, 8, 3]),
        face("Osaka", "Osaka", advances: [5, 8, 3]),
        face("Osaka", "Osaka-Mono", trait: true, advances: [7, 7])
    ]

    @Test func listsSFMonoFirstThenTheMonospacedFamiliesInOrder() {
        let families = SheetFonts.monospacedFamilies(in: Self.installed)
        #expect(families.first == "SF Mono")
        #expect(families == ["SF Mono", "Courier New", "FiraCode Nerd Font Mono", "Menlo", "Monaco", "MonoLisa", "Osaka"])
    }

    @Test func listsFamiliesWithTheTraitAndFamiliesWithEqualAdvances() {
        let families = SheetFonts.monospacedFamilies(in: Self.installed)
        for name in ["Menlo", "Monaco", "Courier New", "FiraCode Nerd Font Mono", "MonoLisa"] {
            #expect(families.contains(name))
        }
    }

    @Test func leavesOutAProportionalOnlyFamily() {
        #expect(!SheetFonts.monospacedFamilies(in: Self.installed).contains("Helvetica"))
    }

    @Test func listsAMixedFamilyAndUsesOnlyItsMonospacedFaces() {
        #expect(SheetFonts.monospacedFamilies(in: Self.installed).contains("Osaka"))
        let selection = SheetFonts.selection(for: "Osaka", in: Self.installed)
        #expect(selection?.text.name == "Osaka-Mono")
        #expect(selection?.heading.name == "Osaka-Mono")
    }

    @Test func aSingleGlyphAdvanceDoesNotMakeAFaceMonospaced() {
        let lone = [Self.face("Lone", advances: [7])]
        #expect(!SheetFonts.monospacedFamilies(in: lone).contains("Lone"))
    }

    @Test func listsSFMonoOnceEvenWhenInstalled() {
        let faces = [Self.face("SF Mono", trait: true, advances: [7, 7])]
        #expect(SheetFonts.monospacedFamilies(in: faces) == ["SF Mono"])
    }

    @Test func headingsUseTheMonospacedBoldFaceWhenThereIsOne() {
        let selection = SheetFonts.selection(for: "Menlo", in: Self.installed)
        #expect(selection?.text.name == "Menlo")
        #expect(selection?.heading.name == "Menlo-Bold")
        #expect(selection?.isHeadingSynthetic == false)
    }

    @Test func headingsAreASyntheticBoldOfTheRegularFaceWithoutABoldFace() {
        let selection = SheetFonts.selection(for: "MonoLisa", in: Self.installed)
        #expect(selection?.text.name == "MonoLisa")
        #expect(selection?.heading.name == "MonoLisa")
        #expect(selection?.isHeadingSynthetic == true)
    }

    @Test func aProportionalBoldFaceIsNotUsedForHeadings() {
        let faces = [
            Self.face("Mixed", trait: true, advances: [7, 7]),
            Self.face("Mixed", bold: true, advances: [5, 8, 3])
        ]
        let selection = SheetFonts.selection(for: "Mixed", in: faces)
        #expect(selection?.isHeadingSynthetic == true)
    }

    @Test func textPrefersTheUprightRegularFace() {
        let faces = [
            Self.face("Code", "Code-Italic", italic: true, trait: true, advances: [7, 7]),
            Self.face("Code", "Code-Bold", bold: true, trait: true, advances: [7, 7]),
            Self.face("Code", "Code-Regular", trait: true, advances: [7, 7])
        ]
        let selection = SheetFonts.selection(for: "Code", in: faces)
        #expect(selection?.text.name == "Code-Regular")
        #expect(selection?.heading.name == "Code-Bold")
    }

    @Test func aMissingFamilyResolvesToSFMono() {
        #expect(SheetFonts.resolvedFamily("Gone Mono", in: Self.installed) == "SF Mono")
        #expect(SheetFonts.resolvedFamily("Helvetica", in: Self.installed) == "SF Mono")
    }

    @Test func anInstalledFamilyResolvesToItself() {
        #expect(SheetFonts.resolvedFamily("MonoLisa", in: Self.installed) == "MonoLisa")
        #expect(SheetFonts.resolvedFamily("SF Mono", in: Self.installed) == "SF Mono")
    }

    @Test func aMissingFamilyLeavesTheResolvedNameAsTheDefault() {
        let stored = "MonoLisa"
        let without = Self.installed.filter { $0.family != "MonoLisa" }
        #expect(SheetFonts.resolvedFamily(stored, in: without) == "SF Mono")
        #expect(stored == "MonoLisa")
    }
}
