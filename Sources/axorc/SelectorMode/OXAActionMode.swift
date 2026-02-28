import AppKit
import AXorcist
import ApplicationServices
import Foundation

@MainActor
enum SelectorActionRefStore {
    private(set) static var hasSnapshot = false
    private(set) static var snapshotAppPID: pid_t?
    private static var elementsByReference: [String: Element] = [:]

    static func replace(with elementsByReference: [String: Element], appPID: pid_t?) {
        self.elementsByReference = elementsByReference
        self.snapshotAppPID = appPID
        self.hasSnapshot = true
    }

    static func clear() {
        self.elementsByReference = [:]
        self.snapshotAppPID = nil
        self.hasSnapshot = false
    }

    static func element(for reference: String) -> Element? {
        self.elementsByReference[reference.lowercased()]
    }
}

enum OXAActionError: LocalizedError {
    case parse(String)
    case noSnapshot
    case unknownElementReference(String)
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case let .parse(message):
            "Invalid OXA program: \(message)"
        case .noSnapshot:
            "No cached query snapshot available. Run a selector query through the cache daemon first (query+)."
        case let .unknownElementReference(reference):
            "Unknown element reference '\(reference)'. Re-run query to refresh refs."
        case let .runtime(message):
            message
        }
    }
}

struct OXAHotkeyChord: Equatable {
    let modifiers: [String]
    let baseKey: String
}

enum OXAScrollDirection: String, Equatable {
    case up
    case down
    case left
    case right
}

enum OXAStatement: Equatable {
    case sendText(text: String, targetRef: String)
    case sendTextAsKeys(text: String, targetRef: String)
    case sendClick(targetRef: String)
    case sendRightClick(targetRef: String)
    case sendDrag(sourceRef: String, targetRef: String)
    case sendHotkey(chord: OXAHotkeyChord, targetRef: String)
    case sendScroll(direction: OXAScrollDirection, targetRef: String)
    case readAttribute(attributeName: String, targetRef: String)
    case sleep(milliseconds: Int)
    case open(app: String)
    case close(app: String)
}

struct OXAProgram: Equatable {
    let statements: [OXAStatement]
}

struct OXAParser {
    static func parse(_ source: String) throws -> OXAProgram {
        var parser = Impl(source: source)
        return try parser.parseProgram()
    }

    private struct Token {
        enum Kind: Equatable {
            case word(String)
            case string(String)
            case semicolon
            case plus
            case eof
        }

        let kind: Kind
        let offset: Int
    }

    private struct Impl {
        init(source: String) {
            self.lexer = Lexer(source: source)
            self.lookahead = self.lexer.nextToken()
        }

        private static let modifierSet: Set<String> = ["cmd", "ctrl", "alt", "shift", "fn"]
        private static let namedBaseKeys: Set<String> = [
            "enter", "tab", "space", "escape", "backspace", "delete",
            "home", "end", "page_up", "page_down",
            "up", "down", "left", "right",
        ]

        private var lexer: Lexer
        private var lookahead: Token

        mutating func parseProgram() throws -> OXAProgram {
            var statements: [OXAStatement] = []

            while !self.isEOF {
                let statement = try self.parseStatement()
                try self.expectSemicolon()
                statements.append(statement)
            }

            return OXAProgram(statements: statements)
        }

        private var isEOF: Bool {
            if case .eof = self.lookahead.kind {
                return true
            }
            return false
        }

        private mutating func parseStatement() throws -> OXAStatement {
            let keyword = try self.expectWord().lowercased()
            switch keyword {
            case "send":
                return try self.parseSendStatement()
            case "read":
                let attributeName = try self.expectWord()
                _ = try self.expectWord("from")
                let targetRef = try self.expectElementReference()
                return .readAttribute(attributeName: attributeName, targetRef: targetRef)
            case "sleep":
                let milliseconds = try self.expectInteger()
                return .sleep(milliseconds: milliseconds)
            case "open":
                return .open(app: try self.expectString())
            case "close":
                return .close(app: try self.expectString())
            default:
                throw self.parseError("Unexpected statement keyword '\(keyword)'.")
            }
        }

