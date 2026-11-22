import AppKit
import SolvrCore
import OSLog
import SwiftUI

@main
struct SolvrApp: App {
    @NSApplicationDelegateAdaptor(SolvrApplicationDelegate.self) private var appDelegate
    @AppStorage(AppearanceMode.key) private var modeName = AppearanceMode.auto.rawValue

    // Set on the app rather than through preferredColorScheme: a nil color
    // scheme does not return a window to the macOS appearance until the
    // window is activated again.
    private func applyAppearance() {
        NSApp.appearance = AppearanceMode(stored: modeName).appearance
    }

    var body: some Scene {
        WindowGroup("Solvr") {
            SheetEditorView()
                .onChange(of: modeName, initial: true) { applyAppearance() }
        }
        .defaultSize(width: 648, height: 498)

        Settings {
            TabView {
                PrecisionSettingsView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                AppearanceSettingsView()
                    .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            }
            .onChange(of: modeName, initial: true) { applyAppearance() }
        }
    }
}

/// The colors of the window design, taken from the active theme.
private struct Palette: Equatable {
    let background: NSColor
    let text: NSColor
    let lineNumber: NSColor
    let lineNumberActive: NSColor
    let result: NSColor
    let error: NSColor
    let caret: NSColor
    let sidebar: NSColor
    let sidebarSelection: NSColor
    let tertiaryText: NSColor
    let secondaryText: NSColor
    let activeLine: NSColor
    private let syntax: [SyntaxKind: NSColor]

    func color(for kind: SyntaxKind) -> NSColor {
        syntax[kind] ?? text
    }

    init(_ theme: Theme) {
        func color(_ value: ThemeColor) -> NSColor {
            NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        }
        background = color(theme.background)
        text = color(theme.text)
        lineNumber = color(theme.lineNumber)
        lineNumberActive = color(theme.lineNumberActive)
        result = color(theme.result)
        error = color(theme.error)
        caret = color(theme.caret)
        sidebar = color(theme.sidebar)
        sidebarSelection = color(theme.sidebarSelection)
        tertiaryText = color(theme.tertiaryText)
        secondaryText = color(theme.secondaryText)
        activeLine = color(theme.activeLine)
        syntax = Dictionary(uniqueKeysWithValues: SyntaxKind.allCases.map { ($0, color(theme.color(for: $0))) })
    }
}

