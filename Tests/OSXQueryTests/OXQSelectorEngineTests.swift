import Foundation
import Testing
@testable import OSXQuery

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
                matching: #"AXStaticText[AXTitle*="spotify"]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA"])

        #expect(
            fixture.ids(try engine.findAll(
                matching: #"AXStaticText[AXValue*=""]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA", "staticB", "staticParent", "staticChild"])

        #expect(
            (try engine.findAll(
                matching: #"AXButton[AXValue*=""]"#,
                from: fixture.root,
                maxDepth: 10)).isEmpty)

        #expect(
            fixture.ids(try engine.findAll(
                matching: #"AXStaticText[AXTitle^="Spot"]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA"])

        #expect(
            (try engine.findAll(
                matching: #"AXStaticText[AXTitle^="spot"]"#,
                from: fixture.root,
                maxDepth: 10)).isEmpty)

        #expect(
            fixture.ids(try engine.findAll(
                matching: #"AXStaticText[AXTitle$="Song"]"#,
                from: fixture.root,
                maxDepth: 10)) == ["staticA"])

        #expect(
            (try engine.findAll(
                matching: #"AXStaticText[AXTitle$="song"]"#,
                from: fixture.root,
                maxDepth: 10)).isEmpty)
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

    @Test("uses unlimited max depth by default")
    func usesUnlimitedMaxDepthByDefault() throws {
        let root = FakeNode(id: "deepRoot")
        let chain = (0...15).map { FakeNode(id: "n\($0)") }
        let deepLeaf = FakeNode(id: "deepLeaf")

        var childrenMap: [FakeNode: [FakeNode]] = [root: [chain[0]]]
        for index in 0..<(chain.count - 1) {
            childrenMap[chain[index]] = [chain[index + 1]]
        }
        childrenMap[chain.last!] = [deepLeaf]

        var roles: [FakeNode: String] = [root: "AXApplication", deepLeaf: "AXStaticText"]
        for node in chain {
            roles[node] = "AXGroup"
        }

        let engine = OXQSelectorEngine<FakeNode>(
            children: { node in childrenMap[node] ?? [] },
            role: { node in roles[node] },
            attributeValue: { _, _ in nil })

        let defaultDepthMatches = try engine.findAll(matching: "AXStaticText", from: root)
        #expect(defaultDepthMatches.map(\.id) == ["deepLeaf"])

        let cappedMatches = try engine.findAll(matching: "AXStaticText", from: root, maxDepth: 10)
        #expect(cappedMatches.isEmpty)
    }

    @Test("reprocesses node when discovered at a shallower depth")
    func reprocessesNodeWhenDiscoveredAtShallowerDepth() throws {
        let root = FakeNode(id: "rootDepth")
        let deepOne = FakeNode(id: "deepOne")
        let deepTwo = FakeNode(id: "deepTwo")
        let shared = FakeNode(id: "shared")
        let target = FakeNode(id: "target")

        // DFS sees shared first via root->deepOne->deepTwo->shared (depth 3). At maxDepth 3, shared's
        // children are not traversed on that first visit. Later root->shared (depth 1) should reprocess.
        let childrenMap: [FakeNode: [FakeNode]] = [
            root: [deepOne, shared],
            deepOne: [deepTwo],
            deepTwo: [shared],
            shared: [target],
        ]

        let roles: [FakeNode: String] = [
            root: "AXApplication",
            deepOne: "AXGroup",
            deepTwo: "AXGroup",
            shared: "AXGroup",
            target: "AXStaticText",
        ]

        let engine = OXQSelectorEngine<FakeNode>(
            children: { node in childrenMap[node] ?? [] },
            role: { node in roles[node] },
            attributeValue: { _, _ in nil })

        let matches = try engine.findAll(matching: "AXStaticText", from: root, maxDepth: 3)
        #expect(matches.map(\.id) == ["target"])
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

    @Test("does not evaluate attributes when role prefilter has no candidates")
    func skipsAttributeReadsWhenRoleHasNoCandidates() throws {
        let fixture = FakeTreeFixture()
        let probe = AttributeProbe()
        let engine = fixture.makeEngine(probe: probe)

        let matches = try engine.findAll(
            matching: #"AXUnknownRole[AXTitle="Save"]"#,
            from: fixture.root,
            maxDepth: 10)

        #expect(matches.isEmpty)
        #expect((probe.totalReads["AXTitle"] ?? 0) == 0)
    }

    @Test("propagates parser errors for invalid selectors")
    func propagatesParserErrors() {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        do {
            _ = try engine.findAll(matching: "AXGroup:has(", from: fixture.root, maxDepth: 10)
            Issue.record("Expected parse failure")
        } catch let error as OXQParseError {
            if case .emptyInput = error {
                #expect(Bool(true))
                return
            }
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("returns no match for impossible structural chain")
    func returnsNoMatchForImpossibleChain() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: "AXWindow > AXTextField",
            from: fixture.root,
            maxDepth: 10)

        #expect(matches.isEmpty)
    }

    @Test("distinguishes has child from has descendant")
    func distinguishesHasChildFromHasDescendant() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let descendantMatches = try engine.findAll(
            matching: #"AXGroup:has(AXStaticText[AXValue="Child"])"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(descendantMatches) == ["groupC"])

        let childMatches = try engine.findAll(
            matching: #"AXGroup:has(> AXStaticText[AXValue="Child"])"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(childMatches.isEmpty)
    }

    @Test("anchors relative has selector chains to :scope")
    func anchorsRelativeHasSelectorChainsToScope() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let parentMatches = try engine.findAll(
            matching: #":has(> [CPName*="Child"])"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(parentMatches) == ["staticParent"])

        let grandparentMatches = try engine.findAll(
            matching: #":has(> * > [CPName*="Child"])"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(grandparentMatches) == ["groupC"])
    }

    @Test("evaluates not pseudo with selector list")
    func evaluatesNotPseudoWithSelectorList() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: #"AXStaticText:not([AXValue="Ralph"], [AXValue="Other"])"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(matches) == ["staticParent", "staticChild"])
    }

    @Test("supports attribute alias mapping")
    func supportsAttributeAliasMapping() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: #"*[role="AXButton"]"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(matches) == ["buttonSave", "buttonCancel"])
    }

    @Test("supports computed name alias mapping via CPName")
    func supportsComputedNameAliasMappingViaCPName() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(
            matching: #"*[CPName*="ave"]"#,
            from: fixture.root,
            maxDepth: 10)
        #expect(fixture.ids(matches) == ["buttonSave"])
    }

    @Test("handles negative max depth as zero")
    func handlesNegativeMaxDepth() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let matches = try engine.findAll(matching: "*", from: fixture.root, maxDepth: -1)
        #expect(fixture.ids(matches) == ["root"])
    }

    @Test("handles cycles safely")
    func handlesCyclesSafely() throws {
        let root = FakeNode(id: "rootCycle")
        let a = FakeNode(id: "a")
        let b = FakeNode(id: "b")

        let childrenMap: [FakeNode: [FakeNode]] = [
            root: [a],
            a: [b],
            b: [a], // cycle
        ]

        let roles: [FakeNode: String] = [
            root: "AXApplication",
            a: "AXGroup",
            b: "AXStaticText",
        ]

        let engine = OXQSelectorEngine<FakeNode>(
            children: { node in childrenMap[node] ?? [] },
            role: { node in roles[node] },
            attributeValue: { node, attr in
                if attr == AXAttributeNames.kAXRoleAttribute {
                    return roles[node]
                }
                return nil
            })

        let matches = try engine.findAll(matching: "*", from: root, maxDepth: 10)
        #expect(matches.map(\.id) == ["rootCycle", "a", "b"])
    }

    @Test("memoization avoids repeated attribute reads inside a single query")
    func memoizationAvoidsRepeatedAttributeReadsWithinQuery() throws {
        let fixture = FakeTreeFixture()
        let probe = AttributeProbe()
        let engine = fixture.makeEngine(probe: probe)

        let matches = try engine.findAll(
            matching: #"AXStaticText[AXTitle*="Spotify", AXTitle$="Song"]"#,
            from: fixture.root,
            maxDepth: 10)

        #expect(fixture.ids(matches) == ["staticA"])
        #expect(probe.totalReads["AXTitle"] == 4)
    }

    @Test("memoization is short-lived and does not persist between queries")
    func memoizationIsShortLivedAcrossQueries() throws {
        let fixture = FakeTreeFixture()
        let probe = AttributeProbe()
        let engine = fixture.makeEngine(probe: probe)

        _ = try engine.findAll(
            matching: #"AXStaticText[AXValue*=""]"#,
            from: fixture.root,
            maxDepth: 10)
        let firstReadCount = probe.totalReads["AXValue"] ?? 0
        #expect(firstReadCount == 4)

        _ = try engine.findAll(
            matching: #"AXStaticText[AXValue*=""]"#,
            from: fixture.root,
            maxDepth: 10)
        let secondReadCount = probe.totalReads["AXValue"] ?? 0
        #expect(secondReadCount == 8)
    }

    @Test("skips role lookups for selectors that do not reference roles")
    func skipsRoleLookupsWhenSelectorDoesNotReferenceRoles() throws {
        let fixture = FakeTreeFixture()
        let roleProbe = RoleProbe()
        let engine = fixture.makeEngine(roleProbe: roleProbe)

        let matches = try engine.findAll(matching: "*", from: fixture.root, maxDepth: 10)
        #expect(fixture.ids(matches).count == fixture.nodeCount)
        #expect(roleProbe.totalReads == 0)
    }

    @Test("builds role index when selector references roles")
    func buildsRoleIndexWhenSelectorReferencesRoles() throws {
        let fixture = FakeTreeFixture()
        let roleProbe = RoleProbe()
        let engine = fixture.makeEngine(roleProbe: roleProbe)

        let matches = try engine.findAll(matching: "AXButton", from: fixture.root, maxDepth: 10)
        #expect(fixture.ids(matches) == ["buttonSave", "buttonCancel"])
        #expect(roleProbe.totalReads == fixture.nodeCount)
    }

    @Test("reports traversed node count for query")
    func reportsTraversedNodeCount() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let evaluation = try engine.findAllWithMetrics(
            matching: "AXButton",
            from: fixture.root,
            maxDepth: 10)

        #expect(fixture.ids(evaluation.matches) == ["buttonSave", "buttonCancel"])
        #expect(evaluation.traversedNodeCount == fixture.nodeCount)
    }

    @Test("reports traversed node count with max depth applied")
    func reportsTraversedNodeCountWithMaxDepth() throws {
        let fixture = FakeTreeFixture()
        let engine = fixture.makeEngine()

        let evaluation = try engine.findAllWithMetrics(
            matching: "*",
            from: fixture.root,
            maxDepth: 3)

        #expect(fixture.ids(evaluation.matches).count == 13)
        #expect(evaluation.traversedNodeCount == 13)
    }

    @Test("matches ancestor relationships when a node is reachable by multiple parents")
    func matchesAncestorRelationshipsWithMultipleParentPaths() throws {
        let app = FakeNode(id: "app")
        let window = FakeNode(id: "window")
        let container = FakeNode(id: "container")
        let textArea = FakeNode(id: "textArea")

        // `textArea` is reachable both from AXApplication extras and from the AXWindow subtree.
        // This mirrors app-level AX extras like AXFocusedUIElement.
        let childrenMap: [FakeNode: [FakeNode]] = [
            app: [window, textArea],
            window: [container],
            container: [textArea],
        ]

        let roles: [FakeNode: String] = [
            app: "AXApplication",
            window: "AXWindow",
            container: "AXGroup",
            textArea: "AXTextArea",
        ]

        let attributes: [FakeNode: [String: String]] = [
            textArea: [AXMiscConstants.computedNameAttributeKey: "Ask anything"],
        ]

        let engine = OXQSelectorEngine<FakeNode>(
            children: { node in childrenMap[node] ?? [] },
            role: { node in roles[node] },
            attributeValue: { node, attributeName in
                if attributeName == AXAttributeNames.kAXRoleAttribute {
                    return roles[node]
                }
                return attributes[node]?[attributeName]
            })

        let appDirectMatches = try engine.findAll(
            matching: #"AXApplication > AXTextArea[CPName*="Ask anything"]"#,
            from: app,
            maxDepth: 10)
        #expect(appDirectMatches.map(\.id) == ["textArea"])

        let descendantMatches = try engine.findAll(
            matching: #"AXWindow AXTextArea[CPName*="Ask anything"]"#,
            from: app,
            maxDepth: 10)
        #expect(descendantMatches.map(\.id) == ["textArea"])

        let hasMatches = try engine.findAll(
            matching: #"AXWindow:has(AXTextArea[CPName*="Ask anything"])"#,
            from: app,
            maxDepth: 10)
        #expect(hasMatches.map(\.id) == ["window"])
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

private final class RoleProbe {
    var totalReads = 0

    func record() {
        self.totalReads += 1
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
        "staticParent": ["AXValue": "Parent", AXMiscConstants.computedNameAttributeKey: "Parent"],
        "staticChild": ["AXValue": "Child", AXMiscConstants.computedNameAttributeKey: "Child"],
        "textAreaA": ["AXValue": "test draft"],
        "textAreaB": ["AXValue": "notes"],
        "buttonSave": ["AXTitle": "Save", AXMiscConstants.computedNameAttributeKey: "Save"],
        "buttonCancel": ["AXTitle": "Cancel", AXMiscConstants.computedNameAttributeKey: "Cancel"],
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

    var nodeCount: Int { self.nodes.count }

    func makeEngine(probe: AttributeProbe? = nil, roleProbe: RoleProbe? = nil) -> OXQSelectorEngine<FakeNode> {
        let nodeByID = Dictionary(uniqueKeysWithValues: self.nodes.map { ($0.id, $0) })

        return OXQSelectorEngine<FakeNode>(
            children: { node in
                let childIDs = self.childIDsByID[node.id] ?? []
                return childIDs.compactMap { nodeByID[$0] }
            },
            role: { node in
                roleProbe?.record()
                return self.roleByID[node.id]
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
