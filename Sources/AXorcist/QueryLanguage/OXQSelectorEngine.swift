import Foundation

public struct OXQSelectorEvaluation<Node> {
    public let matches: [Node]
    public let traversedNodeCount: Int
}

@MainActor
public final class OXQSelectorEngine<Node: Hashable> {
    // MARK: Lifecycle

    public init(
        parser: OXQParser = OXQParser(),
        children: @escaping (Node) -> [Node],
        role: @escaping (Node) -> String?,
        attributeValue: @escaping (Node, String) -> String?)
    {
        self.parser = parser
        self.childrenProvider = children
        self.roleProvider = role
        self.attributeValueProvider = attributeValue
    }

    // MARK: Public

    public func findAll(
        matching query: String,
        from root: Node,
        maxDepth: Int = .max,
        memoizationContext: OXQQueryMemoizationContext<Node>? = nil) throws -> [Node]
    {
        try self.findAllWithMetrics(
            matching: query,
            from: root,
            maxDepth: maxDepth,
            memoizationContext: memoizationContext).matches
    }

    public func findAllWithMetrics(
        matching query: String,
        from root: Node,
        maxDepth: Int = .max,
        memoizationContext: OXQQueryMemoizationContext<Node>? = nil) throws -> OXQSelectorEvaluation<Node>
    {
        let syntaxTree = try self.parser.parse(query)
        return self.findAllWithMetrics(
            matching: syntaxTree,
            from: root,
            maxDepth: maxDepth,
            memoizationContext: memoizationContext)
    }

    public func findFirst(
        matching query: String,
        from root: Node,
        maxDepth: Int = .max,
        memoizationContext: OXQQueryMemoizationContext<Node>? = nil) throws -> Node?
    {
        try self.findAll(
            matching: query,
            from: root,
            maxDepth: maxDepth,
            memoizationContext: memoizationContext).first
    }

    public func findAll(
        matching syntaxTree: OXQSyntaxTree,
        from root: Node,
        maxDepth: Int = .max,
        memoizationContext: OXQQueryMemoizationContext<Node>? = nil) -> [Node]
    {
        self.findAllWithMetrics(
            matching: syntaxTree,
            from: root,
            maxDepth: maxDepth,
            memoizationContext: memoizationContext).matches
    }

    public func findAllWithMetrics(
        matching syntaxTree: OXQSyntaxTree,
        from root: Node,
        maxDepth: Int = .max,
        memoizationContext: OXQQueryMemoizationContext<Node>? = nil) -> OXQSelectorEvaluation<Node>
    {
        let safeMaxDepth = max(0, maxDepth)
        let memoization = memoizationContext ?? self.makeMemoizationContext()
        let needsRoleIndex = syntaxTree.requiresRoleLookups
        let indexedTree = OXQIndexedTree(
            root: root,
            maxDepth: safeMaxDepth,
            childrenProvider: { memoization.children(of: $0) },
            roleProvider: needsRoleIndex ? { memoization.role(of: $0) } : nil)
        var evaluator = OXQEvaluator(
            syntaxTree: syntaxTree,
            indexedTree: indexedTree,
            roleProvider: { memoization.role(of: $0) },
            attributeValueProvider: { memoization.attributeValue(of: $0, attributeName: $1) })
        let matches = evaluator.evaluateAll()
        return OXQSelectorEvaluation(
            matches: matches,
            traversedNodeCount: indexedTree.nodesInTraversalOrder.count)
    }

    public func findFirst(
        matching syntaxTree: OXQSyntaxTree,
        from root: Node,
        maxDepth: Int = .max,
        memoizationContext: OXQQueryMemoizationContext<Node>? = nil) -> Node?
    {
        self.findAll(
            matching: syntaxTree,
            from: root,
            maxDepth: maxDepth,
            memoizationContext: memoizationContext).first
    }

    // MARK: Private

    private let parser: OXQParser
    private let childrenProvider: (Node) -> [Node]
    private let roleProvider: (Node) -> String?
    private let attributeValueProvider: (Node, String) -> String?

    private func makeMemoizationContext() -> OXQQueryMemoizationContext<Node> {
        OXQQueryMemoizationContext<Node>(
            childrenProvider: self.childrenProvider,
            roleProvider: self.roleProvider,
            attributeValueProvider: self.attributeValueProvider)
    }
}

private struct OXQIndexedTree<Node: Hashable> {
    // MARK: Lifecycle

