import ApplicationServices
import Darwin
import Testing
@testable import AXorcist

@Suite("Element Hierarchy Batching")
@MainActor
struct ElementHierarchyBatchingTests {
    @Test("decodes AXUIElement arrays from batched values")
    func decodesAXUIElementArrays() {
        let element = AXUIElementCreateApplication(getpid())
        let decoded = Element.decodeAlternativeChildrenValue([element])

        #expect(decoded?.count == 1)
        #expect(decoded?.first.map { CFEqual($0, element) } == true)
    }

    @Test("decodes single AXUIElement from batched values")
    func decodesSingleAXUIElement() {
        let element = AXUIElementCreateSystemWide()
        let decoded = Element.decodeAlternativeChildrenValue(element)

        #expect(decoded?.count == 1)
        #expect(decoded?.first.map { CFEqual($0, element) } == true)
    }

    @Test("decodes mixed arrays by keeping AXUIElement entries")
    func decodesMixedArrays() {
        let first = AXUIElementCreateSystemWide()
        let second = AXUIElementCreateApplication(getpid())
        let decoded = Element.decodeAlternativeChildrenValue([first, "skip-me", second, 42])

        #expect(decoded?.count == 2)
        #expect(decoded?.contains(where: { CFEqual($0, first) }) == true)
        #expect(decoded?.contains(where: { CFEqual($0, second) }) == true)
    }

    @Test("returns nil for null and unsupported values")
    func returnsNilForUnsupportedValues() {
        #expect(Element.decodeAlternativeChildrenValue(NSNull()) == nil)
        #expect(Element.decodeAlternativeChildrenValue("not-an-element") == nil)
        #expect(Element.decodeAlternativeChildrenValue(123) == nil)
        #expect(Element.decodeAlternativeChildrenValue([String]()) == nil)
    }
}