        private mutating func parseSendStatement() throws -> OXAStatement {
            let action = try self.expectWord().lowercased()
            switch action {
            case "text":
                let text = try self.expectString()
                if self.consumeWordIfPresent("as") {
                    _ = try self.expectWord("keys")
                    _ = try self.expectWord("to")
                    let targetRef = try self.expectElementReference()
                    return .sendTextAsKeys(text: text, targetRef: targetRef)
                }
                _ = try self.expectWord("to")
                let targetRef = try self.expectElementReference()
                return .sendText(text: text, targetRef: targetRef)
            case "click":
                _ = try self.expectWord("to")
                let targetRef = try self.expectElementReference()
                return .sendClick(targetRef: targetRef)
            case "right":
                _ = try self.expectWord("click")
                _ = try self.expectWord("to")
                let targetRef = try self.expectElementReference()
                return .sendRightClick(targetRef: targetRef)
            case "drag":
                let sourceRef = try self.expectElementReference()
                _ = try self.expectWord("to")
                let targetRef = try self.expectElementReference()
                return .sendDrag(sourceRef: sourceRef, targetRef: targetRef)
            case "hotkey":
                let chord = try self.parseHotkeyChord()
                _ = try self.expectWord("to")
                let targetRef = try self.expectElementReference()
                return .sendHotkey(chord: chord, targetRef: targetRef)
            case "scroll":
                let rawDirection = try self.expectWord().lowercased()
                guard let direction = OXAScrollDirection(rawValue: rawDirection) else {
                    throw self.parseError("Unsupported scroll direction '\(rawDirection)'.")
                }
                _ = try self.expectWord("to")
                let targetRef = try self.expectElementReference()
                return .sendScroll(direction: direction, targetRef: targetRef)
            default:
                throw self.parseError("Unsupported send action '\(action)'.")
            }
        }

        private mutating func parseHotkeyChord() throws -> OXAHotkeyChord {
            var parts: [String] = [self.normalizeHotkeyToken(try self.expectWord())]

            while self.consumePlusIfPresent() {
                parts.append(self.normalizeHotkeyToken(try self.expectWord()))
            }

            guard let baseKey = parts.last else {
                throw self.parseError("Hotkey is empty.")
            }

            let modifiers = Array(parts.dropLast())
            for modifier in modifiers {
                guard Self.modifierSet.contains(modifier) else {
                    throw self.parseError("Hotkey modifiers must appear before the base key. Invalid token '\(modifier)'.")
                }
            }

            let modifierCount = Set(modifiers).count
            guard modifierCount == modifiers.count else {
                throw self.parseError("Hotkey modifiers must be unique.")
            }

            guard !Self.modifierSet.contains(baseKey) else {
                throw self.parseError("Hotkey requires a base key at the end.")
            }

            guard self.isSupportedBaseKey(baseKey) else {
                throw self.parseError("Unsupported hotkey base key '\(baseKey)'.")
            }

            return OXAHotkeyChord(modifiers: modifiers, baseKey: baseKey)
        }

        private func isSupportedBaseKey(_ value: String) -> Bool {
            if value.count == 1, let scalar = value.unicodeScalars.first {
                return CharacterSet.alphanumerics.contains(scalar)
            }

            if value.first == "f",
               let number = Int(value.dropFirst()),
               number >= 1,
               number <= 24
            {
                return true
            }

            return Self.namedBaseKeys.contains(value)
        }

        private func normalizeHotkeyToken(_ token: String) -> String {
            let lowered = token
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")

            let aliases: [String: String] = [
                "command": "cmd",
                "control": "ctrl",
                "option": "alt",
                "opt": "alt",
                "return": "enter",
                "esc": "escape",
                "pageup": "page_up",
                "pagedown": "page_down",
                "arrowup": "up",
                "arrowdown": "down",
                "arrowleft": "left",
                "arrowright": "right",
            ]

            return aliases[lowered] ?? lowered
        }

        private mutating func expectSemicolon() throws {
            guard case .semicolon = self.lookahead.kind else {
                throw self.parseError("Expected ';' after statement.")
            }
            self.advance()
        }

        private mutating func expectWord(_ expected: String? = nil) throws -> String {
            guard case let .word(value) = self.lookahead.kind else {
                throw self.parseError("Expected identifier.")
            }

            if let expected,
               value.lowercased() != expected.lowercased()
            {
                throw self.parseError("Expected '\(expected)'.")
            }

            self.advance()
            return value
        }

        private mutating func expectString() throws -> String {
            guard case let .string(value) = self.lookahead.kind else {
                throw self.parseError("Expected string literal.")
            }
            self.advance()
            return value
        }

        private mutating func expectInteger() throws -> Int {
            let text = try self.expectWord()
            guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text) else {
                throw self.parseError("Expected integer value.")
            }
            return value
        }

        private mutating func expectElementReference() throws -> String {
            let value = try self.expectWord().lowercased()
            guard Self.isValidElementReference(value) else {
                throw self.parseError("Element references must be exactly 9 hex characters.")
            }
            return value
        }

        private static func isValidElementReference(_ value: String) -> Bool {
            guard value.count == 9 else { return false }
            return value.unicodeScalars.allSatisfy { scalar in
                CharacterSet(charactersIn: "0123456789abcdef").contains(scalar)
            }
        }

        private mutating func consumePlusIfPresent() -> Bool {
            guard case .plus = self.lookahead.kind else {
                return false
            }
            self.advance()
            return true
        }