    init(
        root: Node,
        maxDepth: Int,
        childrenProvider: (Node) -> [Node],
        roleProvider: ((Node) -> String?)?)
    {
        self.root = root
        var nodesInTraversalOrder: [Node] = []
        var parentsByNode: [Node: Set<Node>] = [:]
        var childrenByNode: [Node: [Node]] = [:]
        var roleByNode: [Node: String] = [:]
        var roleIndex: [String: [Node]] = [:]
        var bestDepthByNode: [Node: Int] = [:]
        var stack: [(node: Node, depth: Int, parent: Node?)] = [(node: root, depth: 0, parent: nil)]

        while let entry = stack.popLast() {
            let node = entry.node
            let depth = entry.depth

            if let parent = entry.parent {
                parentsByNode[node, default: []].insert(parent)
            }

            if let bestDepth = bestDepthByNode[node], depth >= bestDepth {
                continue
            }

            let isFirstVisit = bestDepthByNode[node] == nil
            bestDepthByNode[node] = depth

            if isFirstVisit {
                nodesInTraversalOrder.append(node)
                if let roleProvider {
                    let role = roleProvider(node)
                    if let role {
                        roleByNode[node] = role
                        roleIndex[role, default: []].append(node)
                    }
                }
            }

            let children = depth < maxDepth ? childrenProvider(node) : []
            childrenByNode[node] = children

            for child in children.reversed() {
                stack.append((node: child, depth: depth + 1, parent: node))
            }
        }

        self.nodesInTraversalOrder = nodesInTraversalOrder
        self.parentsByNode = parentsByNode
        self.childrenByNode = childrenByNode
        self.roleByNode = roleByNode
        self.roleIndex = roleIndex
    }

    // MARK: Internal

    let root: Node
    let nodesInTraversalOrder: [Node]
    let parentsByNode: [Node: Set<Node>]
    let childrenByNode: [Node: [Node]]
    let roleByNode: [Node: String]
    let roleIndex: [String: [Node]]
}

private struct OXQEvaluator<Node: Hashable> {
    // MARK: Lifecycle

    init(
        syntaxTree: OXQSyntaxTree,
        indexedTree: OXQIndexedTree<Node>,
        roleProvider: @escaping (Node) -> String?,
        attributeValueProvider: @escaping (Node, String) -> String?)
    {
        self.syntaxTree = syntaxTree
        self.indexedTree = indexedTree
        self.roleProvider = roleProvider
        self.attributeValueProvider = attributeValueProvider
    }

    // MARK: Internal

    mutating func evaluateAll() -> [Node] {
        var matchedNodes = Set<Node>()

        for selector in self.syntaxTree.selectors {
            for node in self.evaluateSelector(selector) {
                matchedNodes.insert(node)
            }
        }

        return self.indexedTree.nodesInTraversalOrder.filter { matchedNodes.contains($0) }
    }

    // MARK: Private

    private let syntaxTree: OXQSyntaxTree
    private let indexedTree: OXQIndexedTree<Node>
    private let roleProvider: (Node) -> String?
    private let attributeValueProvider: (Node, String) -> String?

    private var compoundMatchCache: [OXQCompoundMatchKey<Node>: Bool] = [:]
    private var selectorSubjectMatchCache: [OXQSelectorSubjectMatchKey<Node>: Bool] = [:]
    private var selectorLeftmostMatchCache: [OXQSelectorSubjectMatchKey<Node>: [Node]] = [:]
    private var descendantsCache: [Node: [Node]] = [:]
    private var ancestorsCache: [Node: Set<Node>] = [:]

    private mutating func evaluateSelector(_ selector: OXQSelector) -> [Node] {
        let selectorParts = self.selectorParts(for: selector)
        guard let terminalCompound = selectorParts.compounds.last else { return [] }

        let candidates = self.candidates(matching: terminalCompound)
        if selectorParts.compounds.count == 1 {
            return candidates
        }

        return candidates.filter { self.selectorMatchesSubject(selector: selector, subject: $0) }
    }

    private func selectorParts(for selector: OXQSelector) -> (compounds: [OXQCompound], combinators: [OXQCombinator]) {
        var compounds = [selector.leading]
        var combinators: [OXQCombinator] = []
        for link in selector.links {
            combinators.append(link.combinator)
            compounds.append(link.compound)
        }
        return (compounds, combinators)
    }

    // Compound evaluation order:
    // 1) Base role
    // 2) Attribute filters
    // 3) :not
    // 4) :has
    private mutating func candidates(matching compound: OXQCompound) -> [Node] {
        let baseRoleCandidates: [Node] = switch compound.typeSelector {
        case let .role(roleName):
            self.indexedTree.roleIndex[roleName] ?? []
        case .wildcard, .none:
            self.indexedTree.nodesInTraversalOrder
        }

        let attributesFiltered = baseRoleCandidates.filter { self.matchesAttributes($0, attributes: compound.attributes) }
        let notFiltered = attributesFiltered.filter { self.matchesNotPseudos($0, pseudos: compound.pseudos) }
        let hasFiltered = notFiltered.filter { self.matchesHasPseudos($0, pseudos: compound.pseudos) }
        return hasFiltered
    }

