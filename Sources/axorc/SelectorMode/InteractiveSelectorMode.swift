import Darwin
import Foundation
import AXorcist
import AppKit

enum InteractiveSelectorCLIError: LocalizedError, Equatable {
    case missingApplication
    case conflictingInputModes
    case invalidMaxDepth(Int)
    case requiresTTY

    var errorDescription: String? {
        switch self {
        case .missingApplication:
            "Interactive mode requires --app."
        case .conflictingInputModes:
            "Interactive mode (-i/--interactive) cannot be combined with JSON input flags or payloads."
        case let .invalidMaxDepth(value):
            "--max-depth must be greater than 0. Received: \(value)."
        case .requiresTTY:
            "Interactive mode requires an interactive terminal (TTY) for stdin and stdout."
        }
    }
}

struct InteractiveSelectorRequest: Equatable {
    let appIdentifier: String
    let initialSelector: String?
    let maxDepth: Int
    let refocusTerminalAfterInteractions: Bool
}

enum InteractiveSelectorRequestBuilder {
    private static let unlimitedMaxDepth = Int.max

    static func build(
        app: String?,
        selector: String?,
        maxDepth: Int?,
        interactive: Bool,
        refocusTerminalAfterInteractions: Bool = false,
        hasStructuredInput: Bool) throws -> InteractiveSelectorRequest?
    {
        guard interactive else { return nil }

        if hasStructuredInput {
            throw InteractiveSelectorCLIError.conflictingInputModes
        }

        let trimmedApp = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedApp, !trimmedApp.isEmpty else {
            throw InteractiveSelectorCLIError.missingApplication
        }

        if let maxDepth, maxDepth <= 0 {
            throw InteractiveSelectorCLIError.invalidMaxDepth(maxDepth)
        }

        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialSelector = (trimmedSelector?.isEmpty ?? true) ? nil : trimmedSelector

        return InteractiveSelectorRequest(
            appIdentifier: trimmedApp,
            initialSelector: initialSelector,
            maxDepth: maxDepth ?? unlimitedMaxDepth,
            refocusTerminalAfterInteractions: refocusTerminalAfterInteractions)
    }
}

@MainActor
enum InteractiveSelectorRunner {
    static func run(request: InteractiveSelectorRequest) throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw InteractiveSelectorCLIError.requiresTTY
        }

        let session = try InteractiveSelectorSession(request: request)
        try session.run()
    }
}

@MainActor
private final class InteractiveSelectorSession {
    private enum Mode {
        case query
        case results
        case search
        case interactionMenu
        case interactionValueInput(InteractionKind)
    }

    private enum InteractionKind {
        case setValue
        case setValueSubmit
        case sendKeystrokesSubmit

        var label: String {
            switch self {
            case .setValue:
                return "set-value"
            case .setValueSubmit:
                return "set-value-submit"
            case .sendKeystrokesSubmit:
                return "send-keystrokes-submit"
            }
        }
    }

    private let request: InteractiveSelectorRequest
    private let runner = SelectorQueryRunner()
    private let colorEnabled: Bool
    private let roleColorizer: InteractiveRoleColorizer
    private let terminalAppPID: pid_t?
    private var rawMode: RawTerminalMode

    private var mode: Mode = .query
    private var running = true

    private var query: String
    private var queryCursorIndex: Int
    private var searchText = ""
    private var searchCursorIndex = 0
    private var pendingValueText = ""
    private var pendingValueCursorIndex = 0

    private var lastReport: SelectorQueryExecutionReport?
    private var results: [SelectorMatchSummary] = []
    private var selectedIndex = 0
    private var scrollOffset = 0
    private var searchMatchIndices: [Int] = []
    private var searchMatchCursor = -1
    private var statusMessage = "Type a selector and press Enter. Press Ctrl+C to exit."
    private var pendingGG = false

    init(request: InteractiveSelectorRequest) throws {
        self.request = request
        self.query = request.initialSelector ?? ""
        self.queryCursorIndex = self.query.count
        self.colorEnabled = OutputCapabilities.stdoutSupportsANSI
        self.roleColorizer = InteractiveRoleColorizer(enabled: OutputCapabilities.stdoutSupportsANSI)
        self.terminalAppPID = request.refocusTerminalAfterInteractions ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        self.rawMode = try RawTerminalMode(fd: STDIN_FILENO)
    }

    func run() throws {
        try self.rawMode.enable()
        self.enterAlternateScreen()
        defer {
            self.leaveAlternateScreen()
            self.rawMode.restore()
        }

        if !self.query.isEmpty {
            self.executeQuery()
        }

        while self.running {
            self.render()
            let key = Self.readKey()
            self.handle(key: key)
        }
    }

    private func executeQuery() {
        let trimmedQuery = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            self.statusMessage = "Query cannot be empty."
            self.mode = .query
            return
        }