        private mutating func consumeWordIfPresent(_ expected: String) -> Bool {
            guard case let .word(value) = self.lookahead.kind else {
                return false
            }
            guard value.lowercased() == expected.lowercased() else {
                return false
            }

            self.advance()
            return true
        }

        private mutating func advance() {
            self.lookahead = self.lexer.nextToken()
        }

        private func parseError(_ message: String) -> OXAActionError {
            .parse("\(message) (offset \(self.lookahead.offset))")
        }
    }

    private struct Lexer {
        init(source: String) {
            self.source = source
            self.index = source.startIndex
        }

        private let source: String
        private var index: String.Index

        mutating func nextToken() -> Token {
            self.consumeWhitespace()
            let offset = self.source.distance(from: self.source.startIndex, to: self.index)

            guard self.index < self.source.endIndex else {
                return Token(kind: .eof, offset: offset)
            }

            let character = self.source[self.index]

            if character == ";" {
                self.advance()
                return Token(kind: .semicolon, offset: offset)
            }
            if character == "+" {
                self.advance()
                return Token(kind: .plus, offset: offset)
            }
            if character == "\"" {
                return self.lexString(startOffset: offset)
            }

            if self.isWordCharacter(character) {
                let start = self.index
                self.advance()
                while self.index < self.source.endIndex,
                      self.isWordCharacter(self.source[self.index])
                {
                    self.advance()
                }
                let value = String(self.source[start..<self.index])
                return Token(kind: .word(value), offset: offset)
            }

            self.advance()
            return Token(kind: .word(String(character)), offset: offset)
        }

        private mutating func lexString(startOffset: Int) -> Token {
            self.advance() // opening quote
            var result = ""

            while self.index < self.source.endIndex {
                let character = self.source[self.index]
                self.advance()

                if character == "\"" {
                    return Token(kind: .string(result), offset: startOffset)
                }

                if character == "\\" {
                    guard self.index < self.source.endIndex else {
                        return Token(kind: .word("<unterminated_string>"), offset: startOffset)
                    }
                    let escaped = self.source[self.index]
                    self.advance()
                    switch escaped {
                    case "n":
                        result.append("\n")
                    case "t":
                        result.append("\t")
                    case "r":
                        result.append("\r")
                    case "\\":
                        result.append("\\")
                    case "\"":
                        result.append("\"")
                    default:
                        result.append(escaped)
                    }
                    continue
                }

                result.append(character)
            }

            return Token(kind: .word("<unterminated_string>"), offset: startOffset)
        }

        private mutating func consumeWhitespace() {
            while self.index < self.source.endIndex,
                  self.source[self.index].isWhitespace
            {
                self.advance()
            }
        }

        private func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "-" || character == "."
        }

        private mutating func advance() {
            self.index = self.source.index(after: self.index)
        }
    }
}

@MainActor
enum OXAExecutor {
    private static let postPreflightDelaySeconds: TimeInterval = 0.1
    private static let appActivationTimeoutSeconds: TimeInterval = 1.0
    private static let appActivationPollIntervalSeconds: TimeInterval = 0.05
    private static let appleScriptActivationTimeoutSeconds: TimeInterval = 0.35
    private static let processPollIntervalSeconds: TimeInterval = 0.01
    private static let appLaunchWaitTimeoutSeconds: TimeInterval = 2.0
    private static let windowCreationWaitTimeoutSeconds: TimeInterval = 1.0
    private static var lastActivationFailureDescription: String?

    static func execute(programSource: String) throws -> String {
        let program = try OXAParser.parse(programSource)
        try self.preflightProgramApplication(program)

        var output: [String] = []
        for (index, statement) in program.statements.enumerated() {
            let readOutput = try self.execute(statement)
            output.append("ok [\(index + 1)] \(self.describe(statement))")
            if let readOutput {
                output.append("value [\(index + 1)] \(readOutput)")
            }
        }

        if output.isEmpty {
            return "ok actions=0"
        }

        return output.joined(separator: "\n")
    }

