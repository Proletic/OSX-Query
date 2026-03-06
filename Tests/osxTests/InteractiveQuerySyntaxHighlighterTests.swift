import Testing
@testable import osx

@Suite("Interactive Query Syntax Highlighter")
struct InteractiveQuerySyntaxHighlighterTests {
    @Test("Returns query unchanged when highlighting is disabled")
    func disabledHighlightingReturnsOriginalQuery() {
        let query = "AXGroup:has(AXStaticText[AXValue=\"Ralph\"])"
        let highlighted = OXQInteractiveSyntaxHighlighter.highlight(query, enabled: false)
        #expect(highlighted == query)
    }

    @Test("Applies role, attribute, function, and string colors")
    func appliesExpectedTokenColors() {
        let query = "AXGroup:has(AXStaticText[AXValue=\"Ralph\"])"
        let highlighted = OXQInteractiveSyntaxHighlighter.highlight(query, enabled: true)

        #expect(highlighted.contains(
            OXQInteractiveSyntaxHighlighter.roleColor + "AXGroup" + OXQInteractiveSyntaxHighlighter.resetColor))
        #expect(highlighted.contains(
            OXQInteractiveSyntaxHighlighter.roleColor + "AXStaticText" + OXQInteractiveSyntaxHighlighter.resetColor))
        #expect(highlighted.contains(
            OXQInteractiveSyntaxHighlighter.functionColor + "has" + OXQInteractiveSyntaxHighlighter.resetColor))
        #expect(highlighted.contains(
            OXQInteractiveSyntaxHighlighter.attributeColor + "AXValue" + OXQInteractiveSyntaxHighlighter.resetColor))
        #expect(highlighted.contains(
            OXQInteractiveSyntaxHighlighter.stringColor + "\"Ralph\"" + OXQInteractiveSyntaxHighlighter.resetColor))
    }
}
