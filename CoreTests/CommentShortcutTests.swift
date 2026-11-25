@testable import Core
import Foundation
import Testing

struct CommentShortcutTests {
    private func context(
        locale identifier: String = "en_US",
        precision: Int = 10
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: Date(timeIntervalSince1970: 1_791_926_400),
            displayPrecision: precision
        )
    }

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
        let toggled = CommentShortcut.toggle("2 + 2\n// 3 + 3", lines: [0, 1])
        let results = evaluate(sheetText: toggled, context: context())
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.kind == .comment })
        #expect(results.allSatisfy { $0.value == nil && $0.diagnostic == nil })
    }

    @Test
    func toggleOperatesExactlyAtLineStart() {
        #expect(CommentShortcut.toggle("  2 + 2", lines: [0]) == "//   2 + 2")
        #expect(CommentShortcut.toggle("// 2 + 2", lines: [0]) == "2 + 2")
        #expect(CommentShortcut.toggle("//3 + 3", lines: [0]) == "// //3 + 3")
    }

    @Test
    func emptySelectedLineTakesTheMarker() {
        #expect(CommentShortcut.toggle("2 + 2\n", lines: [1]) == "2 + 2\n// ")
    }
}
