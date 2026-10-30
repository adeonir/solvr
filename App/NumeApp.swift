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
                        let resultText = result.diagnostic?.message ?? result.display ?? ""
                        let resultColor: Color = result.diagnostic == nil ? .secondary : .red
                        Text(resultText)
                            .foregroundStyle(resultColor)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding()
            }
            .frame(minWidth: 140)
        }
        .safeAreaPadding(.top, 8)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = ShortcutTextView()
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        textView.onCommentShortcut = { textView in
            let lineIndexes = context.coordinator.selectedLineIndexes(in: textView)
            let updated = CommentShortcut.toggle(textView.string, lines: lineIndexes)
            textView.string = updated
            self.text = updated
            self.onEdit(updated)
        }
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ShortcutTextView else { return }
        if textView.string != text { textView.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SheetTextView
        init(_ parent: SheetTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.onEdit(view.string)
        }

        @MainActor
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