        let request = SelectorQueryRequest(
            appIdentifier: self.request.appIdentifier,
            selector: trimmedQuery,
            maxDepth: self.request.maxDepth,
            limit: Int.max,
            colorEnabled: false,
            showPath: false,
            showNameSource: false)

        do {
            let report = try self.runner.execute(request)
            self.lastReport = report
            self.results = report.results
            self.selectedIndex = min(self.selectedIndex, max(0, report.results.count - 1))
            self.scrollOffset = 0
            self.searchMatchIndices = []
            self.searchMatchCursor = -1
            self.statusMessage = "Query complete. \(report.matchedCount) matches."
            self.mode = .results
        } catch let parseError as OXQParseError {
            self.statusMessage = "Parse error: \(parseError.description)"
            self.mode = .query
        } catch let selectorError as SelectorQueryCLIError {
            self.statusMessage = selectorError.localizedDescription
            self.mode = .query
        } catch {
            self.statusMessage = "Query failed: \(error.localizedDescription)"
            self.mode = .query
        }
    }

    private func executeInteraction(_ action: SelectorInteractionAction) {
        guard !self.results.isEmpty else {
            self.statusMessage = "No result selected."
            self.mode = .results
            return
        }

        let trimmedQuery = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            self.statusMessage = "Query cannot be empty."
            self.mode = .query
            return
        }

        let request = SelectorQueryRequest(
            appIdentifier: self.request.appIdentifier,
            selector: trimmedQuery,
            maxDepth: self.request.maxDepth,
            limit: Int.max,
            colorEnabled: false,
            showPath: false,
            showNameSource: false,
            interaction: SelectorInteractionRequest(resultIndex: self.selectedIndex + 1, action: action))

        let shouldRefocusTerminal = self.shouldRefocusTerminal(after: action)
        defer {
            if shouldRefocusTerminal {
                self.refocusTerminalApp()
            }
        }

        do {
            let report = try self.runner.execute(request)
            self.lastReport = report
            self.results = report.results
            self.selectedIndex = min(self.selectedIndex, max(0, self.results.count - 1))
            self.statusMessage = "Interaction '\(action.rawName)' succeeded on result \(self.selectedIndex + 1)."
        } catch let selectorError as SelectorQueryCLIError {
            self.statusMessage = selectorError.localizedDescription
        } catch let parseError as OXQParseError {
            self.statusMessage = "Parse error: \(parseError.description)"
        } catch {
            self.statusMessage = "Interaction failed: \(error.localizedDescription)"
        }

        self.mode = .results
    }

    private func shouldRefocusTerminal(after action: SelectorInteractionAction) -> Bool {
        guard self.request.refocusTerminalAfterInteractions else { return false }
        switch action {
        case .click, .focus, .setValueAndSubmit, .sendKeystrokesAndSubmit:
            return true
        case .press, .setValue:
            return false
        }
    }

    private func refocusTerminalApp() {
        guard let terminalAppPID else { return }
        guard let terminalApp = NSRunningApplication(processIdentifier: terminalAppPID), !terminalApp.isTerminated else {
            return
        }
        _ = terminalApp.activate(options: [])
    }

    private func render() {
        let size = Self.terminalSize()
        var lines: [String] = []
        var cursorPosition: (row: Int, col: Int)?

        lines.append(self.headerLine("axorc interactive app=\(self.request.appIdentifier) max_depth=\(self.maxDepthLabel())"))

        switch self.mode {
        case .query:
            lines.append(self.modeLine("mode=query | Enter run | q clear | Ctrl+C exit"))
            lines.append("")
            let queryPrefix = "query> "
            lines.append(self.queryPromptLine(prefix: queryPrefix, query: self.query))
            cursorPosition = (
                row: lines.count,
                col: min(size.cols, queryPrefix.count + self.queryCursorIndex + 1)
            )
            lines.append("")
            lines.append(self.statusLine(self.statusMessage))

        case .results:
            lines.append(self.modeLine("mode=results | j/k or arrows move | / search | Enter interact | q edit query | Ctrl+C exit"))
            lines.append(self.statsLine(styled: true))
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            lines.append(self.statusLine(self.statusMessage))

        case .search:
            lines.append(self.modeLine("mode=search | Enter apply | Esc cancel"))
            lines.append(self.statsLine(styled: true))
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            let searchPrefix = "search> "
            lines.append(self.promptLine(prefix: searchPrefix, value: self.searchText))
            cursorPosition = (
                row: lines.count,
                col: min(size.cols, searchPrefix.count + self.searchCursorIndex + 1)
            )

        case .interactionMenu:
            lines.append(self.modeLine("mode=interaction | c click | p press | f focus | v set-value | s set-value-submit | k send-keys-submit | q cancel"))
            lines.append(self.statsLine(styled: true))
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            lines.append(self.statusLine(self.statusMessage))

        case let .interactionValueInput(kind):
            lines.append(self.modeLine("mode=\(kind.label) | Enter submit | Esc cancel"))
            lines.append(self.statsLine(styled: true))
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            let valuePrefix = "value> "
            lines.append(self.promptLine(prefix: valuePrefix, value: self.pendingValueText))
            cursorPosition = (
                row: lines.count,
                col: min(size.cols, valuePrefix.count + self.pendingValueCursorIndex + 1)
            )
        }

        if lines.count > size.rows {
            lines = Array(lines.prefix(size.rows))
        }

        let shouldShowCursor: Bool
        switch self.mode {
        case .query, .search, .interactionValueInput:
            shouldShowCursor = true
        case .results, .interactionMenu:
            shouldShowCursor = false
        }

        var output = "\u{001B}[2J\u{001B}[H"
        output += lines.joined(separator: "\r\n")
        if shouldShowCursor, let cursorPosition, cursorPosition.row <= lines.count {
            let safeRow = max(1, min(size.rows, cursorPosition.row))
            let safeCol = max(1, min(size.cols, cursorPosition.col))
            output += "\u{001B}[\(safeRow);\(safeCol)H"
        }
        output += shouldShowCursor ? "\u{001B}[?25h" : "\u{001B}[?25l"
        fputs(output, stdout)
        fflush(stdout)
    }

    private func appendResultLines(into lines: inout [String], terminalRows: Int) {
        guard !self.results.isEmpty else {
            lines.append(self.statusLine("No results."))
            return
        }

        let reservedFooterRows = 2
        let reservedHeaderRows = lines.count
        let viewportHeight = max(1, terminalRows - reservedHeaderRows - reservedFooterRows)
        self.ensureSelectionVisible(viewportHeight: viewportHeight)

        let upperBound = min(self.results.count, self.scrollOffset + viewportHeight)
        for index in self.scrollOffset..<upperBound {
            let result = self.results[index]
            let isSelected = (index == self.selectedIndex)
            let marker = isSelected ? ">" : " "
            let plainLine = "\(marker) [\(index + 1)] \(self.renderedResultLine(result))"
            lines.append(self.decorateResultLine(self.truncate(plainLine, maxLength: 220), role: result.role, selected: isSelected))
        }
    }

    private func renderedResultLine(_ result: SelectorMatchSummary) -> String {
        var parts: [String] = [result.role]
        if let name = self.detailValue(result.resultDisplayName) {
            parts.append("name=\"\(name)\"")
        }
        if let value = self.detailValue(result.resultDisplayValue) {
            parts.append("value=\"\(value)\"")
        }
        if let descriptionText = self.detailValue(result.descriptionText) {
            parts.append("desc=\"\(descriptionText)\"")
        }
        if let identifier = self.detailValue(result.identifier) {
            parts.append("id=\"\(identifier)\"")
        }
        if result.isFocused == true {
            parts.append("focused")
        }
        if result.isEnabled == false {
            parts.append("disabled")
        }
        if let childCount = result.childCount, childCount > 0 {
            parts.append("children=\(childCount)")
        }
        return parts.joined(separator: " ")
    }

    private func statsLine(styled: Bool = false) -> String {
        guard let report = self.lastReport else {
            return "stats no-query"
        }
        let line = "stats elapsed_ms=\(Self.formatMilliseconds(report.elapsedMilliseconds)) traversed=\(report.traversedCount) matched=\(report.matchedCount) shown=\(report.shownCount)"
        return styled ? self.emphasisLine(line) : line
    }

    private func maxDepthLabel() -> String {
        if self.request.maxDepth == Int.max {
            return "unlimited"
        }
        return String(self.request.maxDepth)
    }

    private func handle(key: TerminalKey) {
        if key == .ctrlC {
            self.running = false
            return
        }

        switch self.mode {
        case .query:
            self.handleQueryMode(key: key)
        case .results:
            self.handleResultsMode(key: key)
        case .search:
            self.handleSearchMode(key: key)
        case .interactionMenu:
            self.handleInteractionMenuMode(key: key)
        case let .interactionValueInput(kind):
            self.handleInteractionValueInputMode(key: key, kind: kind)
        }
    }

    private func handleQueryMode(key: TerminalKey) {
        self.pendingGG = false

        switch key {
        case .enter:
            self.executeQuery()

        case .backspace:
            self.deleteCharacterBeforeCursor(in: &self.query, cursor: &self.queryCursorIndex)

        case .optionDelete:
            self.deleteWordBeforeCursor(in: &self.query, cursor: &self.queryCursorIndex)

        case .commandDelete:
            self.deleteToStartOfLine(in: &self.query, cursor: &self.queryCursorIndex)

        case .arrowLeft:
            self.moveCursorLeft(cursor: &self.queryCursorIndex)

        case .arrowRight:
            self.moveCursorRight(in: self.query, cursor: &self.queryCursorIndex)

        case .altArrowLeft:
            self.moveCursorWordLeft(in: self.query, cursor: &self.queryCursorIndex)

        case .altArrowRight:
            self.moveCursorWordRight(in: self.query, cursor: &self.queryCursorIndex)

        case .character("q"):
            self.query = ""
            self.queryCursorIndex = 0
            self.statusMessage = "Query cleared."

        case let .character(character):
            self.insertCharacter(character, into: &self.query, cursor: &self.queryCursorIndex)

        default:
            break
        }
    }

    private func handleResultsMode(key: TerminalKey) {
        let rows = max(1, Self.terminalSize().rows - 8)

        switch key {
        case .character("j"), .arrowDown:
            self.pendingGG = false
            self.moveSelection(by: 1)

        case .character("k"), .arrowUp:
            self.pendingGG = false
            self.moveSelection(by: -1)

        case .pageDown, .ctrlF:
            self.pendingGG = false
            self.moveSelection(by: rows)

        case .pageUp, .ctrlB:
            self.pendingGG = false
            self.moveSelection(by: -rows)

        case .character("g"):
            if self.pendingGG {
                self.pendingGG = false
                self.selectedIndex = 0
            } else {
                self.pendingGG = true
            }

        case .character("G"):
            self.pendingGG = false
            if !self.results.isEmpty {
                self.selectedIndex = self.results.count - 1
            }

        case .character("/"):
            self.pendingGG = false
            self.searchText = ""
            self.searchCursorIndex = 0
            self.mode = .search

        case .character("n"):
            self.pendingGG = false
            self.selectNextSearchMatch(reverse: false)

        case .character("N"):
            self.pendingGG = false
            self.selectNextSearchMatch(reverse: true)

        case .enter:
            self.pendingGG = false
            if self.results.isEmpty {
                self.statusMessage = "No results to interact with."
            } else {
                self.mode = .interactionMenu
            }

        case .character("q"):
            self.pendingGG = false
            self.mode = .query
            self.queryCursorIndex = self.query.count
            self.statusMessage = "Edit query and press Enter to run."

        default:
            self.pendingGG = false
        }
    }

    private func handleSearchMode(key: TerminalKey) {
        switch key {
        case .enter:
            self.applySearch()
            self.mode = .results

        case .escape:
            self.mode = .results
            self.statusMessage = "Search canceled."

        case .backspace:
            self.deleteCharacterBeforeCursor(in: &self.searchText, cursor: &self.searchCursorIndex)

        case .optionDelete:
            self.deleteWordBeforeCursor(in: &self.searchText, cursor: &self.searchCursorIndex)

        case .commandDelete:
            self.deleteToStartOfLine(in: &self.searchText, cursor: &self.searchCursorIndex)

        case .arrowLeft:
            self.moveCursorLeft(cursor: &self.searchCursorIndex)

        case .arrowRight:
            self.moveCursorRight(in: self.searchText, cursor: &self.searchCursorIndex)

        case .altArrowLeft:
            self.moveCursorWordLeft(in: self.searchText, cursor: &self.searchCursorIndex)

        case .altArrowRight:
            self.moveCursorWordRight(in: self.searchText, cursor: &self.searchCursorIndex)

        case let .character(character):
            self.insertCharacter(character, into: &self.searchText, cursor: &self.searchCursorIndex)

        default:
            break
        }
    }

    private func handleInteractionMenuMode(key: TerminalKey) {
        switch key {
        case .character("c"):
            self.executeInteraction(.click)

        case .character("p"):
            self.executeInteraction(.press)

        case .character("f"):
            self.executeInteraction(.focus)

        case .character("v"):
            self.pendingValueText = ""
            self.pendingValueCursorIndex = 0
            self.mode = .interactionValueInput(.setValue)

        case .character("s"):
            self.pendingValueText = ""
            self.pendingValueCursorIndex = 0
            self.mode = .interactionValueInput(.setValueSubmit)

        case .character("k"):
            self.pendingValueText = ""
            self.pendingValueCursorIndex = 0
            self.mode = .interactionValueInput(.sendKeystrokesSubmit)

        case .character("q"), .escape:
            self.mode = .results
            self.statusMessage = "Interaction canceled."

        default:
            break
        }
    }

    private func handleInteractionValueInputMode(key: TerminalKey, kind: InteractionKind) {
        switch key {
        case .enter:
            switch kind {
            case .setValue:
                self.executeInteraction(.setValue(self.pendingValueText))
            case .setValueSubmit:
                self.executeInteraction(.setValueAndSubmit(self.pendingValueText))
            case .sendKeystrokesSubmit:
                self.executeInteraction(.sendKeystrokesAndSubmit(self.pendingValueText))
            }

        case .escape:
            self.mode = .results
            self.statusMessage = "Interaction canceled."

        case .backspace:
            self.deleteCharacterBeforeCursor(in: &self.pendingValueText, cursor: &self.pendingValueCursorIndex)

        case .optionDelete:
            self.deleteWordBeforeCursor(in: &self.pendingValueText, cursor: &self.pendingValueCursorIndex)

        case .commandDelete:
            self.deleteToStartOfLine(in: &self.pendingValueText, cursor: &self.pendingValueCursorIndex)

        case .arrowLeft:
            self.moveCursorLeft(cursor: &self.pendingValueCursorIndex)

        case .arrowRight:
            self.moveCursorRight(in: self.pendingValueText, cursor: &self.pendingValueCursorIndex)

        case .altArrowLeft:
            self.moveCursorWordLeft(in: self.pendingValueText, cursor: &self.pendingValueCursorIndex)

        case .altArrowRight:
            self.moveCursorWordRight(in: self.pendingValueText, cursor: &self.pendingValueCursorIndex)

        case let .character(character):
            self.insertCharacter(character, into: &self.pendingValueText, cursor: &self.pendingValueCursorIndex)

        default:
            break
        }
    }

    private func moveSelection(by delta: Int) {
        guard !self.results.isEmpty else { return }
        let clamped = max(0, min(self.results.count - 1, self.selectedIndex + delta))
        self.selectedIndex = clamped
    }

    private func applySearch() {
        let token = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty else {
            self.searchMatchIndices = []
            self.searchMatchCursor = -1
            self.statusMessage = "Search cleared."
            return
        }

        self.searchMatchIndices = self.results.enumerated().compactMap { index, summary in
            let haystack = self.renderedResultLine(summary).lowercased()
            return haystack.contains(token) ? index : nil
        }

        guard !self.searchMatchIndices.isEmpty else {
            self.searchMatchCursor = -1
            self.statusMessage = "No results matched '\(token)'."
            return
        }

        self.searchMatchCursor = 0
        self.selectedIndex = self.searchMatchIndices[0]
        self.statusMessage = "Search matched \(self.searchMatchIndices.count) results."
    }

    private func selectNextSearchMatch(reverse: Bool) {
        guard !self.searchMatchIndices.isEmpty else {
            self.statusMessage = "No active search matches."
            return
        }

        if reverse {
            if self.searchMatchCursor <= 0 {
                self.searchMatchCursor = self.searchMatchIndices.count - 1
            } else {
                self.searchMatchCursor -= 1
            }
        } else if self.searchMatchCursor >= self.searchMatchIndices.count - 1 {
            self.searchMatchCursor = 0
        } else {
            self.searchMatchCursor += 1
        }

        self.selectedIndex = self.searchMatchIndices[self.searchMatchCursor]
    }

    private func ensureSelectionVisible(viewportHeight: Int) {
        if self.selectedIndex < self.scrollOffset {
            self.scrollOffset = self.selectedIndex
        } else if self.selectedIndex >= self.scrollOffset + viewportHeight {
            self.scrollOffset = self.selectedIndex - viewportHeight + 1
        }

        let maxOffset = max(0, self.results.count - viewportHeight)
        self.scrollOffset = max(0, min(maxOffset, self.scrollOffset))
    }

    private func detailValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered == "nil" || lowered == "null" || lowered == "(null)" || lowered == "<null>" || lowered == "optional(nil)" {
            return nil
        }
        return self.truncate(trimmed.replacingOccurrences(of: "\n", with: " "), maxLength: 80)
    }

    private func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength)) + "..."
    }

    private func headerLine(_ value: String) -> String {
        self.colorize(value, InteractiveANSI.bold + InteractiveANSI.brightCyan)
    }

    private func modeLine(_ value: String) -> String {
        self.colorize(value, InteractiveANSI.brightBlue)
    }

    private func emphasisLine(_ value: String) -> String {
        self.colorize(value, InteractiveANSI.brightMagenta)
    }

    private func promptLine(prefix: String, value: String) -> String {
        if !self.colorEnabled {
            return prefix + value
        }
        return self.colorize(prefix, InteractiveANSI.brightYellow) + value
    }

    private func queryPromptLine(prefix: String, query: String) -> String {
        let highlighted = OXQInteractiveSyntaxHighlighter.highlight(query, enabled: self.colorEnabled)
        if !self.colorEnabled {
            return prefix + highlighted
        }
        return self.colorize(prefix, InteractiveANSI.brightYellow) + highlighted
    }

    private func statusLine(_ value: String) -> String {
        let lowered = value.lowercased()
        if lowered.contains("failed") || lowered.contains("error") || lowered.contains("cannot") {
            return self.colorize(value, InteractiveANSI.brightRed)
        }
        if lowered.contains("succeeded") || lowered.contains("complete") || lowered.contains("matched") {
            return self.colorize(value, InteractiveANSI.brightGreen)
        }
        return self.colorize(value, InteractiveANSI.brightWhite)
    }

    private func selectedMarker(_ value: String) -> String {
        self.colorize(value, InteractiveANSI.bold + InteractiveANSI.brightGreen)
    }

    private func decorateResultLine(_ line: String, role: String, selected: Bool) -> String {
        guard self.colorEnabled else { return line }

        var decorated = line
        if let roleRange = decorated.range(of: role) {
            decorated.replaceSubrange(roleRange, with: self.roleColorizer.colorizeRole(role))
        }

        if selected {
            if let markerRange = decorated.range(of: ">") {
                decorated.replaceSubrange(markerRange, with: self.selectedMarker(">"))
            }
            decorated = self.colorize(decorated, InteractiveANSI.bold)
        }

        return decorated
    }

    private func colorize(_ value: String, _ style: String) -> String {
        guard self.colorEnabled else { return value }
        return style + value + InteractiveANSI.reset
    }

    private func insertCharacter(_ character: Character, into text: inout String, cursor: inout Int) {
        let boundedCursor = max(0, min(text.count, cursor))
        let insertionIndex = text.index(text.startIndex, offsetBy: boundedCursor)
        text.insert(character, at: insertionIndex)
        cursor = boundedCursor + 1
    }

    private func deleteCharacterBeforeCursor(in text: inout String, cursor: inout Int) {
        let boundedCursor = max(0, min(text.count, cursor))
        guard boundedCursor > 0 else {
            cursor = 0
            return
        }

        let deleteStart = text.index(text.startIndex, offsetBy: boundedCursor - 1)
        let deleteEnd = text.index(after: deleteStart)
        text.removeSubrange(deleteStart..<deleteEnd)
        cursor = boundedCursor - 1
    }

    private func deleteWordBeforeCursor(in text: inout String, cursor: inout Int) {
        let characters = Array(text)
        let end = max(0, min(cursor, characters.count))
        guard end > 0 else {
            cursor = 0
            return
        }

        var start = end
        while start > 0, characters[start - 1].isWhitespaceLike {
            start -= 1
        }
        while start > 0, !characters[start - 1].isWhitespaceLike {
            start -= 1
        }

        let deleteStart = text.index(text.startIndex, offsetBy: start)
        let deleteEnd = text.index(text.startIndex, offsetBy: end)
        text.removeSubrange(deleteStart..<deleteEnd)
        cursor = start
    }

    private func deleteToStartOfLine(in text: inout String, cursor: inout Int) {
        let end = max(0, min(cursor, text.count))
        guard end > 0 else {
            cursor = 0
            return
        }
        let deleteEnd = text.index(text.startIndex, offsetBy: end)
        text.removeSubrange(text.startIndex..<deleteEnd)
        cursor = 0
    }

    private func moveCursorLeft(cursor: inout Int) {
        cursor = max(0, cursor - 1)
    }

    private func moveCursorRight(in text: String, cursor: inout Int) {
        cursor = min(text.count, cursor + 1)
    }

    private func moveCursorWordLeft(in text: String, cursor: inout Int) {
        let characters = Array(text)
        var index = max(0, min(cursor, characters.count))

        while index > 0, characters[index - 1].isWhitespaceLike {
            index -= 1
        }
        while index > 0, !characters[index - 1].isWhitespaceLike {
            index -= 1
        }

        cursor = index
    }

    private func moveCursorWordRight(in text: String, cursor: inout Int) {
        let characters = Array(text)
        var index = max(0, min(cursor, characters.count))

        while index < characters.count, characters[index].isWhitespaceLike {
            index += 1
        }
        while index < characters.count, !characters[index].isWhitespaceLike {
            index += 1
        }

        cursor = index
    }

    private func enterAlternateScreen() {
        fputs("\u{001B}[?1049h\u{001B}[2J\u{001B}[H\u{001B}[?25l", stdout)
        fflush(stdout)
    }

    private func leaveAlternateScreen() {
        fputs("\u{001B}[?25h\u{001B}[?1049l", stdout)
        fflush(stdout)
    }

    private static func formatMilliseconds(_ milliseconds: Double) -> String {
        String(format: "%.2f", milliseconds)
    }

    private static func terminalSize() -> (rows: Int, cols: Int) {
        var windowSize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize) == 0 {
            return (
                rows: max(20, Int(windowSize.ws_row)),
                cols: max(60, Int(windowSize.ws_col))
            )
        }
        return (rows: 40, cols: 120)
    }

    private static func readKey() -> TerminalKey {
        guard let firstByte = self.readByte(timeoutMillis: -1) else {
            return .unknown
        }

        switch firstByte {
        case 3:
            return .ctrlC
        case 21:
            // Common mapping for Cmd+Delete / kill-to-beginning-of-line in terminals.
            return .commandDelete
        case 6:
            return .ctrlF
        case 2:
            return .ctrlB
        case 10, 13:
            return .enter
        case 127:
            return .backspace
        case 27:
            return self.readEscapeSequence()
        default:
            if firstByte >= 32, firstByte <= 126, let scalar = UnicodeScalar(Int(firstByte)) {
                return .character(Character(scalar))
            }
            return .unknown
        }
    }

    private static func readEscapeSequence() -> TerminalKey {
        guard let secondByte = self.readByte(timeoutMillis: 15) else {
            return .escape
        }

        // Common meta key fallback when option sends ESC+b / ESC+f.
        if secondByte == 98 || secondByte == 66 {
            return .altArrowLeft
        }
        if secondByte == 102 || secondByte == 70 {
            return .altArrowRight
        }
        if secondByte == 127 || secondByte == 8 {
            return .optionDelete
        }

        guard secondByte == 91 else {
            return .escape
        }

        var sequenceBytes: [UInt8] = []

        while let byte = self.readByte(timeoutMillis: 15) {
            sequenceBytes.append(byte)

            if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 126 {
                break
            }
        }

        guard !sequenceBytes.isEmpty else {
            return .escape
        }

        guard let sequence = String(bytes: sequenceBytes, encoding: .utf8) else {
            return .escape
        }

        switch sequence {
        case "A":
            return .arrowUp
        case "B":
            return .arrowDown
        case "C":
            return .arrowRight
        case "D":
            return .arrowLeft
        case "5~":
            return .pageUp
        case "6~":
            return .pageDown
        default:
            if sequence.hasSuffix("D"),
               sequence.contains(";3") || sequence.contains(";9") || sequence.contains(";7")
            {
                return .altArrowLeft
            }
            if sequence.hasSuffix("C"),
               sequence.contains(";3") || sequence.contains(";9") || sequence.contains(";7")
            {
                return .altArrowRight
            }
            if sequence.contains(";3"), sequence.hasSuffix("~") {
                return .optionDelete
            }
            if sequence.contains(";9"), sequence.hasSuffix("~") {
                return .commandDelete
            }
            return .unknown
        }
    }

    private static func readByte(timeoutMillis: Int32) -> UInt8? {
        var pollDescriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let pollTimeout = timeoutMillis < 0 ? -1 : Int32(timeoutMillis)
        let ready = poll(&pollDescriptor, 1, pollTimeout)
        guard ready > 0, (pollDescriptor.revents & Int16(POLLIN)) != 0 else {
            return nil
        }

        var byte: UInt8 = 0
        let readCount = Darwin.read(STDIN_FILENO, &byte, 1)
        guard readCount == 1 else { return nil }
        return byte
    }
}

