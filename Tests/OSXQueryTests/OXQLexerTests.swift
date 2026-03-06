import Foundation
import Testing
@testable import OSXQuery

@Suite("OXQ Lexer")
struct OXQLexerTests {
    private let lexer = OXQLexer()

    @Test("tokenizes all punctuation and operators")
    func tokenizesPunctuationAndOperators() throws {
        let tokens = try self.lexer.tokenize(#"*[AXTitle="a",AXValue*="b",AXDescription^="c",AXHelp$="d"]:has(> AXButton),AXTextField"#)
        let tags = tokens.map { $0.kind.tag }

        #expect(tags == [
            .star,
            .leftBracket,
            .identifier, .eq, .string,
            .comma,
            .identifier, .contains, .string,
            .comma,
            .identifier, .startsWith, .string,
            .comma,
            .identifier, .endsWith, .string,
            .rightBracket,
            .colon,
            .identifier,
            .leftParen,
            .child,
            .identifier,
            .rightParen,
            .comma,
            .identifier,
        ])
    }

    @Test("rewrites whitespace as descendant between compounds")
    func rewritesWhitespaceAsDescendant() throws {
        let tokens = try self.lexer.tokenize("AXGroup AXStaticText")
        #expect(tokens.map { $0.kind.tag } == [.identifier, .desc, .identifier])
    }

    @Test("rewrites whitespace between right bracket and role as descendant")
    func rewritesWhitespaceAfterBracketAsDescendant() throws {
        let tokens = try self.lexer.tokenize(#"[AXTitle="X"] AXButton"#)
        #expect(tokens.map { $0.kind.tag } == [.leftBracket, .identifier, .eq, .string, .rightBracket, .desc, .identifier])
    }

    @Test("rewrites whitespace between right paren and left bracket as descendant")
    func rewritesWhitespaceAfterParenAsDescendant() throws {
        let tokens = try self.lexer.tokenize(#"AXGroup:has(AXButton) [AXTitle="Y"]"#)
        let tags = tokens.map { $0.kind.tag }
        #expect(tags.contains(.desc))
    }

    @Test("does not rewrite whitespace around commas or child combinators")
    func doesNotRewriteWhitespaceAroundCommaOrChild() throws {
        let tokens = try self.lexer.tokenize("AXGroup , AXButton > AXStaticText")
        #expect(tokens.map { $0.kind.tag } == [.identifier, .comma, .identifier, .child, .identifier])
    }

    @Test("drops leading and trailing whitespace")
    func dropsLeadingAndTrailingWhitespace() throws {
        let tokens = try self.lexer.tokenize("   AXButton   ")
        #expect(tokens.map { $0.kind.tag } == [.identifier])
    }

    @Test("keeps escaped double quote in double-quoted string")
    func parsesEscapedDoubleQuote() throws {
        let tokens = try self.lexer.tokenize(#"[AXTitle="He said \"hello\""]"#)
        guard case let .string(value) = tokens[3].kind else {
            Issue.record("Expected string token.")
            return
        }
        #expect(value == #"He said "hello""#)
    }

    @Test("keeps escaped single quote in single-quoted string")
    func parsesEscapedSingleQuote() throws {
        let tokens = try self.lexer.tokenize("[AXTitle='it\\'s ok']")
        guard case let .string(value) = tokens[3].kind else {
            Issue.record("Expected string token.")
            return
        }
        #expect(value == "it's ok")
    }

    @Test("supports newline, tab, carriage-return escapes")
    func parsesControlEscapes() throws {
        let tokens = try self.lexer.tokenize(#"[AXValue="a\nb\tc\rd"]"#)
        guard case let .string(value) = tokens[3].kind else {
            Issue.record("Expected string token.")
            return
        }
        #expect(value == "a\nb\tc\rd")
    }

    @Test("throws on unterminated string")
    func throwsOnUnterminatedString() {
        do {
            _ = try self.lexer.tokenize(#"[AXTitle="missing]"#)
            Issue.record("Expected unterminated string error.")
        } catch let error as OXQParseError {
            guard case .unterminatedString = error else {
                Issue.record("Expected unterminated string, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("throws on unsupported character")
    func throwsOnUnsupportedCharacter() {
        do {
            _ = try self.lexer.tokenize("AXRole@")
            Issue.record("Expected unexpectedCharacter error.")
        } catch let error as OXQParseError {
            guard case let .unexpectedCharacter(character, _) = error else {
                Issue.record("Expected unexpectedCharacter, got \(error)")
                return
            }
            #expect(character == "@")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("throws on malformed starts-with operator")
    func throwsOnMalformedStartsWithOperator() {
        do {
            _ = try self.lexer.tokenize("AXRole[AXTitle^\"x\"]")
            Issue.record("Expected unexpectedCharacter error.")
        } catch let error as OXQParseError {
            guard case let .unexpectedCharacter(character, _) = error else {
                Issue.record("Expected unexpectedCharacter, got \(error)")
                return
            }
            #expect(character == "^")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("throws on malformed ends-with operator")
    func throwsOnMalformedEndsWithOperator() {
        do {
            _ = try self.lexer.tokenize("AXRole[AXTitle$\"x\"]")
            Issue.record("Expected unexpectedCharacter error.")
        } catch let error as OXQParseError {
            guard case let .unexpectedCharacter(character, _) = error else {
                Issue.record("Expected unexpectedCharacter, got \(error)")
                return
            }
            #expect(character == "$")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
