import Foundation
import Testing
@testable import OSXQuery

@Suite("OXQ Parser")
struct OXQParserTests {
    private let parser = OXQParser()

    @Test("parses wildcard selector")
    func parsesWildcardSelector() throws {
        let ast = try self.parser.parse("*")

        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].leading.typeSelector == .wildcard)
        #expect(ast.selectors[0].leading.attributes.isEmpty)
        #expect(ast.selectors[0].leading.pseudos.isEmpty)
        #expect(ast.selectors[0].links.isEmpty)
    }

    @Test("parses descendant selection")
    func parsesDescendantSelection() throws {
        let ast = try self.parser.parse("AXGroup AXStaticText")

        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].leading.typeSelector == .role("AXGroup"))
        #expect(ast.selectors[0].links.count == 1)
        #expect(ast.selectors[0].links[0].combinator == .descendant)
        #expect(ast.selectors[0].links[0].compound.typeSelector == .role("AXStaticText"))
    }

    @Test("parses child combinator")
    func parsesChildCombinator() throws {
        let ast = try self.parser.parse("AXGroup > AXTextField")

        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].links.count == 1)
        #expect(ast.selectors[0].links[0].combinator == .child)
        #expect(ast.selectors[0].links[0].compound.typeSelector == .role("AXTextField"))
    }

    @Test("parses attributes with multiple operators")
    func parsesAttributeGroup() throws {
        let ast = try self.parser.parse(#"AXStaticText[AXValue="Ralph", AXTitle*="Spotify"]"#)

        #expect(ast.selectors.count == 1)
        let attrs = ast.selectors[0].leading.attributes
        #expect(attrs.count == 2)
        #expect(attrs[0] == OXQAttributeMatch(name: "AXValue", op: .equals, value: "Ralph"))
        #expect(attrs[1] == OXQAttributeMatch(name: "AXTitle", op: .contains, value: "Spotify"))
    }

    @Test("parses has with relative selector")
    func parsesHasRelativeSelector() throws {
        let ast = try self.parser.parse("AXGroup:has(> AXTextField)")

        #expect(ast.selectors.count == 1)
        guard case let .has(argument) = ast.selectors[0].leading.pseudos[0] else {
            Issue.record("Expected :has pseudo")
            return
        }

        guard case let .relativeSelectors(relativeSelectors) = argument else {
            Issue.record("Expected relative selector list for :has")
            return
        }

        #expect(relativeSelectors.count == 1)
        #expect(relativeSelectors[0].leadingCombinator == .child)
        #expect(relativeSelectors[0].selector.leading.typeSelector == .role("AXTextField"))
    }

    @Test("parses has followed by descendant selector")
    func parsesHasThenDescendantSelection() throws {
        let ast = try self.parser.parse("AXGroup:has(> AXTextField) AXStaticText")

        #expect(ast.selectors.count == 1)
        #expect(ast.selectors[0].links.count == 1)
        #expect(ast.selectors[0].links[0].combinator == .descendant)
        #expect(ast.selectors[0].links[0].compound.typeSelector == .role("AXStaticText"))
    }

    @Test("parses not pseudo")
    func parsesNotPseudo() throws {
        let ast = try self.parser.parse(#"AXTextArea:not([AXValue*="test"])"#)

        #expect(ast.selectors.count == 1)
        guard case let .not(selectors) = ast.selectors[0].leading.pseudos[0] else {
            Issue.record("Expected :not pseudo")
            return
        }

        #expect(selectors.count == 1)
        #expect(selectors[0].leading.attributes.count == 1)
        #expect(selectors[0].leading.attributes[0] == OXQAttributeMatch(name: "AXValue", op: .contains, value: "test"))
    }

    @Test("parses selector disjunction")
    func parsesSelectorDisjunction() throws {
        let ast = try self.parser.parse("AXTextArea, AXTextField, AXComboBox")

        #expect(ast.selectors.count == 3)
        #expect(ast.selectors.map { $0.leading.typeSelector } == [.role("AXTextArea"), .role("AXTextField"), .role("AXComboBox")])
    }

    @Test("fails on unknown pseudo")
    func failsOnUnknownPseudo() {
        do {
            _ = try self.parser.parse("AXGroup:foo(AXTextField)")
            Issue.record("Expected parse failure.")
        } catch let error as OXQParseError {
            guard case let .unknownPseudo(name, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(name == "foo")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
