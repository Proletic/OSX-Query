import Foundation
import Testing
@testable import AXorcist

@Suite("OXQ Selector Engine")
@MainActor
struct OXQSelectorEngineTests {
    @Test("matches descendant and child combinators")
    func matchesCombinators() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let descendantMatches = try engine.findAll(matching: "AXGroup AXStaticText", from: fixture.root, maxDepth: 10)
        #expect(fixture.ids(descendantMatches) == ["staticA", "staticB", "staticParent", "staticChild"])

        let childMatches = try engine.findAll(matching: "AXGroup > AXTextField", from: fixture.root, maxDepth: 10)
        #expect(fixture.ids(childMatches) == ["textFieldA"])
    }

    @Test("matches attribute operators")
    func matchesAttributeOperators() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        #expect(
            fixture.ids(try engine.findAll(
                matching: #"AXStaticText[AXValue="Ralph"]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA"])

        #expect(
            fixture.ids(try engine.findAll(
                matching: #"AXStaticText[AXTitle*="Spotify"]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA"])

        #expect(
            fixture.ids(try engine.findAll(
                matching: #"AXStaticText[AXTitle^="Spot"]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA"])

        #expect(
            fixture.ids(try engine.findAll(
                matching: #"AXStaticText[AXTitle$="Song"]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA"])
    }

    @Test("evaluates not pseudo")
    func evaluatesNotPseudo() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: #"AXTextArea:not([AXValue*="test"])"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(matches) == ["textAreaB"])
    }

    @Test("evaluates has pseudo for descendants and children")
    func evaluatesHasPseudo() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let descendantMatches = try engine.findAll(
            matching: "AXGroup:has(AXStaticText)",
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(descendantMatches) == ["groupA", "groupB", "groupC"])

        let childMatches = try engine.findAll(
            matching: "AXGroup:has(> AXTextField)",
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(childMatches) == ["groupA"])

        let relativeChainMatches = try engine.findAll(
            matching: "AXGroup:has(> AXTextField) AXStaticText",
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(relativeChainMatches) == ["staticA"])
    }

    @Test("supports disjunction and de-duplicates results")
    func supportsDisjunctionDedup() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: "AXStaticText, AXGroup AXStaticText",
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(matches) == ["staticA", "staticB", "staticParent", "staticChild"])
    }

    @Test("applies max depth when indexing tree")
    func appliesMaxDepth() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let shallow = try engine.findAll(matching: "AXStaticText", from: fixture.root, maxDepth: 3)
        #expect(fixture.ids(shallow) == ["staticA", "staticB", "staticParent"])

        let deep = try engine.findAll(matching: "AXStaticText", from: fixture.root, maxDepth: 10)
        #expect(fixture.ids(deep) == ["staticA", "staticB", "staticParent", "staticChild"])
    }

    @Test("selector evaluation is right-to-left")
    func evaluatesRightToLeft() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: "AXWindow AXGroup > AXStaticText",
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(matches) == ["staticA", "staticB", "staticParent"])
    }

    @Test("supports not with complex selector argument")
    func supportsNotWithComplexSelectorArgument() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: "AXStaticText:not(AXGroup AXStaticText)",
            from: fixture.root,
            maxDepth: 10)
        #expect(matches.isEmpty)
    }

    @Test("filters by role before attributes")
    func filtersByRoleBeforeAttributes() throws {
        let fixture = FakeTreeFixture()
        let probe = AttributeProbe()
        let engine = fixture.makeEngine(probe: probe)

        let matches = try engine.findAll(
            matching: #"AXButton[AXTitle="Save"]"#,
            from: fixture.root,
            maxDepth: 10)

        #expect(fixture.ids(matches) == ["buttonSave"])
        #expect(probe.totalReads["AXTitle"] == 2)
    }
}

private struct FakeNode: Hashable, Sendable {
    let id: String
}

private final class AttributeProbe {
    var totalReads: [String: Int] = [:]

    func record(_ attributeName: String) {
        self.totalReads[attributeName, default: 0] += 1
    }
}

@MainActor
private struct FakeTreeFixture {
    let root = FakeNode(id: "root")

    private let nodes: [FakeNode] = [
        FakeNode(id: "root"),
        FakeNode(id: "window"),
        FakeNode(id: "groupA"),
        FakeNode(id: "groupB"),
        FakeNode(id: "groupC"),
        FakeNode(id: "textFieldA"),
        FakeNode(id: "staticA"),
        FakeNode(id: "staticB"),
        FakeNode(id: "staticParent"),
        FakeNode(id: "staticChild"),
        FakeNode(id: "textAreaA"),
        FakeNode(id: "textAreaB"),
        FakeNode(id: "buttonSave"),
        FakeNode(id: "buttonCancel"),
    ]

    private let roleByID: [String: String] = [
        "root": "AXApplication",
        "window": "AXWindow",
        "groupA": "AXGroup",
        "groupB": "AXGroup",
        "groupC": "AXGroup",
        "textFieldA": "AXTextField",
        "staticA": "AXStaticText",
        "staticB": "AXStaticText",
        "staticParent": "AXStaticText",
        "staticChild": "AXStaticText",
        "textAreaA": "AXTextArea",
        "textAreaB": "AXTextArea",
        "buttonSave": "AXButton",
        "buttonCancel": "AXButton",
    ]

    private let attributesByID: [String: [String: String]] = [
        "window": ["AXTitle": "Main Window"],
        "staticA": ["AXValue": "Ralph", "AXTitle": "Spotify Song"],
        "staticB": ["AXValue": "Other"],
        "staticParent": ["AXValue": "Parent"],
        "staticChild": ["AXValue": "Child"],
        "textAreaA": ["AXValue": "test draft"],
        "textAreaB": ["AXValue": "notes"],
        "buttonSave": ["AXTitle": "Save"],
        "buttonCancel": ["AXTitle": "Cancel"],
        "textFieldA": ["AXValue": "Ralph"],
    ]

    private let childIDsByID: [String: [String]] = [
        "root": ["window"],
        "window": ["groupA", "groupB", "buttonSave", "buttonCancel", "groupC"],
        "groupA": ["textFieldA", "staticA", "textAreaA", "textAreaB"],
        "groupB": ["staticB"],
        "groupC": ["staticParent"],
        "staticParent": ["staticChild"],
    ]

    func makeEngine(probe: AttributeProbe? = nil) -> OXQSelectorEngine<FakeNode> {
        let nodeByID = Dictionary(uniqueKeysWithValues: self.nodes.map { ($0.id, $0) })

        return OXQSelectorEngine<FakeNode>(
            children: { node in
                let childIDs = self.childIDsByID[node.id] ?? []
                return childIDs.compactMap { nodeByID[$0] }
            },
            role: { node in
                self.roleByID[node.id]
            },
            attributeValue: { node, attributeName in
                probe?.record(attributeName)
                if attributeName == AXAttributeNames.kAXRoleAttribute {
                    return self.roleByID[node.id]
                }
                return self.attributesByID[node.id]?[attributeName]
            })
    }

    func ids(_ nodes: [FakeNode]) -> [String] {
        nodes.map(\.id)
    }
}
