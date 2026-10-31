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
    static let sidebar = dynamic(light: 0xF2F2F4, dark: 0x232326)
    static let sidebarSelection = dynamic(light: 0xE1E1E5, dark: 0x303033)
    static let tertiaryText = dynamic(light: 0x8E8E93, dark: 0x7C7C82)
    static let secondaryText = dynamic(light: 0x636368, dark: 0xA1A1A6)
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
    @State private var sheetTitle = ""
    @FocusState private var titleFocused: Bool
    @State private var sheets: [StoredSheet] = []
    @State private var selectedID: UUID?
    @State private var autosave: SheetAutosave?
    @State private var sheetToDelete: StoredSheet?
    private let store = SheetStore(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Nume/Sheets"))
    private let logger = Logger(subsystem: "Nume", category: "SheetStore")

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                // The title bar row, centered on the window buttons, which draw over the content.
                HStack {
                    Spacer()
                    Button(action: createSheet) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: Palette.secondaryText))
                    .help("New Sheet")
                    .accessibilityLabel("New Sheet")
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(height: 52)
                TextField("Title", text: $sheetTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
                    .focused($titleFocused)
                    .onSubmit(renameSheet)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
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
        .alert("Delete \"\(sheetToDelete?.title ?? "")\"?", isPresented: Binding(
            get: { sheetToDelete != nil },
            set: { if !$0 { sheetToDelete = nil } }
        ), presenting: sheetToDelete) { sheet in
            Button("Delete", role: .destructive) {
                deleteSheet(sheet)
            }
            Button("Cancel", role: .cancel) { sheetToDelete = nil }
        } message: { _ in
            Text("This sheet will be removed permanently and cannot be recovered.")
        }
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
            sheetTitle = sheet.title
            UserDefaults.standard.set(sheet.id.uuidString, forKey: "lastOpenedSheetID")
            openSheet()
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused { renameSheet() }
        }
        .onDisappear { autosave?.flush(); coordinator.closeSheet() }
    }

    /// The sidebar, full height and flush with the window edge, like the Finder,
    /// with room at the top for the window buttons.
    private var sidebar: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 52)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(sheets) { sheet in
                        sidebarRow(sheet)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: Palette.sidebar))
    }

    private func sidebarRow(_ sheet: StoredSheet) -> some View {
        Button {
            selectedID = sheet.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sheet.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(nsColor: Palette.text))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.stamp(of: sheet.updated))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color(nsColor: Palette.tertiaryText))
                }
                Text(Self.preview(of: sheet.text))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Palette.secondaryText))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedID == sheet.id ? Color(nsColor: Palette.sidebarSelection) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Duplicate") { duplicateSheet(sheet) }
            Button("Delete", role: .destructive) { requestDeletion(sheet) }
        }
    }

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return formatter
    }()

    private static func stamp(of date: Date) -> String {
        (Calendar.current.isDateInToday(date) ? timeFormat : dateFormat).string(from: date)
    }

    private static func preview(of text: String) -> String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map(String.init) ?? "No content"
    }

    private func loadSheets() {
        do {
            let result = try store.list()
            sheets = result.sheets
            for skipped in result.skipped {
                logger.error("Skipped \(skipped.url.path): \(skipped.reason)")
            }
            if sheets.isEmpty {
                let sheet = try store.create(title: "Untitled")
                sheets = [sheet]
            }
            let lastOpened = UserDefaults.standard.string(forKey: "lastOpenedSheetID").flatMap(UUID.init(uuidString:))
            selectedID = SheetLaunch.selection(in: sheets.map(\.id), lastOpened: lastOpened)
        } catch {
            logger.error("Could not list sheets: \(error.localizedDescription)")
        }
    }

    private func createSheet() {
        autosave?.flush()
        do {
            let sheet = try store.create(title: "Untitled")
            sheets.insert(sheet, at: 0)
            selectedID = sheet.id
        } catch {
            logger.error("Could not create sheet: \(error.localizedDescription)")
        }
    }

    private func renameSheet() {
        guard let id = selectedID, let sheet = sheets.first(where: { $0.id == id }), sheetTitle != sheet.title else { return }
        do {
            sheets = try SheetActions(store: store).rename(id, title: sheetTitle, sheets: sheets)
        } catch {
            sheetTitle = sheet.title
            logger.error("Could not rename sheet: \(error.localizedDescription)")
        }
    }

    private func duplicateSheet(_ source: StoredSheet) {
        do {
            let result = try SheetActions(store: store).duplicate(source.id, sheets: sheets, selectedID: selectedID)
            sheets = result.sheets
            selectedID = result.copy.id
        } catch {
            logger.error("Could not duplicate sheet: \(error.localizedDescription)")
        }
    }

    private func requestDeletion(_ sheet: StoredSheet) {
        if UserDefaults.standard.bool(forKey: "confirmedFirstSheetDeletion") {
            deleteSheet(sheet)
        } else {
            sheetToDelete = sheet
        }
    }

    private func deleteSheet(_ sheet: StoredSheet) {
        guard let index = sheets.firstIndex(where: { $0.id == sheet.id }) else { return }
        autosave?.flush()
        do {
            try store.delete(sheet.id)
            UserDefaults.standard.set(true, forKey: "confirmedFirstSheetDeletion")
            sheets.remove(at: index)
            if sheets.isEmpty {
                let replacement = try store.create(title: "Untitled")
                sheets = [replacement]
                selectedID = replacement.id
            } else if selectedID == sheet.id {
                selectedID = sheets[min(index, sheets.count - 1)].id
            }
            sheetToDelete = nil
        } catch {
            logger.error("Could not delete sheet: \(error.localizedDescription)")
            sheetToDelete = nil
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
/// has the color of the sheet. The title is hidden, and the window buttons sit
/// lower and farther from the edge, like the Finder.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context _: Context) -> ChromeView {
        ChromeView()
    }

    func updateNSView(_: ChromeView, context _: Context) {}
}

@MainActor
private final class ChromeView: NSView {
    private static let titleBarHeight: CGFloat = 52
    private static let buttonInset: CGFloat = 19
    private static let buttonSpacing: CGFloat = 23

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        configure()
        DispatchQueue.main.async { [weak self] in self?.configure() }
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeWindowButtons() }
            }
        }
    }

    /// Runs twice: SwiftUI sets the window up after this view is attached.
    private func configure() {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = Palette.background
        placeWindowButtons()
    }

    /// The system puts the window buttons back at its own position on every
    /// resize, so this runs again then.
    private func placeWindowButtons() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let bar = window.standardWindowButton(.closeButton)?.superview,
              let container = bar.superview
        else { return }
        let height = Self.titleBarHeight
        container.frame = NSRect(x: 0, y: window.frame.height - height, width: container.frame.width, height: height)
        bar.frame = container.bounds
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in types.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            button.setFrameOrigin(NSPoint(
                x: Self.buttonInset + CGFloat(index) * Self.buttonSpacing,
                y: (height - button.frame.height) / 2
            ))
        }
    }
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
