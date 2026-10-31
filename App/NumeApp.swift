import AppKit
import NumeCore
import OSLog
import SwiftUI

@main
struct NumeApp: App {
    var body: some Scene {
        WindowGroup("Nume") {
            SheetEditorView()
        }
        .defaultSize(width: 648, height: 498)
    }
}

/// The colors of the window design, light and dark, resolved by the system
/// appearance at draw time.
private enum Palette {
    static let background = dynamic(light: 0xFFFFFF, dark: 0x1E1E1E)
    static let text = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let lineNumber = dynamic(light: 0xC7C7CC, dark: 0x505055)
    static let lineNumberActive = dynamic(light: 0x8E8E93, dark: 0x8E8E93)
    static let result = dynamic(light: 0x0062CC, dark: 0x4DA3FF)
    static let error = dynamic(light: 0xD70015, dark: 0xFF453A)
    static let caret = dynamic(light: 0x007AFF, dark: 0x0A84FF)
    static let activeLine = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.05)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            rgb(appearance.isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@MainActor
private struct SheetEditorView: View {
    @State private var coordinator = SheetRefreshCoordinator()
    @State private var sheetText = ""
    @State private var sheets: [StoredSheet] = []
    @State private var selectedID: UUID?
    @State private var autosave: SheetAutosave?
    private let store = SheetStore(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Nume/Sheets"))
    private let logger = Logger(subsystem: "Nume", category: "SheetStore")

    var body: some View {
        VStack(spacing: 0) {
            // Room for the title bar, which draws over the content.
            Color.clear.frame(height: 52)
            HStack(spacing: 0) {
                VStack {
                    List(sheets, selection: $selectedID) { sheet in
                        Text(sheet.title).tag(sheet.id)
                    }
                    Button("New Sheet", action: createSheet)
                        .padding()
                }
                .frame(width: 180)
                Divider()
                SheetTextView(text: $sheetText, results: coordinator.results.map(SheetLineResult.init)) { updatedText in
                    sheetText = updatedText
                    coordinator.sheetTextEdited(updatedText)
                    guard let id = selectedID, let index = sheets.firstIndex(where: { $0.id == id }) else { return }
                    let old = sheets.remove(at: index)
                    sheets.insert(StoredSheet(id: old.id, title: old.title, created: old.created, updated: Date(), text: updatedText), at: 0)
                    autosave?.edit(id, text: updatedText)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .background(Color(nsColor: Palette.background).ignoresSafeArea())
        .background(WindowChrome())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if autosave == nil {
                autosave = SheetAutosave(store: store, timer: AppSaveTimer()) { error in
                    logger.error("Could not save sheet: \(error.localizedDescription)")
                }
            }
            loadSheets()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in autosave?.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in autosave?.flush() }
        .onChange(of: selectedID) { _, id in
            guard let sheet = sheets.first(where: { $0.id == id }) else { return }
            sheetText = sheet.text
            openSheet()
        }
        .onDisappear { autosave?.flush(); coordinator.closeSheet() }
    }

    private func loadSheets() {
        do {
            let result = try store.list()
            sheets = result.sheets
            for skipped in result.skipped {
                logger.error("Skipped \(skipped.url.path): \(skipped.reason)")
            }
            selectedID = sheets.first?.id
        } catch {
            logger.error("Could not list sheets: \(error.localizedDescription)")
        }
    }

    private func createSheet() {
        autosave?.flush()
        do {
            let sheet = try store.create(title: "Untitled")
            loadSheets()
            selectedID = sheet.id
        } catch {
            logger.error("Could not create sheet: \(error.localizedDescription)")
        }
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

@MainActor
private final class AppSaveTimer: SheetSaveTimer {
    private var task: Task<Void, Never>?

    func schedule(afterMilliseconds delay: Int, _ action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Lets the window background show through the title bar, so the title bar
/// has the color of the sheet. The title "Nume" stays drawn.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = Palette.background
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}

/// What the editor draws beside a line: a result, an error message, or nothing.
private struct SheetLineResult: Equatable {
    let text: String
    let isError: Bool

    init(_ result: ExpressionResult) {
        if let diagnostic = result.diagnostic {
            text = diagnostic.message
            isError = true
        } else {
            text = result.display ?? ""
            isError = false
        }
    }
}

private enum Metrics {
    nonisolated(unsafe) static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    nonisolated(unsafe) static let headingFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    static let lineHeight: CGFloat = 26
    static let sidePadding: CGFloat = 24
    static let columnGap: CGFloat = 16
    static let numberColumn = ("000" as NSString).size(withAttributes: [.font: font]).width
    static let bottomPadding: CGFloat = 24
}

private struct SheetTextView: NSViewRepresentable {
    @Binding var text: String
    var results: [SheetLineResult]
    var onEdit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Metrics.bottomPadding, right: 0)

        let textView = ShortcutTextView()
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.insertionPointColor = Palette.caret
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator
        textView.onCommentShortcut = { textView in
            let lineIndexes = context.coordinator.selectedLineIndexes(in: textView)
            let updated = CommentShortcut.toggle(textView.string, lines: lineIndexes)
            textView.string = updated
            textView.applySheetStyle()
            text = updated
            onEdit(updated)
        }
        textView.string = text
        textView.applySheetStyle()
        textView.lineResults = results
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ShortcutTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.applySheetStyle()
        }
        if textView.lineResults != results {
            textView.lineResults = results
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SheetTextView
        init(_ parent: SheetTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? ShortcutTextView else { return }
            view.applySheetStyle()
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
    var onCommentShortcut: ((ShortcutTextView) -> Void)?

    /// The results drawn beside the lines, parallel to the sheet's lines.
    var lineResults: [SheetLineResult] = [] {
        didSet {
            updateContainerWidth()
            needsDisplay = true
        }
    }

    private var resultsReserve: CGFloat {
        let widest = lineResults
            .map { ($0.text as NSString).size(withAttributes: [.font: Metrics.font]).width }
            .max() ?? 0
        return widest > 0 ? widest + Metrics.columnGap : 0
    }

    private var leadingInset: CGFloat {
        Metrics.sidePadding + Metrics.numberColumn + Metrics.columnGap
    }

    private var lineParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = Metrics.lineHeight
        style.maximumLineHeight = Metrics.lineHeight
        return style
    }

    /// Gives every line the design's fixed height, the text color, and the
    /// bold heading look, so the numbers and results drawn beside a line
    /// stay level with it.
    func applySheetStyle() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let base: [NSAttributedString.Key: Any] = [
            .font: Metrics.font,
            .foregroundColor: Palette.text,
            .paragraphStyle: lineParagraphStyle,
            .baselineOffset: (Metrics.lineHeight - Metrics.font.boundingRectForFont.height) / 2 + 2.75
        ]
        typingAttributes = base
        let source = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: source.length))
        var location = 0
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            if source.substring(with: line).hasPrefix("#") {
                storage.addAttribute(.font, value: Metrics.headingFont, range: line)
            }
            location = NSMaxRange(line)
        }
        storage.endEditing()
        textContainerInset = NSSize(width: leadingInset, height: 0)
        updateContainerWidth()
    }

    private func updateContainerWidth() {
        textContainerInset = NSSize(width: leadingInset, height: 0)
        let width = max(frame.width - leadingInset - Metrics.sidePadding - resultsReserve, 1)
        if textContainer?.size.width != width {
            textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth()
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        needsDisplay = true
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var caret = rect
        caret.size.height = 16
        caret.origin.y = rect.midY - 8
        caret.size.width = 2
        super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let layoutManager, textContainer != nil else {
            super.draw(dirtyRect)
            return
        }
        let lines = lineFragments(layoutManager)
        let activeLine = activeLineIndex()

        if selectedRange().length == 0, let activeLine, activeLine < lines.count {
            let rect = NSRect(
                x: Metrics.sidePadding - Metrics.columnGap,
                y: lines[activeLine].rect.minY,
                width: bounds.width - 2 * (Metrics.sidePadding - Metrics.columnGap),
                height: Metrics.lineHeight
            )
            Palette.activeLine.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }

        for (index, line) in lines.enumerated() {
            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: Metrics.font,
                .foregroundColor: index == activeLine ? Palette.lineNumberActive : Palette.lineNumber
            ]
            let number = "\(index + 1)" as NSString
            let numberSize = number.size(withAttributes: numberAttributes)
            let top = line.rect.minY + line.baseline - Metrics.font.ascender
            number.draw(
                at: NSPoint(x: Metrics.sidePadding + Metrics.numberColumn - numberSize.width, y: top),
                withAttributes: numberAttributes
            )

            guard index < lineResults.count, !lineResults[index].text.isEmpty else { continue }
            let result = lineResults[index]
            let resultAttributes: [NSAttributedString.Key: Any] = [
                .font: Metrics.font,
                .foregroundColor: result.isError ? Palette.error : Palette.result
            ]
            let resultText = result.text as NSString
            let resultSize = resultText.size(withAttributes: resultAttributes)
            resultText.draw(
                at: NSPoint(x: bounds.width - Metrics.sidePadding - resultSize.width, y: top),
                withAttributes: resultAttributes
            )
        }

        super.draw(dirtyRect)
    }

    /// The first line fragment of every line, with its baseline, in view
    /// coordinates. A trailing empty line comes from the extra fragment.
    private func lineFragments(_ layoutManager: NSLayoutManager) -> [(rect: NSRect, baseline: CGFloat)] {
        guard let textContainer else { return [] }
        layoutManager.ensureLayout(for: textContainer)
        let source = string as NSString
        let origin = textContainerOrigin
        var fragments: [(rect: NSRect, baseline: CGFloat)] = []
        var location = 0
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: line.location)
            var rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            let baseline = layoutManager.location(forGlyphAt: glyphIndex).y
            fragments.append((rect, baseline))
            location = NSMaxRange(line)
        }
        if source.length == 0 || source.hasSuffix("\n") {
            var rect = layoutManager.extraLineFragmentRect
            if rect.isEmpty {
                rect = NSRect(x: 0, y: CGFloat(fragments.count) * Metrics.lineHeight, width: 0, height: Metrics.lineHeight)
            }
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            let baseline = fragments.last?.baseline
                ?? (rect.height - (Metrics.font.ascender - Metrics.font.descender)) / 2 + Metrics.font.ascender
            fragments.append((rect, baseline))
        }
        return fragments
    }

    private func activeLineIndex() -> Int? {
        let source = string as NSString
        let caret = min(selectedRange().location, source.length)
        return source.substring(to: caret).filter { $0 == "\n" }.count
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "/"
        {
            onCommentShortcut?(self)
            return
        }
        super.keyDown(with: event)
    }
}