private enum TerminalKey: Equatable {
    case character(Character)
    case enter
    case backspace
    case optionDelete
    case commandDelete
    case escape
    case arrowLeft
    case arrowRight
    case altArrowLeft
    case altArrowRight
    case arrowUp
    case arrowDown
    case pageUp
    case pageDown
    case ctrlC
    case ctrlF
    case ctrlB
    case unknown
}

private extension Character {
    var isWhitespaceLike: Bool {
        self.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

enum OXQInteractiveSyntaxHighlighter {
    static let roleColor = InteractiveANSI.brightYellow
    static let attributeColor = InteractiveANSI.orange
    static let stringColor = InteractiveANSI.brightGreen
    static let functionColor = InteractiveANSI.brightBlue
    static let resetColor = InteractiveANSI.reset

    static func highlight(_ query: String, enabled: Bool) -> String {
        guard enabled else { return query }

        var output = ""
        var index = query.startIndex
        var attributeBracketDepth = 0
        var expectingAttributeName = false

        while index < query.endIndex {
            let character = query[index]

            if character == "[" {
                output.append(character)
                attributeBracketDepth += 1
                expectingAttributeName = true
                index = query.index(after: index)
                continue
            }

            if character == "]" {
                output.append(character)
                if attributeBracketDepth > 0 {
                    attributeBracketDepth -= 1
                }
                expectingAttributeName = false
                index = query.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                let (literal, nextIndex) = self.consumeStringLiteral(query, from: index)
                output += self.paint(literal, color: self.stringColor)
                index = nextIndex
                continue
            }

            if character == ":" {
                output.append(character)
                index = query.index(after: index)

                let whitespaceStart = index
                while index < query.endIndex, query[index].isWhitespaceLike {
                    index = query.index(after: index)
                }
                if whitespaceStart < index {
                    output += String(query[whitespaceStart..<index])
                }

                if index < query.endIndex, self.isIdentifierStart(query[index]) {
                    let identifierStart = index
                    index = self.consumeIdentifier(in: query, from: identifierStart)
                    let name = String(query[identifierStart..<index])
                    output += self.paint(name, color: self.functionColor)
                }
                continue
            }

            if attributeBracketDepth > 0 {
                if expectingAttributeName {
                    if character.isWhitespaceLike {
                        output.append(character)
                        index = query.index(after: index)
                        continue
                    }

                    if character == "," {
                        output.append(character)
                        index = query.index(after: index)
                        expectingAttributeName = true
                        continue
                    }

                    if self.isIdentifierStart(character) {
                        let attributeStart = index
                        index = self.consumeIdentifier(in: query, from: attributeStart)
                        let attributeName = String(query[attributeStart..<index])
                        output += self.paint(attributeName, color: self.attributeColor)
                        expectingAttributeName = false
                        continue
                    }

                    output.append(character)
                    index = query.index(after: index)
                    continue
                }

                if character == "," {
                    expectingAttributeName = true
                }
                output.append(character)
                index = query.index(after: index)
                continue
            }

            if self.isIdentifierStart(character) {
                let roleStart = index
                index = self.consumeIdentifier(in: query, from: roleStart)
                let roleName = String(query[roleStart..<index])
                output += self.paint(roleName, color: self.roleColor)
                continue
            }

            output.append(character)
            index = query.index(after: index)
        }

        return output
    }

    private static func paint(_ token: String, color: String) -> String {
        color + token + self.resetColor
    }

    private static func consumeStringLiteral(_ query: String, from startIndex: String.Index) -> (String, String.Index) {
        let quote = query[startIndex]
        var index = query.index(after: startIndex)
        var escaped = false

        while index < query.endIndex {
            let character = query[index]
            if escaped {
                escaped = false
                index = query.index(after: index)
                continue
            }
            if character == "\\" {
                escaped = true
                index = query.index(after: index)
                continue
            }
            if character == quote {
                index = query.index(after: index)
                break
            }
            index = query.index(after: index)
        }

        return (String(query[startIndex..<index]), index)
    }

    private static func consumeIdentifier(in query: String, from start: String.Index) -> String.Index {
        var index = start
        while index < query.endIndex, self.isIdentifierContinue(query[index]) {
            index = query.index(after: index)
        }
        return index
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar) || scalar == "_"
        }
    }

