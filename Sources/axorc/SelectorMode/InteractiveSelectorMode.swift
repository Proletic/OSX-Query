import Darwin
import Foundation
import AXorcist

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
}

enum InteractiveSelectorRequestBuilder {
    private static let unlimitedMaxDepth = Int.max

    static func build(
        app: String?,
        selector: String?,
        maxDepth: Int?,
        interactive: Bool,
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
            maxDepth: maxDepth ?? unlimitedMaxDepth)
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

        var label: String {
            switch self {
            case .setValue:
                return "set-value"
            case .setValueSubmit:
                return "set-value-submit"
            }
        }
    }

    private let request: InteractiveSelectorRequest
    private let runner = SelectorQueryRunner()
    private var rawMode: RawTerminalMode

    private var mode: Mode = .query
    private var running = true

    private var query: String
    private var searchText = ""
    private var pendingValueText = ""

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

    private func render() {
        let size = Self.terminalSize()
        var lines: [String] = []

        lines.append("axorc interactive app=\(self.request.appIdentifier) max_depth=\(self.maxDepthLabel())")

        switch self.mode {
        case .query:
            lines.append("mode=query | Enter run | q clear | Ctrl+C exit")
            lines.append("")
            lines.append("query> \(self.query)")
            lines.append("")
            lines.append(self.statusMessage)

        case .results:
            lines.append("mode=results | j/k or arrows move | / search | Enter interact | q edit query | Ctrl+C exit")
            lines.append(self.statsLine())
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            lines.append(self.statusMessage)

        case .search:
            lines.append("mode=search | Enter apply | Esc cancel")
            lines.append(self.statsLine())
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            lines.append("search> \(self.searchText)")

        case .interactionMenu:
            lines.append("mode=interaction | c click | p press | f focus | v set-value | s set-value-submit | q cancel")
            lines.append(self.statsLine())
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            lines.append(self.statusMessage)

        case let .interactionValueInput(kind):
            lines.append("mode=\(kind.label) | Enter submit | Esc cancel")
            lines.append(self.statsLine())
            lines.append("")
            self.appendResultLines(into: &lines, terminalRows: size.rows)
            lines.append("")
            lines.append("value> \(self.pendingValueText)")
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
        output += lines.joined(separator: "\n")
        output += shouldShowCursor ? "\u{001B}[?25h" : "\u{001B}[?25l"
        fputs(output, stdout)
        fflush(stdout)
    }

    private func appendResultLines(into lines: inout [String], terminalRows: Int) {
        guard !self.results.isEmpty else {
            lines.append("No results.")
            return
        }

        let reservedFooterRows = 2
        let reservedHeaderRows = lines.count
        let viewportHeight = max(1, terminalRows - reservedHeaderRows - reservedFooterRows)
        self.ensureSelectionVisible(viewportHeight: viewportHeight)

        let upperBound = min(self.results.count, self.scrollOffset + viewportHeight)
        for index in self.scrollOffset..<upperBound {
            let result = self.results[index]
            let marker = (index == self.selectedIndex) ? ">" : " "
            let line = "\(marker) [\(index + 1)] \(self.renderedResultLine(result))"
            lines.append(self.truncate(line, maxLength: 220))
        }
    }

    private func renderedResultLine(_ result: SelectorMatchSummary) -> String {
        var parts: [String] = [result.role]
        if let name = self.detailValue(result.computedName) {
            parts.append("name=\"\(name)\"")
        }
        if let value = self.detailValue(result.value) {
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

    private func statsLine() -> String {
        guard let report = self.lastReport else {
            return "stats no-query"
        }
        return "stats elapsed_ms=\(Self.formatMilliseconds(report.elapsedMilliseconds)) traversed=\(report.traversedCount) matched=\(report.matchedCount) shown=\(report.shownCount)"
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
            if !self.query.isEmpty {
                self.query.removeLast()
            }

        case .character("q"):
            self.query = ""
            self.statusMessage = "Query cleared."

        case let .character(character):
            self.query.append(character)

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
            if !self.searchText.isEmpty {
                self.searchText.removeLast()
            }

        case let .character(character):
            self.searchText.append(character)

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
            self.mode = .interactionValueInput(.setValue)

        case .character("s"):
            self.pendingValueText = ""
            self.mode = .interactionValueInput(.setValueSubmit)

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
            }

        case .escape:
            self.mode = .results
            self.statusMessage = "Interaction canceled."

        case .backspace:
            if !self.pendingValueText.isEmpty {
                self.pendingValueText.removeLast()
            }

        case let .character(character):
            self.pendingValueText.append(character)

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

        guard secondByte == 91 else {
            return .escape
        }

        guard let thirdByte = self.readByte(timeoutMillis: 15) else {
            return .escape
        }

        switch thirdByte {
        case 65:
            return .arrowUp
        case 66:
            return .arrowDown
        case 53:
            _ = self.readByte(timeoutMillis: 15)
            return .pageUp
        case 54:
            _ = self.readByte(timeoutMillis: 15)
            return .pageDown
        default:
            return .escape
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
    case escape
    case arrowUp
    case arrowDown
    case pageUp
    case pageDown
    case ctrlC
    case ctrlF
    case ctrlB
    case unknown
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
        raw.c_oflag &= ~tcflag_t(OPOST)
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
