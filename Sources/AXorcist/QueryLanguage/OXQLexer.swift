import Foundation

public struct OXQToken: Equatable, Sendable {
    public init(kind: OXQTokenKind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }

    public let kind: OXQTokenKind
    public let range: Range<Int>
}

public enum OXQTokenKind: Equatable, Sendable {
    case star
    case child
    case desc
    case comma
    case colon
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    case eq
    case contains
    case startsWith
    case endsWith
    case identifier(String)
    case string(String)
    case whitespace
}

enum OXQTokenTag: Equatable, Sendable {
    case star
    case child
    case desc
    case comma
    case colon
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    case eq
    case contains
    case startsWith
    case endsWith
    case identifier
    case string
    case whitespace
}

extension OXQTokenKind {
    var tag: OXQTokenTag {
        switch self {
        case .star: .star
        case .child: .child
        case .desc: .desc
        case .comma: .comma
        case .colon: .colon
        case .leftParen: .leftParen
        case .rightParen: .rightParen
        case .leftBracket: .leftBracket
        case .rightBracket: .rightBracket
        case .eq: .eq
        case .contains: .contains
        case .startsWith: .startsWith
        case .endsWith: .endsWith
        case .identifier: .identifier
        case .string: .string
        case .whitespace: .whitespace
        }
    }

    var debugName: String {
        switch self {
        case .star: "*"
        case .child: ">"
        case .desc: "DESC"
        case .comma: ","
        case .colon: ":"
        case .leftParen: "("
        case .rightParen: ")"
        case .leftBracket: "["
        case .rightBracket: "]"
        case .eq: "="
        case .contains: "*="
        case .startsWith: "^="
        case .endsWith: "$="
        case let .identifier(value): "identifier(\(value))"
        case let .string(value): "string(\(value))"
        case .whitespace: "WS"
        }
    }
}

public struct OXQLexer: Sendable {
    public init() {}

    public func tokenize(_ input: String) throws -> [OXQToken] {
        let raw = try self.passOneTokenize(input)
        return self.passTwoRewriteWhitespace(raw)
    }

    private func passOneTokenize(_ input: String) throws -> [OXQToken] {
        let chars = Array(input)
        var tokens: [OXQToken] = []
        var index = 0

        while index < chars.count {
            let char = chars[index]

            if char.isWhitespace {
                let start = index
                index += 1
                while index < chars.count, chars[index].isWhitespace {
                    index += 1
                }
                tokens.append(OXQToken(kind: .whitespace, range: start ..< index))
                continue
            }

            switch char {
            case ",":
                tokens.append(OXQToken(kind: .comma, range: index ..< index + 1))
                index += 1
            case ":":
                tokens.append(OXQToken(kind: .colon, range: index ..< index + 1))
                index += 1
            case "(":
                tokens.append(OXQToken(kind: .leftParen, range: index ..< index + 1))
                index += 1
            case ")":
                tokens.append(OXQToken(kind: .rightParen, range: index ..< index + 1))
                index += 1
            case "[":
                tokens.append(OXQToken(kind: .leftBracket, range: index ..< index + 1))
                index += 1
            case "]":
                tokens.append(OXQToken(kind: .rightBracket, range: index ..< index + 1))
                index += 1
            case ">":
                tokens.append(OXQToken(kind: .child, range: index ..< index + 1))
                index += 1
            case "=":
                tokens.append(OXQToken(kind: .eq, range: index ..< index + 1))
                index += 1
            case "*":
                if self.matches(chars, at: index, token: "*=") {
                    tokens.append(OXQToken(kind: .contains, range: index ..< index + 2))
                    index += 2
                } else {
                    tokens.append(OXQToken(kind: .star, range: index ..< index + 1))
                    index += 1
                }
            case "^":
                if self.matches(chars, at: index, token: "^=") {
                    tokens.append(OXQToken(kind: .startsWith, range: index ..< index + 2))
                    index += 2
                } else {
                    throw OXQParseError.unexpectedCharacter(char, position: index)
                }
            case "$":
                if self.matches(chars, at: index, token: "$=") {
                    tokens.append(OXQToken(kind: .endsWith, range: index ..< index + 2))
                    index += 2
                } else {
                    throw OXQParseError.unexpectedCharacter(char, position: index)
                }
            case "\"", "'":
                let quote = char
                let start = index
                index += 1
                var stringValue = ""
                var isTerminated = false

                while index < chars.count {
                    let current = chars[index]
                    if current == "\\" {
                        guard index + 1 < chars.count else {
                            throw OXQParseError.unterminatedString(position: start)
                        }
                        let escaped = chars[index + 1]
                        switch escaped {
                        case "n": stringValue.append("\n")
                        case "r": stringValue.append("\r")
                        case "t": stringValue.append("\t")
                        case "\\": stringValue.append("\\")
                        case "\"": stringValue.append("\"")
                        case "'": stringValue.append("'")
                        default: stringValue.append(escaped)
                        }
                        index += 2
                        continue
                    }
                    if current == quote {
                        index += 1
                        isTerminated = true
                        break
                    }
                    stringValue.append(current)
                    index += 1
                }

                guard isTerminated else {
                    throw OXQParseError.unterminatedString(position: start)
                }

                tokens.append(OXQToken(kind: .string(stringValue), range: start ..< index))
            default:
                if self.isIdentifierStart(char) {
                    let start = index
                    index += 1
                    while index < chars.count, self.isIdentifierContinue(chars[index]) {
                        index += 1
                    }
                    let text = String(chars[start ..< index])
                    tokens.append(OXQToken(kind: .identifier(text), range: start ..< index))
                } else {
                    throw OXQParseError.unexpectedCharacter(char, position: index)
                }
            }
        }

        return tokens
    }

