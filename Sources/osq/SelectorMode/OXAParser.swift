import Foundation

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
                if self.consumeWordIfPresent("to") {
                    let targetRef = try self.expectElementReference()
                    return .sendScrollIntoView(targetRef: targetRef)
                }

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
