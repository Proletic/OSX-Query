import Foundation

public enum OXQParseError: Error, Equatable, Sendable {
    case emptyInput
    case unexpectedCharacter(Character, position: Int)
    case unterminatedString(position: Int)
    case unexpectedToken(expected: String, actual: String, position: Int)
    case unexpectedEnd(expected: String)
    case unknownPseudo(name: String, position: Int)
}

extension OXQParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyInput:
            "Query is empty."
        case let .unexpectedCharacter(character, position):
            "Unexpected character '\(character)' at index \(position)."
        case let .unterminatedString(position):
            "Unterminated string literal starting at index \(position)."
        case let .unexpectedToken(expected, actual, position):
            "Expected \(expected), found \(actual) at index \(position)."
        case let .unexpectedEnd(expected):
            "Unexpected end of input while expecting \(expected)."
        case let .unknownPseudo(name, position):
            "Unknown pseudo class '\(name)' at index \(position)."
        }
    }
}

public struct OXQParser: Sendable {
    public init(lexer: OXQLexer = OXQLexer()) {
        self.lexer = lexer
    }

    public func parse(_ input: String) throws -> OXQSyntaxTree {
        let tokens = try self.lexer.tokenize(input)
        guard !tokens.isEmpty else { throw OXQParseError.emptyInput }

        var stream = TokenStream(tokens: tokens)
        let selectors = try self.parseSelectorList(&stream, stoppingAt: [])

        if let token = stream.peek() {
            throw OXQParseError.unexpectedToken(
                expected: "end of input",
                actual: token.kind.debugName,
                position: token.range.lowerBound)
        }

        return OXQSyntaxTree(selectors: selectors)
    }

    private let lexer: OXQLexer

    private func parseSelectorList(
        _ stream: inout TokenStream,
        stoppingAt stopTags: Set<OXQTokenTag>) throws -> [OXQSelector]
    {
        guard let nextTag = stream.peekTag(), !stopTags.contains(nextTag) else {
            if stopTags.contains(.rightParen) {
                throw OXQParseError.unexpectedToken(
                    expected: "selector",
                    actual: stream.peek()?.kind.debugName ?? "end of input",
                    position: stream.position)
            }
            throw OXQParseError.emptyInput
        }

        var selectors = [try self.parseSelector(&stream)]

        while stream.consume(if: .comma) != nil {
            if let nextTag = stream.peekTag(), stopTags.contains(nextTag) {
                throw OXQParseError.unexpectedToken(
                    expected: "selector",
                    actual: stream.peek()?.kind.debugName ?? "end of input",
                    position: stream.position)
            }
            selectors.append(try self.parseSelector(&stream))
        }

        return selectors
    }

    private func parseSelector(_ stream: inout TokenStream) throws -> OXQSelector {
        let leading = try self.parseCompound(&stream)
        var links: [OXQSelectorLink] = []

        while let combinator = self.parseOptionalCombinator(&stream) {
            let compound = try self.parseCompound(&stream)
            links.append(OXQSelectorLink(combinator: combinator, compound: compound))
        }

        return OXQSelector(leading: leading, links: links)
    }

    private func parseCompound(_ stream: inout TokenStream) throws -> OXQCompound {
        switch stream.peekTag() {
        case .star, .identifier:
            let type = try self.parseTypeSelector(&stream)
            let attributes = stream.peekTag() == .leftBracket ? try self.parseAttributeGroup(&stream) : []
            let pseudos = try self.parsePseudos(&stream, requireAtLeastOne: false)
            return OXQCompound(typeSelector: type, attributes: attributes, pseudos: pseudos)

        case .leftBracket:
            let attributes = try self.parseAttributeGroup(&stream)
            let pseudos = try self.parsePseudos(&stream, requireAtLeastOne: false)
            return OXQCompound(typeSelector: nil, attributes: attributes, pseudos: pseudos)

        case .colon:
            let pseudos = try self.parsePseudos(&stream, requireAtLeastOne: true)
            return OXQCompound(typeSelector: nil, attributes: [], pseudos: pseudos)

        case let .some(tag):
            let token = stream.peek()
            throw OXQParseError.unexpectedToken(
                expected: "compound selector",
                actual: token?.kind.debugName ?? "\(tag)",
                position: stream.position)

        case .none:
            throw OXQParseError.unexpectedEnd(expected: "compound selector")
        }
    }

