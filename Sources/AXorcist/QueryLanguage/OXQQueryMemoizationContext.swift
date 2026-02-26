import Foundation

@MainActor
public final class OXQQueryMemoizationContext<Node: Hashable> {
    // MARK: Lifecycle

    public init(
        childrenProvider: @escaping (Node) -> [Node],
        roleProvider: @escaping (Node) -> String?,
        attributeValueProvider: @escaping (Node, String) -> String?)
    {
        self.childrenProvider = childrenProvider
        self.roleProvider = roleProvider
        self.attributeValueProvider = attributeValueProvider
    }

    // MARK: Public

    public func children(of node: Node) -> [Node] {
        if let cached = self.childrenCache[node] {
            return cached
        }
        let children = self.childrenProvider(node)
        self.childrenCache[node] = children
        return children
    }

    public func role(of node: Node) -> String? {
        if let cached = self.roleCache[node] {
            return cached.value
        }
        let role = self.roleProvider(node)
        self.roleCache[node] = .init(role)
        return role
    }

    public func attributeValue(of node: Node, attributeName: String) -> String? {
        let key = NodeAttributeKey(node: node, attributeName: attributeName)
        if let cached = self.attributeValueCache[key] {
            return cached.value
        }
        let value = self.attributeValueProvider(node, attributeName)
        self.attributeValueCache[key] = .init(value)
        return value
    }

    // MARK: Private

    private let childrenProvider: (Node) -> [Node]
    private let roleProvider: (Node) -> String?
    private let attributeValueProvider: (Node, String) -> String?

    private var childrenCache: [Node: [Node]] = [:]
    private var roleCache: [Node: OptionalCacheEntry<String>] = [:]
    private var attributeValueCache: [NodeAttributeKey<Node>: OptionalCacheEntry<String>] = [:]
}

private struct OptionalCacheEntry<Value> {
    fileprivate init(_ value: Value?) {
        self.value = value
    }

    fileprivate let value: Value?
}

private struct NodeAttributeKey<Node: Hashable>: Hashable {
    let node: Node
    let attributeName: String
}
