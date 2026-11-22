import Foundation
@testable import SolvrCore
import Testing

// The shortcut toggles `// ` exactly at the start of the cursor's line or
// of every selected line: a selection whose every line already starts with
// `// ` removes one `// ` from each; any other selection adds `// ` to each.
// Re-evaluating the toggled text shows the commented line's result
// disappearing and returning. The shortcut's keybinding in the editable
// sheet is checked by hand.

struct CommentShortcutTests {
    private func context(
        locale identifier: String = "en_US",
        precision: Int = 10
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: Date(timeIntervalSince1970: 1_791_926_400), // 2026-10-30 00:00 UTC
            displayPrecision: precision
        )
    }

    // MARK: One line under the cursor

    @Test
    func commentsTheCursorLine() {
        #expect(CommentShortcut.toggle("2 + 2", lines: [0]) == "// 2 + 2")
        let result = evaluate(
            sheetText: CommentShortcut.toggle("2 + 2", lines: [0]), context: context()
        )[0]
        #expect(result.kind == .comment)
        #expect(result.value == nil && result.display == nil && result.diagnostic == nil)
    }

    @Test
    func uncommentsTheCursorLineRemovingCommentAndSpace() {
        #expect(CommentShortcut.toggle("// 2 + 2", lines: [0]) == "2 + 2")
        let result = evaluate(
            sheetText: CommentShortcut.toggle("// 2 + 2", lines: [0]), context: context()
        )[0]
        #expect(result.kind == .expression)
        #expect(result.display == "4")
    }

    @Test
    func inlineCommentLineTogglesTwiceToItself() {
        let once = CommentShortcut.toggle("2 + 2 // example", lines: [0])
        #expect(once == "// 2 + 2 // example")
        #expect(CommentShortcut.toggle(once, lines: [0]) == "2 + 2 // example")
        let result = evaluate(sheetText: once, context: context())[0]
        #expect(result.kind == .comment)
        #expect(result.value == nil && result.diagnostic == nil)
    }

    @Test
    func uncommentRemovesExactlyOneCommentMarker() {
        #expect(CommentShortcut.toggle("// // 3 + 3", lines: [0]) == "// 3 + 3")
    }

    // MARK: Several selected lines

    @Test
    func commentsEverySelectedPlainLine() {
        #expect(
            CommentShortcut.toggle("2 + 2\n3 + 3", lines: [0, 1]) == "// 2 + 2\n// 3 + 3"
        )
    }

    @Test
    func uncommentsEverySelectedCommentedLine() {
        #expect(
            CommentShortcut.toggle("// 2 + 2\n// 3 + 3", lines: [0, 1])
                == "2 + 2\n3 + 3"
        )
    }

    @Test
    func mixedSelectionCommentsEverySelectedLine() {
        #expect(
            CommentShortcut.toggle("2 + 2\n// 3 + 3", lines: [0, 1])
                == "// 2 + 2\n// // 3 + 3"
        )
    }

    @Test
    func linesOutsideTheSelectionStayUntouched() {
        #expect(
            CommentShortcut.toggle("2 + 2\ncompras do mês\n3 + 3", lines: [2])
                == "2 + 2\ncompras do mês\n// 3 + 3"
        )
    }

    @Test
    func toggledMixedSelectionLeavesEveryLineCommented() {
        // A comment is a comment however many markers it carries.
        let toggled = CommentShortcut.toggle("2 + 2\n// 3 + 3", lines: [0, 1])
        let results = evaluate(sheetText: toggled, context: context())
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.kind == .comment })
        #expect(results.allSatisfy { $0.value == nil && $0.diagnostic == nil })
    }

    // MARK: Whitespace is not part of the rule

    @Test
    func toggleOperatesExactlyAtLineStart() {
        // An indented line takes the marker at its very start; uncommenting
        // requires `// ` there too.
        #expect(CommentShortcut.toggle("  2 + 2", lines: [0]) == "//   2 + 2")
        #expect(CommentShortcut.toggle("// 2 + 2", lines: [0]) == "2 + 2")
        // A bare `//` without the space is not the commented form of the
        // rule: the toggle adds `// ` in front of it.
        #expect(CommentShortcut.toggle("//3 + 3", lines: [0]) == "// //3 + 3")
    }

    @Test
    func emptySelectedLineTakesTheMarker() {
        #expect(CommentShortcut.toggle("2 + 2\n", lines: [1]) == "2 + 2\n// ")
    }
}