    private static func preflightProgramApplication(_ program: OXAProgram) throws {
        let references = self.elementReferencesRequiringActivation(in: program)
        guard !references.isEmpty else {
            return
        }

        var seenReferences = Set<String>()
        var resolvedElements: [Element] = []

        for reference in references {
            if !seenReferences.insert(reference).inserted {
                continue
            }

            let element = try self.resolveElementReference(reference)
            resolvedElements.append(element)
        }

        let allTargetsAreMenuContext = resolvedElements.allSatisfy { self.isMenuContextElement($0) }
        if allTargetsAreMenuContext {
            return
        }

        if let snapshotAppPID = SelectorActionRefStore.snapshotAppPID, snapshotAppPID > 0 {
            guard self.ensureApplicationFrontmost(pid: snapshotAppPID) else {
                let details = self.lastActivationFailureDescription.map { " \($0)" } ?? ""
                throw OXAActionError.runtime(
                    "Failed to activate target app before executing actions. Keystrokes were not sent.\(details)")
            }
            Thread.sleep(forTimeInterval: self.postPreflightDelaySeconds)
            return
        }

        var owningPid: pid_t?
        for element in resolvedElements {
            guard let pid = self.owningPID(for: element) else {
                throw OXAActionError.runtime(
                    "Unable to determine owning app for element reference. Re-run query to refresh refs.")
            }

            if let owningPid, owningPid != pid {
                throw OXAActionError.runtime("Action program references multiple apps. Re-run query and target a single app per action program.")
            }

            owningPid = pid
        }

        guard let owningPid else {
            return
        }

        guard self.ensureApplicationFrontmost(pid: owningPid) else {
            let details = self.lastActivationFailureDescription.map { " \($0)" } ?? ""
            throw OXAActionError.runtime(
                "Failed to activate target app before executing actions. Keystrokes were not sent.\(details)")
        }
        Thread.sleep(forTimeInterval: self.postPreflightDelaySeconds)
    }

    private static func elementReferencesRequiringActivation(in program: OXAProgram) -> [String] {
        var references: [String] = []

        for statement in program.statements {
            switch statement {
            case let .sendText(_, targetRef),
                 let .sendTextAsKeys(_, targetRef),
                 let .sendClick(targetRef),
                 let .sendRightClick(targetRef),
                 let .sendHotkey(_, targetRef),
                 let .sendScroll(_, targetRef):
                references.append(targetRef)
            case let .sendDrag(sourceRef, targetRef):
                references.append(sourceRef)
                references.append(targetRef)
            case .readAttribute, .sleep, .open, .close:
                continue
            }
        }

        return references
    }

    private static func describe(_ statement: OXAStatement) -> String {
        switch statement {
        case let .sendText(text, targetRef):
            return "send text \"\(text)\" to \(targetRef)"
        case let .sendTextAsKeys(text, targetRef):
            return "send text \"\(text)\" as keys to \(targetRef)"
        case let .sendClick(targetRef):
            return "send click to \(targetRef)"
        case let .sendRightClick(targetRef):
            return "send right click to \(targetRef)"
        case let .sendDrag(sourceRef, targetRef):
            return "send drag \(sourceRef) to \(targetRef)"
        case let .sendHotkey(chord, targetRef):
            let hotkey = (chord.modifiers + [chord.baseKey]).joined(separator: "+")
            return "send hotkey \(hotkey) to \(targetRef)"
        case let .sendScroll(direction, targetRef):
            return "send scroll \(direction.rawValue) to \(targetRef)"
        case let .readAttribute(attributeName, targetRef):
            return "read \(attributeName) from \(targetRef)"
        case let .sleep(milliseconds):
            return "sleep \(milliseconds)"
        case let .open(app):
            return "open \"\(app)\""
        case let .close(app):
            return "close \"\(app)\""
        }
    }