    private func parseTypeSelector(_ stream: inout TokenStream) throws -> OXQTypeSelector {
        if stream.consume(if: .star) != nil {
            return .wildcard
        }

        guard let token = stream.consumeIdentifier() else {
            throw OXQParseError.unexpectedToken(
                expected: "role or *",
                actual: stream.peek()?.kind.debugName ?? "end of input",
                position: stream.position)
        }
        return .role(token.value)
    }

    private func parseAttributeGroup(_ stream: inout TokenStream) throws -> [OXQAttributeMatch] {
        _ = try stream.expect(.leftBracket, expected: "[")

        var attributes = [try self.parseAttribute(&stream)]

        while stream.consume(if: .comma) != nil {
            attributes.append(try self.parseAttribute(&stream))
        }

        _ = try stream.expect(.rightBracket, expected: "]")
        return attributes
    }

    private func parseAttribute(_ stream: inout TokenStream) throws -> OXQAttributeMatch {
        guard let nameToken = stream.consumeIdentifier() else {
            throw OXQParseError.unexpectedToken(
                expected: "attribute name",
                actual: stream.peek()?.kind.debugName ?? "end of input",
                position: stream.position)
        }

        let opToken = try stream.expectOneOf([.eq, .contains, .startsWith, .endsWith], expected: "attribute operator")
        let op: OXQAttributeOperator
        switch opToken.kind.tag {
        case .eq: op = .equals
        case .contains: op = .contains
        case .startsWith: op = .startsWith
        case .endsWith: op = .endsWith
        default:
            throw OXQParseError.unexpectedToken(
                expected: "attribute operator",
                actual: opToken.kind.debugName,
                position: opToken.range.lowerBound)
        }

        guard let valueToken = stream.consumeString() else {
            throw OXQParseError.unexpectedToken(
                expected: "quoted string value",
                actual: stream.peek()?.kind.debugName ?? "end of input",
                position: stream.position)
        }

        return OXQAttributeMatch(name: nameToken.value, op: op, value: valueToken.value)
    }

    private func parsePseudos(_ stream: inout TokenStream, requireAtLeastOne: Bool) throws -> [OXQPseudoClass] {
        var pseudos: [OXQPseudoClass] = []
        while stream.peekTag() == .colon {
            pseudos.append(try self.parsePseudo(&stream))
        }

        if requireAtLeastOne, pseudos.isEmpty {
            throw OXQParseError.unexpectedToken(
                expected: "pseudo class",
                actual: stream.peek()?.kind.debugName ?? "end of input",
                position: stream.position)
        }

        return pseudos
    }

    private func parsePseudo(_ stream: inout TokenStream) throws -> OXQPseudoClass {
        _ = try stream.expect(.colon, expected: ":")

        guard let nameToken = stream.consumeIdentifier() else {
            throw OXQParseError.unexpectedToken(
                expected: "pseudo class name",
                actual: stream.peek()?.kind.debugName ?? "end of input",
                position: stream.position)
        }

        _ = try stream.expect(.leftParen, expected: "(")

        let pseudo: OXQPseudoClass
        switch nameToken.value.lowercased() {
        case "has":
            let argument = try self.parseHasArgument(&stream)
            pseudo = .has(argument: argument)
        case "not":
            let selectors = try self.parseSelectorList(&stream, stoppingAt: [.rightParen])
            pseudo = .not(selectors: selectors)
        default:
            throw OXQParseError.unknownPseudo(name: nameToken.value, position: nameToken.position)
        }

        _ = try stream.expect(.rightParen, expected: ")")
        return pseudo
    }