    private func passTwoRewriteWhitespace(_ rawTokens: [OXQToken]) -> [OXQToken] {
        var output: [OXQToken] = []

        for (index, token) in rawTokens.enumerated() {
            guard token.kind.tag == .whitespace else {
                output.append(token)
                continue
            }

            guard
                let previous = self.previousNonWhitespace(rawTokens, before: index),
                let next = self.nextNonWhitespace(rawTokens, after: index)
            else {
                continue
            }

            if self.canEndCompound(previous.kind.tag), self.canStartCompound(next.kind.tag) {
                output.append(OXQToken(kind: .desc, range: token.range))
            }
        }

        return output
    }

    private func previousNonWhitespace(_ tokens: [OXQToken], before index: Int) -> OXQToken? {
        guard index > 0 else { return nil }
        var cursor = index - 1
        while cursor >= 0 {
            let token = tokens[cursor]
            if token.kind.tag != .whitespace {
                return token
            }
            cursor -= 1
        }
        return nil
    }

    private func nextNonWhitespace(_ tokens: [OXQToken], after index: Int) -> OXQToken? {
        guard index + 1 < tokens.count else { return nil }
        var cursor = index + 1
        while cursor < tokens.count {
            let token = tokens[cursor]
            if token.kind.tag != .whitespace {
                return token
            }
            cursor += 1
        }
        return nil
    }

    private func canEndCompound(_ tag: OXQTokenTag) -> Bool {
        switch tag {
        case .star, .identifier, .rightBracket, .rightParen:
            true
        default:
            false
        }
    }

    private func canStartCompound(_ tag: OXQTokenTag) -> Bool {
        switch tag {
        case .star, .identifier, .leftBracket, .colon:
            true
        default:
            false
        }
    }

    private func isIdentifierStart(_ char: Character) -> Bool {
        char == "_" || char.isLetter
    }

    private func isIdentifierContinue(_ char: Character) -> Bool {
        self.isIdentifierStart(char) || char.isNumber || char == "-"
    }

    private func matches(_ chars: [Character], at index: Int, token: String) -> Bool {
        let pattern = Array(token)
        guard index + pattern.count <= chars.count else { return false }
        for offset in 0 ..< pattern.count where chars[index + offset] != pattern[offset] {
            return false
        }
        return true
    }
}
