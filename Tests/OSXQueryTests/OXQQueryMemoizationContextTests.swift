import Testing
@testable import OSXQuery

@Suite("OXQ Query Memoization Context")
@MainActor
struct OXQQueryMemoizationContextTests {
    @Test("computes CPName from memoized primitive attributes")
    func computesComputedNameFromMemoizedAttributes() {
        let node = MemoNode(id: "n1")
        let probe = AttributeProbe()

        let context = OXQQueryMemoizationContext<MemoNode>(
            childrenProvider: { _ in [] },
            roleProvider: { _ in "AXButton" },
            attributeValueProvider: { _, attributeName in
                probe.record(attributeName)
                switch attributeName {
                case AXAttributeNames.kAXTitleAttribute:
                    return "Liam"
                case AXAttributeNames.kAXValueAttribute:
                    return "ignored"
                case AXMiscConstants.computedNameAttributeKey:
                    return "SHOULD_NOT_BE_USED"
                default:
                    return nil
                }
            },
            preferDerivedComputedName: true)

        let computedName = context.attributeValue(of: node, attributeName: AXMiscConstants.computedNameAttributeKey)
        #expect(computedName == "Liam")
        #expect((probe.totalReads[AXMiscConstants.computedNameAttributeKey] ?? 0) == 0)

        let title = context.attributeValue(of: node, attributeName: AXAttributeNames.kAXTitleAttribute)
        #expect(title == "Liam")
        #expect((probe.totalReads[AXAttributeNames.kAXTitleAttribute] ?? 0) == 1)
    }

    @Test("caches computed name details per node within a single context")
    func cachesComputedNamePerNodeWithinContext() {
        let node = MemoNode(id: "n2")
        let probe = AttributeProbe()

        let context = OXQQueryMemoizationContext<MemoNode>(
            childrenProvider: { _ in [] },
            roleProvider: { _ in "AXTextArea" },
            attributeValueProvider: { _, attributeName in
                probe.record(attributeName)
                if attributeName == AXAttributeNames.kAXValueAttribute {
                    return "Ask anything"
                }
                return nil
            },
            preferDerivedComputedName: true)

        let first = context.attributeValue(of: node, attributeName: AXMiscConstants.computedNameAttributeKey)
        let second = context.attributeValue(of: node, attributeName: AXMiscConstants.computedNameAttributeKey)

        #expect(first == "Ask anything")
        #expect(second == "Ask anything")
        #expect((probe.totalReads[AXAttributeNames.kAXValueAttribute] ?? 0) == 1)
    }
}

private struct MemoNode: Hashable {
    let id: String
}

private final class AttributeProbe {
    var totalReads: [String: Int] = [:]

    func record(_ attributeName: String) {
        self.totalReads[attributeName, default: 0] += 1
    }
}