    private func parseHasArgument(_ stream: inout TokenStream) throws -> OXQHasArgument {
        let relativeSelectors = try self.parseRelativeSelectorList(&stream, stoppingAt: [.rightParen])
        let hasLeadingCombinator = relativeSelectors.contains { $0.leadingCombinator != nil }

        if hasLeadingCombinator {
            return .relativeSelectors(relativeSelectors)
        }

        let selectors = relativeSelectors.map(\.selector)
        return .selectors(selectors)
    }

    private func parseRelativeSelectorList(
        _ stream: inout TokenStream,
        stoppingAt stopTags: Set<OXQTokenTag>) throws -> [OXQRelativeSelector]
    {
        guard let nextTag = stream.peekTag(), !stopTags.contains(nextTag) else {
            throw OXQParseError.unexpectedToken(
                expected: "selector",
                actual: stream.peek()?.kind.debugName ?? "end of input",
                position: stream.position)
        }

        var selectors = [try self.parseRelativeSelector(&stream)]

        while stream.consume(if: .comma) != nil {
            selectors.append(try self.parseRelativeSelector(&stream))
        }

        return selectors
    }

    private func parseRelativeSelector(_ stream: inout TokenStream) throws -> OXQRelativeSelector {
        let leadingCombinator = self.parseOptionalCombinator(&stream)
        let selector = try self.parseSelector(&stream)
        return OXQRelativeSelector(leadingCombinator: leadingCombinator, selector: selector)
    }

    private func parseOptionalCombinator(_ stream: inout TokenStream) -> OXQCombinator? {
        if stream.consume(if: .child) != nil {
            return .child
        }
        if stream.consume(if: .desc) != nil {
            return .descendant
        }
        return nil
    }
}

private struct TokenStream: Sendable {
    init(tokens: [OXQToken]) {
        self.tokens = tokens
    }

    let tokens: [OXQToken]
    var index = 0

    var position: Int {
        self.peek()?.range.lowerBound ?? self.tokens.last?.range.upperBound ?? 0
    }

    func peek() -> OXQToken? {
        guard self.index < self.tokens.count else { return nil }
        return self.tokens[self.index]
    }

    func peekTag() -> OXQTokenTag? {
        self.peek()?.kind.tag
    }

    mutating func consume(if tag: OXQTokenTag) -> OXQToken? {
        guard let token = self.peek(), token.kind.tag == tag else { return nil }
        self.index += 1
        return token
    }

    mutating func expect(_ tag: OXQTokenTag, expected: String) throws -> OXQToken {
        if let token = self.consume(if: tag) {
            return token
        }
        throw OXQParseError.unexpectedToken(
            expected: expected,
            actual: self.peek()?.kind.debugName ?? "end of input",
            position: self.position)
    }

    mutating func expectOneOf(_ tags: Set<OXQTokenTag>, expected: String) throws -> OXQToken {
        guard let token = self.peek() else {
            throw OXQParseError.unexpectedEnd(expected: expected)
        }
        guard tags.contains(token.kind.tag) else {
            throw OXQParseError.unexpectedToken(
                expected: expected,
                actual: token.kind.debugName,
                position: token.range.lowerBound)
        }
        self.index += 1
        return token
    }

    mutating func consumeIdentifier() -> (value: String, position: Int)? {
        guard let token = self.peek(), case let .identifier(value) = token.kind else { return nil }
        self.index += 1
        return (value: value, position: token.range.lowerBound)
    }

    mutating func consumeString() -> (value: String, position: Int)? {
        guard let token = self.peek(), case let .string(value) = token.kind else { return nil }
        self.index += 1
        return (value: value, position: token.range.lowerBound)
    }
}
