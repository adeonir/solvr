// Comment and uncomment lines with Cmd + /, owned here as the shared
// `//`-toggle text rule. The shortcut acts on the line with the cursor or
// on every selected line and only adds or removes `// ` at the start of a
// line; the keybinding itself is wired in the editable sheet and checked
// by hand.

import Foundation

/// The model layer of the comment shortcut: the sheet-text toggle that the
/// editable sheet's Cmd + / action must apply.
public enum CommentShortcut {
    /// The marker one toggle adds or removes at a line start.
    private static let marker = "// "

    /// Toggle `// ` exactly at the start of each selected line. When every
    /// selected line already starts with `// `, remove one such marker from
    /// each; any other selection adds the marker to each. Lines outside the
    /// selection stay untouched.
    ///
    /// Sheet lines separate on `\n`; the returned text keeps the same line
    /// count, including a trailing one from a final newline.
    public static func toggle(_ sheetText: String, lines: [Int]) -> String {
        var textLines = sheetText.components(separatedBy: "\n")
        guard lines.allSatisfy({ textLines.indices.contains($0) }) else {
            return sheetText
        }
        let selected = lines.map { textLines[$0] }
        let allCommented = selected.allSatisfy { $0.hasPrefix(marker) }

        for line in lines {
            if allCommented {
                textLines[line] = String(textLines[line].dropFirst(marker.count))
            } else {
                textLines[line] = marker + textLines[line]
            }
        }
        return textLines.joined(separator: "\n")
    }
}