@MainActor
private struct SheetEditorView: View {
    private let exchangeRates = ApplicationExchangeRates.shared.service
    private let cityTimeZones = ApplicationCityTimeZones.shared.service
    @State private var coordinator = SheetRefreshCoordinator()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceMode.key) private var modeName = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceMode.lightThemeKey) private var lightThemeID = Theme.defaultLight.id
    @AppStorage(AppearanceMode.darkThemeKey) private var darkThemeID = Theme.defaultDark.id
    @AppStorage(PrecisionSettingsView.generalKey) private var generalPrecision = PrecisionSetting.generalDefault
    @AppStorage(PrecisionSettingsView.cryptoKey) private var cryptoPrecision = PrecisionSetting.cryptoDefault
    @AppStorage(AppearanceSettingsView.familyKey) private var fontFamily = SheetTypography.defaultFamily
    @AppStorage(AppearanceSettingsView.sizeKey) private var fontSize = TypographySetting.sizeDefault
    @AppStorage(AppearanceSettingsView.lineHeightKey) private var lineHeight = TypographySetting.lineHeightDefault
    @State private var sheetText = ""
    @State private var sheetTitle = ""
    @FocusState private var titleFocused: Bool
    @State private var sheets: [StoredSheet] = []
    @State private var selectedID: UUID?
    @State private var autosave: SheetAutosave?
    @State private var sheetToDelete: StoredSheet?
    private let store = SheetStore(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Solvr/Sheets"))
    private let logger = Logger(subsystem: "Solvr", category: "SheetStore")

    private var palette: Palette {
        Palette(Theme.active(
            mode: AppearanceMode(stored: modeName),
            systemIsDark: colorScheme == .dark,
            lightID: lightThemeID,
            darkID: darkThemeID
        ))
    }

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
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
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
                SheetTextView(
                    text: $sheetText,
                    results: coordinator.results.map(SheetLineResult.init),
                    typography: typography,
                    palette: palette
                ) { updatedText in
                    sheetText = updatedText
                    coordinator.sheetTextEdited(updatedText)
                    guard let id = selectedID, let index = sheets.firstIndex(where: { $0.id == id }) else { return }
                    let old = sheets.remove(at: index)
                    sheets.insert(StoredSheet(id: old.id, title: old.title, created: old.created, updated: Date(), text: updatedText), at: 0)
                    autosave?.edit(id, text: updatedText)
                }
                // The sheet total sits centered below the content and is absent when no total is available.
                if let total = coordinator.total {
                    SheetTotalView(total: total, palette: palette)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .background(Color(nsColor: palette.sidebar).ignoresSafeArea())
        .background(WindowChrome(background: palette.sidebar))
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .ignoresSafeArea(.container, edges: .top)
        .alert("Delete \"\(sheetToDelete?.title ?? "")\"?", isPresented: Binding(
            get: { sheetToDelete != nil },
            set: {
                if !$0 {
                    sheetToDelete = nil
                }
            }
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
            // Cities the results cannot resolve reach the shared service on
            // every trigger, so a lookup that failed while offline is retried.
            coordinator.requestCityData = { names in
                ApplicationCityTimeZones.shared.resolve(names)
            }
            // The stored family returns to the default when it is no longer
            // installed, so sheets show SF Mono.
            let family = SheetFonts.resolvedFamily(fontFamily, in: InstalledFonts.faces)
            if family != fontFamily {
                fontFamily = family
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
            if !focused {
                renameSheet()
            }
        }
        .onChange(of: exchangeRates.snapshot) { _, snapshot in
            coordinator.exchangeRatesChanged(snapshot)
        }
        .onChange(of: cityTimeZones.snapshot) { _, snapshot in
            coordinator.cityTimeZonesChanged(snapshot)
        }
        .onChange(of: [generalPrecision, cryptoPrecision]) { _, _ in
            coordinator.precisionChanged(
                displayPrecision: storedPrecision.general,
                cryptoPrecision: storedPrecision.crypto
            )
        }
        // The cities the visible results name go to the shared city data
        // service, which looks up a city the cache lacks and refreshes one
        // it holds; the fresh city data reaches the results above.
        .onChange(of: coordinator.cityNames) { _, names in
            ApplicationCityTimeZones.shared.resolve(names)
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
                .background(KnobOpacity())
            }
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: palette.background))
    }

    private func sidebarRow(_ sheet: StoredSheet) -> some View {
        Button {
            selectedID = sheet.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sheet.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(nsColor: palette.text))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.stamp(of: sheet.updated))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color(nsColor: palette.tertiaryText))
                }
                Text(Self.preview(of: sheet.text))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: palette.secondaryText))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedID == sheet.id ? Color(nsColor: palette.activeLine) : Color.clear,
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
                displayPrecision: storedPrecision.general,
                exchangeRates: exchangeRates.snapshot,
                cityTimeZones: cityTimeZones.snapshot,
                cryptoPrecision: storedPrecision.crypto
            )
        )
    }

    /// The sheet typography from Settings; the stored family returns to the
    /// default when it is not installed.
    private var typography: SheetTypography {
        TypographySetting.typography(
            family: SheetFonts.resolvedFamily(fontFamily, in: InstalledFonts.faces),
            size: fontSize,
            lineHeight: lineHeight
        )
    }

    /// The Settings precision values, within their ranges even when the
    /// stored preference is not.
    private var storedPrecision: (general: Int, crypto: Int) {
        (
            PrecisionSetting.stored(generalPrecision, in: PrecisionSetting.generalRange, default: PrecisionSetting.generalDefault),
            PrecisionSetting.stored(cryptoPrecision, in: PrecisionSetting.cryptoRange, default: PrecisionSetting.cryptoDefault)
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
    let background: NSColor

    func makeNSView(context _: Context) -> ChromeView {
        let view = ChromeView()
        view.background = background
        return view
    }

    func updateNSView(_ view: ChromeView, context _: Context) {
        view.background = background
    }
}

@MainActor
private final class ChromeView: NSView {
    var background = NSColor.windowBackgroundColor {
        didSet { window?.backgroundColor = background }
    }

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

    /// A change of appearance rebuilds the title bar, which puts the window
    /// buttons back at the system position.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        placeWindowButtons()
        DispatchQueue.main.async { [weak self] in self?.placeWindowButtons() }
    }

    /// Runs twice: SwiftUI sets the window up after this view is attached.
    private func configure() {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = background
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
        let containerFrame = NSRect(x: 0, y: window.frame.height - height, width: container.frame.width, height: height)
        if container.frame != containerFrame {
            container.frame = containerFrame
        }
        if bar.frame != container.bounds {
            bar.frame = container.bounds
        }
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in types.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let origin = NSPoint(
                x: Self.buttonInset + CGFloat(index) * Self.buttonSpacing,
                y: (height - button.frame.height) / 2
            )
            if button.frame.origin != origin {
                button.setFrameOrigin(origin)
            }
        }
    }
}