    private static func execute(_ statement: OXAStatement) throws -> String? {
        switch statement {
        case let .sendText(text, targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            guard self.focusTargetForInput(target) else {
                throw OXAActionError.runtime("Failed to focus target element \(targetRef) for text input.")
            }
            guard target.setValue(text, forAttribute: AXAttributeNames.kAXValueAttribute) else {
                throw OXAActionError.runtime("Failed to set AXValue on target element \(targetRef).")
            }
            return nil

        case let .sendTextAsKeys(text, targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            guard self.focusTargetForInput(target) else {
                throw OXAActionError.runtime("Failed to focus target element \(targetRef) for text input.")
            }

            let targetPid = SelectorActionRefStore.snapshotAppPID ?? self.owningPID(for: target)
            guard let targetPid else {
                throw OXAActionError.runtime("Unable to determine owning app for text input target \(targetRef).")
            }
            try self.executeTextAsKeys(text, targetPid: targetPid)
            return nil

        case let .sendClick(targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            try self.clickElementCenter(target)
            return nil

        case let .sendRightClick(targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            try self.clickElementCenter(target, button: .right)
            return nil

        case let .sendDrag(sourceRef, targetRef):
            let source = try self.resolveElementReference(sourceRef)
            let destination = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(source)

            guard let sourceCenter = self.centerPoint(for: source) else {
                throw OXAActionError.runtime("Unable to resolve frame for drag source \(sourceRef).")
            }
            guard let destinationCenter = self.centerPoint(for: destination) else {
                throw OXAActionError.runtime("Unable to resolve frame for drag target \(targetRef).")
            }

            try InputDriver.drag(from: sourceCenter, to: destinationCenter, steps: 20, interStepDelay: 0.005)
            return nil

        case let .sendHotkey(chord, targetRef):
            let target = try self.resolveElementReference(targetRef)
            let targetPid = SelectorActionRefStore.snapshotAppPID ?? self.owningPID(for: target)
            guard let targetPid else {
                throw OXAActionError.runtime("Unable to determine owning app for hotkey target \(targetRef).")
            }
            try self.executeHotkey(chord, targetPid: targetPid)
            return nil

        case let .sendScroll(direction, targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            guard let center = self.centerPoint(for: target) else {
                throw OXAActionError.runtime("Unable to resolve frame for scroll target \(targetRef).")
            }
            try self.scroll(direction: direction, at: center)
            return nil

        case let .readAttribute(attributeName, targetRef):
            let target = try self.resolveElementReference(targetRef)
            guard let value = self.readAttributeValue(from: target, attributeName: attributeName) else {
                throw OXAActionError.runtime(
                    "Attribute '\(attributeName)' has no readable value on target \(targetRef).")
            }
            return value

        case let .sleep(milliseconds):
            guard milliseconds >= 0 else {
                throw OXAActionError.runtime("Sleep duration must be non-negative.")
            }
            Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
            return nil

        case let .open(app):
            try self.openApplication(app)
            selectorQueryInvalidateCaches()
            return nil

        case let .close(app):
            try self.closeApplication(app)
            selectorQueryInvalidateCaches()
            return nil
        }
    }

    private static func resolveElementReference(_ reference: String) throws -> Element {
        guard SelectorActionRefStore.hasSnapshot else {
            throw OXAActionError.noSnapshot
        }

        guard let element = SelectorActionRefStore.element(for: reference) else {
            throw OXAActionError.unknownElementReference(reference)
        }

        return element
    }

    private static func preflightTargetElement(_ element: Element) {
        if self.isMenuContextElement(element) {
            return
        }

        if let window = self.owningWindow(for: element) {
            _ = AXUIElementSetAttributeValue(
                window.underlyingElement,
                AXAttributeNames.kAXMainAttribute as CFString,
                kCFBooleanTrue)
            _ = window.focusWindow()
        }

        Thread.sleep(forTimeInterval: self.postPreflightDelaySeconds)
    }

    private static func isMenuContextElement(_ element: Element) -> Bool {
        var current: Element? = element
        var depth = 0

        while let candidate = current, depth < 256 {
            if self.isMenuRole(candidate.role()) {
                return true
            }

            current = candidate.parent()
            depth += 1
        }

        return false
    }

    private static func isMenuRole(_ role: String?) -> Bool {
        guard let role else {
            return false
        }

        return role == AXRoleNames.kAXMenuRole || role == AXRoleNames.kAXMenuItemRole
    }

    static func ensureApplicationFrontmost(pid: pid_t) -> Bool {
        self.lastActivationFailureDescription = nil
        return self.ensureApplicationFrontmost(
            pid: pid,
            timeout: self.appActivationTimeoutSeconds,
            pollInterval: self.appActivationPollIntervalSeconds,
            now: Date.init,
            sleep: Thread.sleep,
            activatePid: self.liveActivatePid,
            frontmostPidProvider: self.liveFrontmostPid,
            focusedPidProvider: self.liveFocusedApplicationPid,
            axFrontmostProvider: self.liveAXFrontmost)
    }

    static func ensureApplicationFrontmost(
        pid: pid_t,
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        now: () -> Date,
        sleep: (TimeInterval) -> Void,
        activatePid: (pid_t) -> Bool,
        frontmostPidProvider: () -> pid_t?,
        focusedPidProvider: () -> pid_t?,
        axFrontmostProvider: (pid_t) -> Bool) -> Bool
    {
        let deadline = now().addingTimeInterval(timeout)
        var lastActivation = Date.distantPast

        while now() < deadline {
            let current = now()
            if current.timeIntervalSince(lastActivation) >= 0.2 {
                _ = activatePid(pid)
                lastActivation = current
            }

            if self.isTargetFrontmost(
                pid: pid,
                frontmostPidProvider: frontmostPidProvider,
                focusedPidProvider: focusedPidProvider,
                axFrontmostProvider: axFrontmostProvider)
            {
                return true
            }

            sleep(pollInterval)
        }

        return self.isTargetFrontmost(
            pid: pid,
            frontmostPidProvider: frontmostPidProvider,
            focusedPidProvider: focusedPidProvider,
            axFrontmostProvider: axFrontmostProvider)
    }

    private static func isTargetFrontmost(
        pid: pid_t,
        frontmostPidProvider: () -> pid_t?,
        focusedPidProvider: () -> pid_t?,
        axFrontmostProvider: (pid_t) -> Bool) -> Bool
    {
        let frontmostPid = frontmostPidProvider()
        let focusedPid = focusedPidProvider()

        if let frontmostPid, let focusedPid {
            return frontmostPid == pid && focusedPid == pid
        }
        if let frontmostPid {
            return frontmostPid == pid
        }
        if let focusedPid {
            return focusedPid == pid
        }

        // Only trust AXFrontmost when other focus signals are unavailable.
        return axFrontmostProvider(pid)
    }

    private static func liveActivatePid(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            self.lastActivationFailureDescription = "No running app found for pid \(pid)."
            return false
        }

        if app.isHidden {
            app.unhide()
        }

        if self.activateViaAppleScript(app) {
            return true
        }

        if self.activateViaRunningApplication(app) {
            self.lastActivationFailureDescription = nil
            return true
        }

        return false
    }

    private static func liveFrontmostPid() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private static func liveFocusedApplicationPid() -> pid_t? {
        guard let focused = try? AXUIElement.focusedApplication() else {
            return nil
        }

        var pid: pid_t = 0
        let status = AXUIElementGetPid(focused, &pid)
        guard status == .success, pid > 0 else {
            return nil
        }
        return pid
    }

    private static func liveAXFrontmost(_ pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            AXAttributeNames.kAXFrontmostAttribute as CFString,
            &value)
        guard status == .success, let number = value as? NSNumber else {
            return false
        }
        return number.boolValue
    }

    private static func activateViaAppleScript(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
            self.lastActivationFailureDescription = "Target app has no bundle identifier."
            return false
        }

        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(escapedBundleIdentifier)\" to activate"]
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            self.lastActivationFailureDescription = "AppleScript activation failed to launch: \(error.localizedDescription)"
            return false
        }

        guard self.waitForProcessExit(
            process,
            timeout: self.appleScriptActivationTimeoutSeconds,
            pollInterval: self.processPollIntervalSeconds)
        else {
            self.lastActivationFailureDescription = "AppleScript activation timed out."
            return false
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stderr, !stderr.isEmpty {
                self.lastActivationFailureDescription = "AppleScript activation failed (exit \(process.terminationStatus)): \(stderr)"
            } else {
                self.lastActivationFailureDescription = "AppleScript activation failed (exit \(process.terminationStatus))."
            }
            return false
        }

        self.lastActivationFailureDescription = nil
        return true
    }

