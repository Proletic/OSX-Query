import Foundation
import Testing
@testable import OSXQuery

@Suite("OXQ Parser Edge Cases")
struct OXQParserEdgeCaseTests {
    private let parser = OXQParser()

    @Test("parses role-only compound")
    func parsesRoleOnlyCompound() throws {
        let ast = try self.parser.parse("AXRole")
        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].leading.typeSelector == .role("AXRole"))
        #expect(ast.selectors[0].leading.attributes.isEmpty)
        #expect(ast.selectors[0].leading.pseudos.isEmpty)
    }

    @Test("parses attribute-only compound")
    func parsesAttributeOnlyCompound() throws {
        let ast = try self.parser.parse(#"[AXTitle="Test"]"#)
        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].leading.typeSelector == nil)
        #expect(ast.selectors[0].leading.attributes == [.init(name: "AXTitle", op: .equals, value: "Test")])
    }

    @Test("parses pseudo-only compound")
    func parsesPseudoOnlyCompound() throws {
        let ast = try self.parser.parse(":has(AXTextField)")
        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].leading.typeSelector == nil)
        #expect(ast.selectors[0].leading.attributes.isEmpty)
        #expect(ast.selectors[0].leading.pseudos.count == 1)
    }

    @Test("parses nested pseudo classes")
    func parsesNestedPseudoClasses() throws {
        let ast = try self.parser.parse("AXGroup:not(:has(AXButton))")
        #expect(ast.selectors.count == 1)
        guard case let .not(selectors) = ast.selectors[0].leading.pseudos[0] else {
            Issue.record("Expected :not pseudo")
            return
        }
        #expect(selectors.count == 1)
    }

    @Test("parses not with selector list")
    func parsesNotSelectorList() throws {
        let ast = try self.parser.parse("AXButton:not(AXImage, AXLink)")
        guard case let .not(selectors) = ast.selectors[0].leading.pseudos[0] else {
            Issue.record("Expected :not pseudo")
            return
        }
        #expect(selectors.count == 2)
        #expect(selectors.map { $0.leading.typeSelector } == [.role("AXImage"), .role("AXLink")])
    }

    @Test("parses has with selector list")
    func parsesHasSelectorList() throws {
        let ast = try self.parser.parse("AXGroup:has(AXTextField, AXButton)")
        guard case let .has(argument) = ast.selectors[0].leading.pseudos[0] else {
            Issue.record("Expected :has pseudo")
            return
        }
        guard case let .selectors(selectors) = argument else {
            Issue.record("Expected selector list argument")
            return
        }
        #expect(selectors.count == 2)
    }

    @Test("parses has with relative selector list")
    func parsesHasRelativeSelectorList() throws {
        let ast = try self.parser.parse("AXGroup:has(> AXTextField, > AXButton)")
        guard case let .has(argument) = ast.selectors[0].leading.pseudos[0] else {
            Issue.record("Expected :has pseudo")
            return
        }
        guard case let .relativeSelectors(relativeSelectors) = argument else {
            Issue.record("Expected relative selector list argument")
            return
        }
        #expect(relativeSelectors.count == 2)
        #expect(relativeSelectors[0].leadingCombinator == .child)
        #expect(relativeSelectors[1].leadingCombinator == .child)
    }

    @Test("parses has with mixed relative selectors")
    func parsesHasMixedRelativeSelectorList() throws {
        let ast = try self.parser.parse("AXGroup:has(> AXTextField, AXButton)")
        guard case let .has(argument) = ast.selectors[0].leading.pseudos[0] else {
            Issue.record("Expected :has pseudo")
            return
        }
        guard case let .relativeSelectors(relativeSelectors) = argument else {
            Issue.record("Expected relative selector list argument")
            return
        }
        #expect(relativeSelectors.count == 2)
        #expect(relativeSelectors[0].leadingCombinator == .child)
        #expect(relativeSelectors[1].leadingCombinator == nil)
    }

    @Test("parses descendant and child chain")
    func parsesDescendantAndChildChain() throws {
        let ast = try self.parser.parse("AXWindow AXGroup > AXStaticText")
        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].links.count == 2)
        #expect(ast.selectors[0].links[0].combinator == .descendant)
        #expect(ast.selectors[0].links[1].combinator == .child)
    }

    @Test("parses whitespace around tokens")
    func parsesWithExtraWhitespace() throws {
        let ast = try self.parser.parse("  AXGroup  :has(  >  AXTextField  )   AXStaticText ")
        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].links.count == 2)
        #expect(ast.selectors[0].links[0].combinator == .descendant)
        #expect(ast.selectors[0].links[1].combinator == .descendant)
    }

    @Test("empty input is rejected")
    func rejectsEmptyInput() {
        self.expectParseError("", matches: { error in
            if case .emptyInput = error { return true }
            return false
        })
    }

    @Test("whitespace-only input is rejected")
    func rejectsWhitespaceOnlyInput() {
        self.expectParseError("   \n\t  ", matches: { error in
            if case .emptyInput = error { return true }
            return false
        })
    }

    @Test("unknown pseudo is rejected")
    func rejectsUnknownPseudo() {
        self.expectParseError("AXButton:foo(AXTextField)", matches: { error in
            if case let .unknownPseudo(name, _) = error {
                return name == "foo"
            }
            return false
        })
    }

    @Test("missing pseudo name is rejected")
    func rejectsMissingPseudoName() {
        self.expectParseError("AXButton:(AXTextField)", matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("empty not argument is rejected")
    func rejectsEmptyNotArgument() {
        self.expectParseError("AXButton:not()", matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("empty has argument is rejected")
    func rejectsEmptyHasArgument() {
        self.expectParseError("AXButton:has()", matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("trailing comma in selector list is rejected")
    func rejectsTrailingCommaInSelectorList() {
        self.expectParseError("AXButton,", matches: { error in
            if case .unexpectedEnd = error { return true }
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("trailing comma in attribute group is rejected")
    func rejectsTrailingCommaInAttributeGroup() {
        self.expectParseError(#"AXButton[AXTitle="X",]"#, matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("missing attribute name is rejected")
    func rejectsMissingAttributeName() {
        self.expectParseError(#"AXButton[="X"]"#, matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("missing attribute operator is rejected")
    func rejectsMissingAttributeOperator() {
        self.expectParseError(#"AXButton[AXTitle]"#, matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("missing attribute value is rejected")
    func rejectsMissingAttributeValue() {
        self.expectParseError(#"AXButton[AXTitle=]"#, matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("unquoted attribute value is rejected")
    func rejectsUnquotedAttributeValue() {
        self.expectParseError("AXButton[AXTitle=Ralph]", matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("unsupported operator is rejected")
    func rejectsUnsupportedOperator() {
        self.expectParseError(#"AXButton[AXTitle~="x"]"#, matches: { error in
            if case .unexpectedCharacter = error { return true }
            return false
        })
    }

    @Test("missing closing bracket is rejected")
    func rejectsMissingClosingBracket() {
        self.expectParseError(#"AXButton[AXTitle="x""#, matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("missing closing paren is rejected")
    func rejectsMissingClosingParen() {
        self.expectParseError("AXButton:not(AXTextField", matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("trailing child combinator is rejected")
    func rejectsTrailingChildCombinator() {
        self.expectParseError("AXGroup >", matches: { error in
            if case .unexpectedEnd = error { return true }
            return false
        })
    }

    @Test("missing selector after leading child combinator in has is rejected")
    func rejectsMissingSelectorAfterLeadingChildInHas() {
        self.expectParseError("AXGroup:has(>)", matches: { error in
            if case .unexpectedToken = error { return true }
            if case .unexpectedEnd = error { return true }
            return false
        })
    }

    @Test("extra token without combinator is rejected")
    func rejectsExtraTokenWithoutCombinator() {
        self.expectParseError("AXGroup:has(> AXTextField)AXStaticText", matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    @Test("double attribute groups are rejected by grammar")
    func rejectsDoubleAttributeGroups() {
        self.expectParseError(#"AXButton[AXTitle="x"][AXValue="y"]"#, matches: { error in
            if case .unexpectedToken = error { return true }
            return false
        })
    }

    private func expectParseError(_ query: String, matches matcher: (OXQParseError) -> Bool) {
        do {
            _ = try self.parser.parse(query)
            Issue.record("Expected parser error for query: \(query)")
        } catch let error as OXQParseError {
            #expect(matcher(error), "Unexpected parse error: \(error)")
        } catch {
            Issue.record("Unexpected error type for query '\(query)': \(error)")
        }
    }
}