private struct KnobOpacity: NSViewRepresentable {
    func makeNSView(context _: Context) -> KnobOpacityView {
        KnobOpacityView()
    }

    func updateNSView(_: KnobOpacityView, context _: Context) {}
}

@MainActor
private final class KnobOpacityView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.enclosingScrollView else { return }
            DimKnobScroller.install(in: scrollView)
        }
    }
}

private final class DimKnobScroller: NSScroller {
    static func install(in scrollView: NSScrollView) {
        guard !(scrollView.verticalScroller is DimKnobScroller) else { return }
        let scroller = DimKnobScroller()
        scroller.alphaValue = 0.35
        scrollView.verticalScroller = scroller
    }

    override class func scrollerWidth(for _: NSControl.ControlSize, scrollerStyle _: NSScroller.Style) -> CGFloat {
        12
    }

    override func drawKnobSlot(in _: NSRect, highlight _: Bool) {}
}

/// The sheet total below the content: a labeled value, centered, that darkens on hover.
private struct SheetTotalView: View {
    let total: String
    let palette: Palette
    @State private var isHovered = false

    var body: some View {
        Text("Total: \(total)")
            .font(.system(size: 12, weight: isHovered ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(Color(nsColor: isHovered ? palette.text : palette.secondaryText))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .onHover { isHovered = $0 }
            .accessibilityLabel("Total \(total)")
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

/// The fonts and line metrics of the sheet editor, built from the sheet
/// typography. SF Mono is the system monospaced font.
private struct Metrics {
    static let sidePadding: CGFloat = 24
    static let columnGap: CGFloat = 16
    static let bottomPadding: CGFloat = 24

    let font: NSFont
    let numberFont: NSFont
    let headingFont: NSFont
    /// Whether headings draw the regular face in a synthetic bold.
    let headingIsSynthetic: Bool
    let lineHeight: CGFloat
    let numberColumn: CGFloat

    init(typography: SheetTypography) {
        let selection = SheetFonts.selection(for: typography.family, in: InstalledFonts.faces)
        font = Self.font(selection?.text.name, size: typography.textSize, weight: .regular)
        numberFont = Self.font(selection?.text.name, size: typography.lineNumberSize, weight: .regular)
        headingFont = Self.font(selection?.heading.name, size: typography.headingSize, weight: .bold)
        headingIsSynthetic = selection?.isHeadingSynthetic ?? false
        lineHeight = typography.lineHeightInPixels
        numberColumn = ("000" as NSString).size(withAttributes: [.font: font]).width
    }

    /// The face by name, or the system monospaced font (SF Mono) without one.
    private static func font(_ name: String?, size: Double, weight: NSFont.Weight) -> NSFont {
        if let name, let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

private struct SheetTextView: NSViewRepresentable {
    @Binding var text: String
    var results: [SheetLineResult]
    var typography: SheetTypography
    var palette: Palette
    var onEdit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        DimKnobScroller.install(in: scrollView)
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Metrics.bottomPadding, right: 0)

        let textView = ShortcutTextView()
        textView.palette = palette
        textView.typography = typography
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.insertionPointColor = palette.caret
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
        textView.palette = palette
        textView.typography = typography
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
    private var metrics = Metrics(typography: .default)

    /// The context the line parts are read in.
    var partsContext = EvaluationContext(
        localeIdentifier: Locale.current.identifier, timeZone: .current, now: Date(), displayPrecision: 2
    )

    /// The theme colors. A change recolors the open sheet at once.
    var palette = Palette(.defaultLight) {
        didSet {
            guard palette != oldValue else { return }
            insertionPointColor = palette.caret
            applySheetStyle()
            needsDisplay = true
        }
    }

    /// The sheet typography. A change rebuilds the fonts and line metrics
    /// and restyles the open sheet at once.
    var typography = SheetTypography.default {
        didSet {
            guard typography != oldValue else { return }
            metrics = Metrics(typography: typography)
            applySheetStyle()
            needsDisplay = true
        }
    }

    /// The results drawn beside the lines, parallel to the sheet's lines.
    var lineResults: [SheetLineResult] = [] {
        didSet {
            updateContainerWidth()
            needsDisplay = true
        }
    }

    private var resultsReserve: CGFloat {
        let widest = lineResults
            .map { ($0.text as NSString).size(withAttributes: [.font: metrics.font]).width }
            .max() ?? 0
        return widest > 0 ? widest + Metrics.columnGap : 0
    }

    private var leadingInset: CGFloat {
        Metrics.sidePadding + metrics.numberColumn + Metrics.columnGap
    }

    /// Lifts the text from the baseline TextKit gives a fixed-height line,
    /// which varies with each font's ascent and leading, to the baseline
    /// that centers the cap height.
    private var textBaselineOffset: CGFloat {
        Self.layoutBaseline(for: metrics.font, style: lineParagraphStyle)
            - Self.centeredBaseline(for: metrics.font, lineHeight: metrics.lineHeight)
    }

    /// The baseline, from the top of the line, that TextKit lays out for
    /// one line in the font with the paragraph style.
    private static func layoutBaseline(for font: NSFont, style: NSParagraphStyle) -> CGFloat {
        let storage = NSTextStorage(string: "0", attributes: [.font: font, .paragraphStyle: style])
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 1000, height: 1000))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return layoutManager.location(forGlyphAt: 0).y
    }

    /// The baseline, from the top of a line, that centers the font's cap
    /// height in the line.
    private static func centeredBaseline(for font: NSFont, lineHeight: CGFloat) -> CGFloat {
        (lineHeight + font.capHeight) / 2
    }

    private var lineParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = metrics.lineHeight
        style.maximumLineHeight = metrics.lineHeight
        return style
    }

    /// Gives every line the design's fixed height, the text color, and the
    /// bold heading look, so the numbers and results drawn beside a line
    /// stay level with it.
    func applySheetStyle() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let base: [NSAttributedString.Key: Any] = [
            .font: metrics.font,
            .foregroundColor: palette.text,
            .paragraphStyle: lineParagraphStyle,
            .baselineOffset: textBaselineOffset
        ]
        typingAttributes = base
        let source = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: source.length))
        let parts = lineParts(sheetText: storage.string, context: partsContext)
        var location = 0
        var lineIndex = 0
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            for part in lineIndex < parts.count ? parts[lineIndex] : [] {
                let range = NSRange(location: line.location + part.range.lowerBound, length: part.range.count)
                guard NSMaxRange(range) <= NSMaxRange(line) else { continue }
                storage.addAttribute(.foregroundColor, value: palette.color(for: part.kind), range: range)
                if part.kind == .heading {
                    storage.addAttribute(.font, value: metrics.headingFont, range: range)
                    if metrics.headingIsSynthetic {
                        storage.addAttribute(.strokeWidth, value: -3, range: range)
                    }
                }
            }
            location = NSMaxRange(line)
            lineIndex += 1
        }
        storage.endEditing()
        textContainerInset = NSSize(width: leadingInset, height: 0)
        updateContainerWidth()
    }

    private var updatingContainerWidth = false

    /// Setting the inset or the container size resizes the frame, which
    /// calls back here; the guard stops that recursion.
    func updateContainerWidth() {
        guard !updatingContainerWidth else { return }
        updatingContainerWidth = true
        defer { updatingContainerWidth = false }
        let inset = NSSize(width: leadingInset, height: 0)
        if textContainerInset != inset {
            textContainerInset = inset
        }
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
                height: metrics.lineHeight
            )
            palette.activeLine.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }

        for (index, line) in lines.enumerated() {
            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: metrics.numberFont,
                .foregroundColor: index == activeLine ? palette.lineNumberActive : palette.lineNumber
            ]
            let number = "\(index + 1)" as NSString
            let numberSize = number.size(withAttributes: numberAttributes)
            // Drawn from the baseline itself: a font's hidden line gap moves
            // the baseline of a point-based draw.
            number.draw(
                with: NSRect(
                    x: Metrics.sidePadding + metrics.numberColumn - numberSize.width,
                    y: line.rect.minY + Self.centeredBaseline(for: metrics.numberFont, lineHeight: metrics.lineHeight),
                    width: numberSize.width,
                    height: 0
                ),
                options: [],
                attributes: numberAttributes
            )
            let baseline = line.rect.minY + Self.centeredBaseline(for: metrics.font, lineHeight: metrics.lineHeight)

            guard index < lineResults.count, !lineResults[index].text.isEmpty else { continue }
            let result = lineResults[index]
            let resultAttributes: [NSAttributedString.Key: Any] = [
                .font: metrics.font,
                .foregroundColor: result.isError ? palette.error : palette.result
            ]
            let resultText = result.text as NSString
            let resultSize = resultText.size(withAttributes: resultAttributes)
            resultText.draw(
                with: NSRect(
                    x: bounds.width - Metrics.sidePadding - resultSize.width,
                    y: baseline,
                    width: resultSize.width,
                    height: 0
                ),
                options: [],
                attributes: resultAttributes
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
            if source.length == 0 || rect.isEmpty {
                rect = NSRect(x: 0, y: CGFloat(fragments.count) * metrics.lineHeight, width: 0, height: metrics.lineHeight)
            }
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            let baseline = fragments.last?.baseline
                ?? (rect.height - (metrics.font.ascender - metrics.font.descender)) / 2 + metrics.font.ascender
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