    private mutating func matchesCompound(_ node: Node, compound: OXQCompound) -> Bool {
        let key = OXQCompoundMatchKey(node: node, compound: compound)
        if let cached = self.compoundMatchCache[key] {
            return cached
        }

        let result = self.matchesTypeSelector(node, typeSelector: compound.typeSelector) &&
            self.matchesAttributes(node, attributes: compound.attributes) &&
            self.matchesNotPseudos(node, pseudos: compound.pseudos) &&
            self.matchesHasPseudos(node, pseudos: compound.pseudos)

        self.compoundMatchCache[key] = result
        return result
    }

    private func matchesTypeSelector(_ node: Node, typeSelector: OXQTypeSelector?) -> Bool {
        switch typeSelector {
        case .none, .wildcard:
            true
        case let .role(expectedRole):
            self.indexedTree.roleByNode[node] ?? self.roleProvider(node) == expectedRole
        }
    }

    private func matchesAttributes(_ node: Node, attributes: [OXQAttributeMatch]) -> Bool {
        for attribute in attributes {
            if !self.matchesAttribute(node, attribute: attribute) {
                return false
            }
        }
        return true
    }

    private func matchesAttribute(_ node: Node, attribute: OXQAttributeMatch) -> Bool {
        let canonicalName = self.canonicalAttributeName(attribute.name)
        let actualValue = self.attributeValueProvider(node, canonicalName)
        guard let actualValue else { return false }

        switch attribute.op {
        case .equals:
            return actualValue == attribute.value
        case .contains:
            return actualValue.range(of: attribute.value, options: [.caseInsensitive]) != nil
        case .startsWith:
            return actualValue.hasPrefix(attribute.value)
        case .endsWith:
            return actualValue.hasSuffix(attribute.value)
        }
    }

    private mutating func matchesNotPseudos(_ node: Node, pseudos: [OXQPseudoClass]) -> Bool {
        for pseudo in pseudos {
            guard case let .not(selectors) = pseudo else { continue }
            if selectors.contains(where: { self.selectorMatchesSubject(selector: $0, subject: node) }) {
                return false
            }
        }
        return true
    }

    private mutating func matchesHasPseudos(_ node: Node, pseudos: [OXQPseudoClass]) -> Bool {
        for pseudo in pseudos {
            guard case let .has(argument) = pseudo else { continue }
            if !self.matchesHasArgument(node, argument: argument) {
                return false
            }
        }
        return true
    }

    private mutating func matchesHasArgument(_ node: Node, argument: OXQHasArgument) -> Bool {
        let relativeSelectors: [OXQRelativeSelector] = switch argument {
        case let .selectors(selectors):
            selectors.map { OXQRelativeSelector(leadingCombinator: nil, selector: $0) }
        case let .relativeSelectors(relativeSelectors):
            relativeSelectors
        }

        for relative in relativeSelectors where self.matchesRelativeSelector(node, relativeSelector: relative) {
            return true
        }
        return false
    }

    private mutating func matchesRelativeSelector(_ node: Node, relativeSelector: OXQRelativeSelector) -> Bool {
        let relation = relativeSelector.leadingCombinator ?? .descendant
        let candidateNodes = self.descendants(of: node)
        for candidate in candidateNodes {
            let leftmostMatchNodes = self.selectorLeftmostMatchNodes(
                selector: relativeSelector.selector,
                subject: candidate)
            guard !leftmostMatchNodes.isEmpty else {
                continue
            }
            for leftmostMatchNode in leftmostMatchNodes {
                if self.isRelativeMatchAnchored(
                    anchor: node,
                    relation: relation,
                    leftmostMatchNode: leftmostMatchNode)
                {
                    return true
                }
            }
        }
        return false
    }

    private mutating func descendants(of node: Node) -> [Node] {
        if let cached = self.descendantsCache[node] {
            return cached
        }

        var descendants: [Node] = []
        var stack: [Node] = (self.indexedTree.childrenByNode[node] ?? []).reversed()

        while let current = stack.popLast() {
            descendants.append(current)
            let children = self.indexedTree.childrenByNode[current] ?? []
            for child in children.reversed() {
                stack.append(child)
            }
        }

        self.descendantsCache[node] = descendants
        return descendants
    }

