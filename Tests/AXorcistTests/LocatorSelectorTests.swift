import Foundation
import Testing
@testable import AXorcist

@Suite("Locator Selector")
struct LocatorSelectorTests {
    @Test("encodes and decodes locator selector")
    func encodesAndDecodesSelector() throws {
        let locator = Locator(
            criteria: [Criterion(attribute: "AXRole", value: "AXButton")],
            selector: #"AXGroup:has(> AXTextField) AXStaticText"#)

        let data = try JSONEncoder().encode(locator)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)

        #expect(decoded.selector == #"AXGroup:has(> AXTextField) AXStaticText"#)
        #expect(decoded.criteria.count == 1)
        #expect(decoded.criteria[0].attribute == "AXRole")
    }
}
