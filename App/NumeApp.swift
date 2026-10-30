import AppKit
import SwiftUI
import NumeCore

@main
struct NumeApp: App {
    var body: some Scene {
        WindowGroup {
            SheetEditorView()
        }
    }
}

@MainActor
private struct SheetEditorView: View {
    @State private var coordinator = SheetRefreshCoordinator()
    @State private var sheetText = "# Welcome\n2 + 2"

    var body: some View {
        HStack(spacing: 0) {
            SheetTextView(text: $sheetText) { updatedText in
                sheetText = updatedText
                coordinator.sheetTextEdited(updatedText)
            }
            .frame(minWidth: 420, minHeight: 360)

            Divider()

            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(coordinator.results.enumerated()), id: \.offset) { _, result in
                        Text(result.diagnostic?.message ?? result.display ?? "")
                            .foregroundStyle(result.diagnostic == nil ? .secondary : .red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding()
            }
            .frame(minWidth: 140)
        }
        .onAppear(perform: openSheet)
        .onDisappear { coordinator.closeSheet() }
    }

    private func openSheet() {
        let locale = Locale.current
        coordinator.openSheet(
            sheetText,
            in: EvaluationContext(
                localeIdentifier: locale.identifier,
                timeZone: .current,
                now: Date(),
                displayPrecision: 2
            )
        )
    }
}

private struct SheetTextView: NSViewRepresentable {
    @Binding var text: String
    var onEdit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ShortcutTextView {
        let view = ShortcutTextView()
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.delegate = context.coordinator
        view.onCommentShortcut = { textView in
            let lineIndexes = context.coordinator.selectedLineIndexes(in: textView)
            let updated = CommentShortcut.toggle(textView.string, lines: lineIndexes)
            textView.string = updated
            self.text = updated
            self.onEdit(updated)
        }
        view.string = text
        return view
    }

    func updateNSView(_ view: ShortcutTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text { view.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SheetTextView
        init(_ parent: SheetTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.onEdit(view.string)
        }

        func selectedLineIndexes(in view: NSTextView) -> [Int] {
            let source = view.string as NSString
            let selection = view.selectedRange()
            let start = min(selection.location, source.length)
            let end = min(NSMaxRange(selection), source.length)
            let startLine = source.substring(to: start).filter { $0 == "\n" }.count
            let endLine = source.substring(to: end).filter { $0 == "\n" }.count
            return Array(startLine ... endLine)
        }
    }
}

private final class ShortcutTextView: NSTextView {
    var onCommentShortcut: ((NSTextView) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "/" {
            onCommentShortcut?(self)
            return
        }
        super.keyDown(with: event)
    }
}