    private mutating func selectorMatchesSubject(selector: OXQSelector, subject: Node) -> Bool {
        let key = OXQSelectorSubjectMatchKey(node: subject, selector: selector)
        if let cached = self.selectorSubjectMatchCache[key] {
            return cached
        }

        let didMatch = !self.selectorLeftmostMatchNodes(selector: selector, subject: subject).isEmpty
        self.selectorSubjectMatchCache[key] = didMatch
        return didMatch
    }

    private mutating func selectorLeftmostMatchNodes(selector: OXQSelector, subject: Node) -> [Node] {
        let key = OXQSelectorSubjectMatchKey(node: subject, selector: selector)
        if let cached = self.selectorLeftmostMatchCache[key] {
            return cached
        }

        let selectorParts = self.selectorParts(for: selector)
        guard let rightmostCompound = selectorParts.compounds.last else {
            self.selectorLeftmostMatchCache[key] = []
            return []
        }
        guard self.matchesCompound(subject, compound: rightmostCompound) else {
            self.selectorLeftmostMatchCache[key] = []
            return []
        }

        var currentCandidates: Set<Node> = [subject]

        if selectorParts.compounds.count > 1 {
            for index in stride(from: selectorParts.compounds.count - 2, through: 0, by: -1) {
                let requiredCompound = selectorParts.compounds[index]
                let combinator = selectorParts.combinators[index]
                var nextCandidates = Set<Node>()

                for currentNode in currentCandidates {
                    switch combinator {
                    case .child:
                        for parent in self.parents(of: currentNode)
                            where self.matchesCompound(parent, compound: requiredCompound)
                        {
                            nextCandidates.insert(parent)
                        }

                    case .descendant:
                        for ancestor in self.ancestors(of: currentNode)
                            where self.matchesCompound(ancestor, compound: requiredCompound)
                        {
                            nextCandidates.insert(ancestor)
                        }
                    }
                }

                if nextCandidates.isEmpty {
                    self.selectorLeftmostMatchCache[key] = []
                    return []
                }
                currentCandidates = nextCandidates
            }
        }

        let leftmostMatches = self.indexedTree.nodesInTraversalOrder.filter { currentCandidates.contains($0) }
        self.selectorLeftmostMatchCache[key] = leftmostMatches
        return leftmostMatches
    }

    private func parents(of node: Node) -> Set<Node> {
        self.indexedTree.parentsByNode[node] ?? []
    }

    private mutating func ancestors(of node: Node) -> Set<Node> {
        if let cached = self.ancestorsCache[node] {
            return cached
        }

        var seen = Set<Node>()
        var stack = Array(self.parents(of: node))

        while let candidate = stack.popLast() {
            guard seen.insert(candidate).inserted else {
                continue
            }
            for parent in self.parents(of: candidate) {
                stack.append(parent)
            }
        }

        self.ancestorsCache[node] = seen
        return seen
    }

    private mutating func isRelativeMatchAnchored(anchor: Node, relation: OXQCombinator, leftmostMatchNode: Node) -> Bool {
        switch relation {
        case .child:
            return self.parents(of: leftmostMatchNode).contains(anchor)
        case .descendant:
            return self.ancestors(of: leftmostMatchNode).contains(anchor)
        }
    }

    private func canonicalAttributeName(_ name: String) -> String {
        if let mapped = PathUtils.attributeKeyMappings[name.lowercased()] {
            return mapped
        }
        return name
    }
}

private struct OXQCompoundMatchKey<Node: Hashable>: Hashable {
    let node: Node
    let compound: OXQCompound
}

private struct OXQSelectorSubjectMatchKey<Node: Hashable>: Hashable {
    let node: Node
    let selector: OXQSelector
}

private extension OXQSyntaxTree {
    var requiresRoleLookups: Bool {
        self.selectors.contains { $0.requiresRoleLookups }
    }
}

private extension OXQSelector {
    var requiresRoleLookups: Bool {
        if self.leading.requiresRoleLookups {
            return true
        }

        return self.links.contains { $0.compound.requiresRoleLookups }
    }
}

private extension OXQCompound {
    var requiresRoleLookups: Bool {
        if case .role = self.typeSelector {
            return true
        }

        return self.pseudos.contains { pseudo in
            switch pseudo {
            case let .not(selectors):
                return selectors.contains { $0.requiresRoleLookups }
            case let .has(argument):
                return argument.requiresRoleLookups
            }
        }
    }
}

private extension OXQHasArgument {
    var requiresRoleLookups: Bool {
        switch self {
        case let .selectors(selectors):
            return selectors.contains { $0.requiresRoleLookups }
        case let .relativeSelectors(relativeSelectors):
            return relativeSelectors.contains { $0.selector.requiresRoleLookups }
        }
    }
}
