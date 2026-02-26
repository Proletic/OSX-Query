import Foundation

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
        maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch) throws -> [Node]
    {
        let syntaxTree = try self.parser.parse(query)
        return self.findAll(
            matching: syntaxTree,
            from: root,
            maxDepth: maxDepth)
    }

    public func findFirst(
        matching query: String,
        from root: Node,
        maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch) throws -> Node?
    {
        try self.findAll(matching: query, from: root, maxDepth: maxDepth).first
    }

    public func findAll(
        matching syntaxTree: OXQSyntaxTree,
        from root: Node,
        maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch) -> [Node]
    {
        let safeMaxDepth = max(0, maxDepth)
        let indexedTree = OXQIndexedTree(
            root: root,
            maxDepth: safeMaxDepth,
            childrenProvider: self.childrenProvider,
            roleProvider: self.roleProvider)
        var evaluator = OXQEvaluator(
            syntaxTree: syntaxTree,
            indexedTree: indexedTree,
            roleProvider: self.roleProvider,
            attributeValueProvider: self.attributeValueProvider)
        return evaluator.evaluateAll()
    }

    public func findFirst(
        matching syntaxTree: OXQSyntaxTree,
        from root: Node,
        maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch) -> Node?
    {
        self.findAll(matching: syntaxTree, from: root, maxDepth: maxDepth).first
    }

    // MARK: Private

    private let parser: OXQParser
    private let childrenProvider: (Node) -> [Node]
    private let roleProvider: (Node) -> String?
    private let attributeValueProvider: (Node, String) -> String?
}

private struct OXQIndexedTree<Node: Hashable> {
    // MARK: Lifecycle

    init(
        root: Node,
        maxDepth: Int,
        childrenProvider: (Node) -> [Node],
        roleProvider: (Node) -> String?)
    {
        self.root = root
        var nodesInTraversalOrder: [Node] = []
        var parentByNode: [Node: Node] = [:]
        var childrenByNode: [Node: [Node]] = [:]
        var roleByNode: [Node: String] = [:]
        var roleIndex: [String: [Node]] = [:]
        var visited = Set<Node>()

        var stack: [(node: Node, depth: Int)] = [(node: root, depth: 0)]

        while let entry = stack.popLast() {
            let node = entry.node
            let depth = entry.depth
            if visited.contains(node) {
                continue
            }
            visited.insert(node)

            nodesInTraversalOrder.append(node)
            let role = roleProvider(node)
            if let role {
                roleByNode[node] = role
                roleIndex[role, default: []].append(node)
            }

            let children = depth < maxDepth ? childrenProvider(node) : []
            childrenByNode[node] = children
            for child in children where parentByNode[child] == nil {
                parentByNode[child] = node
            }

            for child in children.reversed() {
                stack.append((node: child, depth: depth + 1))
            }
        }

        self.nodesInTraversalOrder = nodesInTraversalOrder
        self.parentByNode = parentByNode
        self.childrenByNode = childrenByNode
        self.roleByNode = roleByNode
        self.roleIndex = roleIndex
    }

    // MARK: Internal

    let root: Node
    let nodesInTraversalOrder: [Node]
    let parentByNode: [Node: Node]
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
    private var descendantsCache: [Node: [Node]] = [:]

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
            return actualValue.contains(attribute.value)
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
        let candidateNodes: [Node] = switch relation {
        case .child:
            self.indexedTree.childrenByNode[node] ?? []
        case .descendant:
            self.descendants(of: node)
        }

        for candidate in candidateNodes where self.selectorMatchesSubject(selector: relativeSelector.selector, subject: candidate) {
            return true
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

        let selectorParts = self.selectorParts(for: selector)
        guard let rightmostCompound = selectorParts.compounds.last else { return false }
        guard self.matchesCompound(subject, compound: rightmostCompound) else {
            self.selectorSubjectMatchCache[key] = false
            return false
        }

        var currentNode = subject
        var didMatch = true

        if selectorParts.compounds.count > 1 {
            for index in stride(from: selectorParts.compounds.count - 2, through: 0, by: -1) {
                let requiredCompound = selectorParts.compounds[index]
                let combinator = selectorParts.combinators[index]

                switch combinator {
                case .child:
                    guard
                        let parent = self.indexedTree.parentByNode[currentNode],
                        self.matchesCompound(parent, compound: requiredCompound)
                    else {
                        didMatch = false
                        break
                    }
                    currentNode = parent

                case .descendant:
                    var ancestor = self.indexedTree.parentByNode[currentNode]
                    var matchedAncestor: Node?

                    while let ancestorNode = ancestor {
                        if self.matchesCompound(ancestorNode, compound: requiredCompound) {
                            matchedAncestor = ancestorNode
                            break
                        }
                        ancestor = self.indexedTree.parentByNode[ancestorNode]
                    }

                    guard let matchedAncestor else {
                        didMatch = false
                        break
                    }
                    currentNode = matchedAncestor
                }

                if !didMatch {
                    break
                }
            }
        }

        self.selectorSubjectMatchCache[key] = didMatch
        return didMatch
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