    private static func isIdentifierContinue(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
    }
}

private struct InteractiveRoleColorizer {
    private static let colors = [
        InteractiveANSI.red,
        InteractiveANSI.green,
        InteractiveANSI.yellow,
        InteractiveANSI.blue,
        InteractiveANSI.magenta,
        InteractiveANSI.cyan,
        InteractiveANSI.brightRed,
        InteractiveANSI.brightGreen,
        InteractiveANSI.brightYellow,
        InteractiveANSI.brightBlue,
        InteractiveANSI.brightMagenta,
        InteractiveANSI.brightCyan,
    ]

    let enabled: Bool

    func colorizeRole(_ role: String) -> String {
        guard self.enabled else { return role }

        let color = Self.colors[self.colorIndex(for: role)]
        return color + role + InteractiveANSI.reset
    }

    private func colorIndex(for role: String) -> Int {
        let stableHash = role.utf8.reduce(UInt64(5381)) { partial, byte in
            ((partial << 5) &+ partial) &+ UInt64(byte)
        }
        return Int(stableHash % UInt64(Self.colors.count))
    }
}

private enum InteractiveANSI {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let brightRed = "\u{001B}[91m"
    static let brightGreen = "\u{001B}[92m"
    static let brightYellow = "\u{001B}[93m"
    static let brightBlue = "\u{001B}[94m"
    static let brightMagenta = "\u{001B}[95m"
    static let brightCyan = "\u{001B}[96m"
    static let brightWhite = "\u{001B}[97m"
    static let orange = "\u{001B}[38;5;208m"
}

private struct RawTerminalMode {
    private let fd: Int32
    private let original: termios
    private var enabled = false

    init(fd: Int32) throws {
        self.fd = fd
        var current = termios()
        guard tcgetattr(fd, &current) == 0 else {
            throw InteractiveSelectorCLIError.requiresTTY
        }
        self.original = current
    }

    mutating func enable() throws {
        guard !self.enabled else { return }
        var raw = self.original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0
        guard tcsetattr(self.fd, TCSAFLUSH, &raw) == 0 else {
            throw InteractiveSelectorCLIError.requiresTTY
        }
        self.enabled = true
    }

    func restore() {
        var original = self.original
        _ = tcsetattr(self.fd, TCSAFLUSH, &original)
    }
}