    private static func activateViaRunningApplication(_ app: NSRunningApplication) -> Bool {
        let options: NSApplication.ActivationOptions = [.activateAllWindows, .activateIgnoringOtherApps]
        guard app.activate(options: options) else {
            let previous = self.lastActivationFailureDescription
            if let previous, !previous.isEmpty {
                self.lastActivationFailureDescription =
                    "\(previous) Fallback activation via NSRunningApplication.activate failed."
            } else {
                self.lastActivationFailureDescription =
                    "Fallback activation via NSRunningApplication.activate failed."
            }
            return false
        }
        return true
    }

    private static func waitForProcessExit(
        _ process: Process,
        timeout: TimeInterval,
        pollInterval: TimeInterval) -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
        }

        guard process.isRunning else {
            return true
        }

        process.terminate()
        for _ in 0..<10 where process.isRunning {
            Thread.sleep(forTimeInterval: pollInterval)
        }

        return !process.isRunning
    }

    private static func owningPID(for element: Element) -> pid_t? {
        if let pid = self.axPid(for: element), pid > 0 {
            return pid
        }

        var current = element.parent()
        var depth = 0
        while let candidate = current, depth < 256 {
            if let pid = self.axPid(for: candidate), pid > 0 {
                return pid
            }
            current = candidate.parent()
            depth += 1
        }

        return nil
    }

    private static func axPid(for element: Element) -> pid_t? {
        if let pid = element.pid(), pid > 0 {
            return pid
        }

        var pid: pid_t = 0
        let status = AXUIElementGetPid(element.underlyingElement, &pid)
        guard status == .success, pid > 0 else {
            return nil
        }
        return pid
    }

    private static func owningWindow(for element: Element) -> Element? {
        if element.role() == AXRoleNames.kAXWindowRole {
            return element
        }

        if let windowUIElement: AXUIElement = element.attribute(.window) {
            return Element(windowUIElement)
        }

        var current = element.parent()
        var depth = 0
        while let candidate = current, depth < 256 {
            if candidate.role() == AXRoleNames.kAXWindowRole {
                return candidate
            }
            current = candidate.parent()
            depth += 1
        }

        return nil
    }

    private static func centerPoint(for element: Element) -> CGPoint? {
        guard let frame = element.frame() else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func clickPoint(for element: Element) -> CGPoint? {
        guard let elementFrame = element.frame() else {
            return nil
        }

        if element.role() == AXRoleNames.kAXLinkRole,
           let descendantPoint = self.deepestDescendantPointInBounds(
               root: element,
               bounds: elementFrame)
        {
            return descendantPoint
        }

        return CGPoint(x: elementFrame.midX, y: elementFrame.midY)
    }

    private static func deepestDescendantPointInBounds(root: Element, bounds: CGRect) -> CGPoint? {
        var bestPoint: CGPoint?
        var bestDepth = -1
        var visited: Set<Element> = [root]

        func visit(_ element: Element, depth: Int) {
            guard depth < 256 else {
                return
            }

            guard let children = element.children(strict: false, includeApplicationExtras: false), !children.isEmpty else {
                return
            }

            for child in children {
                if visited.contains(child) {
                    continue
                }
                visited.insert(child)

                if let frame = child.frame(),
                   frame.width > 0,
                   frame.height > 0
                {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    if bounds.contains(center), depth > bestDepth {
                        bestDepth = depth
                        bestPoint = center
                    }
                }

                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 1)
        return bestPoint
    }

    private static func clickElementCenter(_ element: Element, button: MouseButton = .left) throws {
        guard let center = self.clickPoint(for: element) else {
            throw OXAActionError.runtime("Unable to resolve element frame for click.")
        }
        try self.movePointerToElementCenter(center)
        try InputDriver.click(at: center, button: button)
    }

    private static func movePointerToElementCenter(_ point: CGPoint) throws {
        try InputDriver.move(to: point)

        if let current = InputDriver.currentLocation() {
            let deltaX = current.x - point.x
            let deltaY = current.y - point.y
            if (deltaX * deltaX + deltaY * deltaY) <= 1 {
                return
            }
        }

        _ = CGWarpMouseCursorPosition(point)
    }

    private static func focusTargetForInput(_ element: Element) -> Bool {
        if element.setValue(true, forAttribute: AXAttributeNames.kAXFocusedAttribute) {
            return true
        }

        if element.press() {
            return true
        }

        do {
            try self.clickElementCenter(element)
            return true
        } catch {
            return false
        }
    }

    static func executeHotkey(
        _ chord: OXAHotkeyChord,
        targetPid: pid_t,
        dispatch: ([String], pid_t) throws -> Void = { keys, pid in
            try InputDriver.hotkey(keys: keys, targetPid: pid, holdDuration: 0)
        }) throws
    {
        let keys = chord.modifiers + [self.driverKeyName(for: chord.baseKey)]
        try dispatch(keys, targetPid)
    }

    static func executeTextAsKeys(
        _ text: String,
        targetPid: pid_t,
        dispatch: (String, pid_t) throws -> Void = { value, pid in
            try InputDriver.type(value, targetPid: pid, delayPerCharacter: 0)
        }) throws
    {
        try dispatch(text, targetPid)
    }

    private static func driverKeyName(for baseKey: String) -> String {
        switch baseKey {
        case "page_up":
            return "pageup"
        case "page_down":
            return "pagedown"
        case "backspace":
            return "delete"
        default:
            return baseKey
        }
    }

    private static func scroll(direction: OXAScrollDirection, at point: CGPoint) throws {
        let amount: Double = 80
        let deltas = self.scrollDeltas(
            for: direction,
            amount: amount,
            naturalScrollEnabled: self.isNaturalScrollEnabled())
        try InputDriver.scroll(deltaX: deltas.deltaX, deltaY: deltas.deltaY, at: point)
    }

    static func scrollDeltas(
        for direction: OXAScrollDirection,
        amount: Double,
        naturalScrollEnabled: Bool) -> (deltaX: Double, deltaY: Double)
    {
        let verticalUnit = naturalScrollEnabled ? -amount : amount
        let horizontalUnit = naturalScrollEnabled ? -amount : amount

        switch direction {
        case .up:
            return (0, verticalUnit)
        case .down:
            return (0, -verticalUnit)
        case .left:
            return (horizontalUnit, 0)
        case .right:
            return (-horizontalUnit, 0)
        }
    }

    private static func isNaturalScrollEnabled() -> Bool {
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let value = domain?["com.apple.swipescrolldirection"] as? Bool {
            return value
        }

        return true
    }

    private static func readAttributeValue(from element: Element, attributeName: String) -> String? {
        let canonicalName = self.canonicalAttributeName(attributeName)

        switch canonicalName {
        case AXAttributeNames.kAXRoleAttribute:
            return element.role()
        case AXAttributeNames.kAXSubroleAttribute:
            return element.subrole()
        case AXAttributeNames.kAXPIDAttribute:
            return element.pid().map(String.init)
        case AXAttributeNames.kAXTitleAttribute:
            return element.title()
        case AXAttributeNames.kAXDescriptionAttribute:
            return element.descriptionText()
        case AXAttributeNames.kAXHelpAttribute:
            return element.help()
        case AXAttributeNames.kAXIdentifierAttribute:
            return element.identifier()
        case AXAttributeNames.kAXRoleDescriptionAttribute:
            return element.roleDescription()
        case AXAttributeNames.kAXPlaceholderValueAttribute:
            return element.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute))
        case AXAttributeNames.kAXEnabledAttribute:
            return element.isEnabled().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXFocusedAttribute:
            return element.isFocused().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXValueAttribute:
            return SelectorMatchSummary.stringify(element.value())
        case AXMiscConstants.computedNameAttributeKey:
            return element.computedName()
        case AXMiscConstants.isIgnoredAttributeKey:
            return element.isIgnored() ? "true" : "false"
        default:
            break
        }

        guard let rawValue: Any = element.attribute(Attribute<Any>(canonicalName)) else {
            return nil
        }
        return SelectorMatchSummary.stringify(rawValue)
    }

    private static func canonicalAttributeName(_ name: String) -> String {
        PathUtils.attributeKeyMappings[name.lowercased()] ?? name
    }

    private static func openApplication(_ applicationIdentifier: String) throws {
        if let runningApp = self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated }) {
            guard self.ensureApplicationFrontmost(pid: runningApp.processIdentifier) else {
                let details = self.lastActivationFailureDescription.map { " \($0)" } ?? ""
                throw OXAActionError.runtime("Failed to activate '\(applicationIdentifier)'.\(details)")
            }

            if !self.applicationHasAnyWindow(runningApp) {
                _ = self.reopenViaAppleScript(runningApp)
                _ = self.waitForAnyWindow(in: runningApp, timeout: self.windowCreationWaitTimeoutSeconds)
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        if self.looksLikeBundleIdentifier(applicationIdentifier) {
            process.arguments = ["-b", applicationIdentifier]
        } else {
            process.arguments = ["-a", applicationIdentifier]
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw OXAActionError.runtime("Failed to launch '\(applicationIdentifier)': \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            throw OXAActionError.runtime("Failed to launch '\(applicationIdentifier)' (exit code \(process.terminationStatus)).")
        }

        guard let launchedApp = self.waitForRunningApplication(
            matching: applicationIdentifier,
            timeout: self.appLaunchWaitTimeoutSeconds)
        else {
            return
        }

        guard self.ensureApplicationFrontmost(pid: launchedApp.processIdentifier) else {
            let details = self.lastActivationFailureDescription.map { " \($0)" } ?? ""
            throw OXAActionError.runtime("Launched '\(applicationIdentifier)' but failed to activate it.\(details)")
        }

        if !self.applicationHasAnyWindow(launchedApp) {
            _ = self.reopenViaAppleScript(launchedApp)
            _ = self.waitForAnyWindow(in: launchedApp, timeout: self.windowCreationWaitTimeoutSeconds)
        }
    }

    private static func closeApplication(_ applicationIdentifier: String) throws {
        let matches = self.runningApplications(matching: applicationIdentifier)
        guard !matches.isEmpty else {
            return
        }

        for application in matches {
            if !application.terminate() {
                _ = application.forceTerminate()
                continue
            }

            for _ in 0..<20 where !application.isTerminated {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if !application.isTerminated {
                _ = application.forceTerminate()
            }
        }
    }

    private static func reopenViaAppleScript(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return false
        }

        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(escapedBundleIdentifier)\" to reopen"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }

        guard self.waitForProcessExit(
            process,
            timeout: self.appleScriptActivationTimeoutSeconds,
            pollInterval: self.processPollIntervalSeconds)
        else {
            return false
        }

        return process.terminationStatus == 0
    }

    private static func applicationHasAnyWindow(_ app: NSRunningApplication) -> Bool {
        guard let appElement = getApplicationElement(for: app.processIdentifier) else {
            return false
        }
        guard let windows = appElement.windows() else {
            return false
        }
        return !windows.isEmpty
    }

    private static func waitForAnyWindow(in app: NSRunningApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if self.applicationHasAnyWindow(app) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return self.applicationHasAnyWindow(app)
    }

    private static func waitForRunningApplication(
        matching applicationIdentifier: String,
        timeout: TimeInterval) -> NSRunningApplication?
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated }) {
                return app
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated })
    }

    private static func runningApplications(matching applicationIdentifier: String) -> [NSRunningApplication] {
        let normalizedIdentifier = applicationIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if self.looksLikeBundleIdentifier(applicationIdentifier) {
            return NSRunningApplication.runningApplications(withBundleIdentifier: applicationIdentifier)
        }

        return NSWorkspace.shared.runningApplications.filter { app in
            guard let name = app.localizedName?.lowercased() else { return false }
            return name == normalizedIdentifier
        }
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(".") && !trimmed.contains(" ")
    }
}
