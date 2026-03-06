import Foundation

@MainActor
public final class OXQQueryMemoizationContext<Node: Hashable> {
    public struct ComputedNameDetails: Equatable, Sendable {
        public let value: String
        public let source: String

        public init(value: String, source: String) {
            self.value = value
            self.source = source
        }
    }

    // MARK: Lifecycle

    public init(
        childrenProvider: @escaping (Node) -> [Node],
        roleProvider: @escaping (Node) -> String?,
        attributeValueProvider: @escaping (Node, String) -> String?,
        preferDerivedComputedName: Bool = false)
    {
        self.childrenProvider = childrenProvider
        self.roleProvider = roleProvider
        self.attributeValueProvider = attributeValueProvider
        self.preferDerivedComputedName = preferDerivedComputedName
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
        if attributeName == AXMiscConstants.computedNameAttributeKey {
            if !self.preferDerivedComputedName,
               let directComputedName = self.nonEmptyValue(
                   self.attributeValueDirect(of: node, attributeName: AXMiscConstants.computedNameAttributeKey))
            {
                return directComputedName
            }
            return self.computedNameDetails(of: node)?.value
        }
        return self.attributeValueDirect(of: node, attributeName: attributeName)
    }

    public func computedNameDetails(of node: Node) -> ComputedNameDetails? {
        if let cached = self.computedNameDetailsCache[node] {
            return cached.value
        }

        let details = self.computeComputedNameDetails(of: node)
        self.computedNameDetailsCache[node] = .init(details)
        return details
    }

    private func attributeValueDirect(of node: Node, attributeName: String) -> String? {
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
    private let preferDerivedComputedName: Bool

    private var childrenCache: [Node: [Node]] = [:]
    private var roleCache: [Node: OptionalCacheEntry<String>] = [:]
    private var computedNameDetailsCache: [Node: OptionalCacheEntry<ComputedNameDetails>] = [:]
    private var attributeValueCache: [NodeAttributeKey<Node>: OptionalCacheEntry<String>] = [:]

    private func computeComputedNameDetails(of node: Node) -> ComputedNameDetails? {
        let cachedRole = self.roleCache[node]?.value
        let preferValueFirst = cachedRole.map(self.isTextLikeRole) ?? false

        if preferValueFirst {
            if let valueCandidate = self.valueCandidate(of: node) {
                return valueCandidate
            }
        }

        if let title = self.nonEmptyValue(self.attributeValueDirect(of: node, attributeName: AXAttributeNames.kAXTitleAttribute)) {
            return ComputedNameDetails(value: title, source: AXAttributeNames.kAXTitleAttribute)
        }

        if !preferValueFirst, let valueCandidate = self.valueCandidate(of: node) {
            return valueCandidate
        }

        if let identifier = self.nonEmptyValue(self.attributeValueDirect(of: node, attributeName: AXAttributeNames.kAXIdentifierAttribute)) {
            return ComputedNameDetails(value: identifier, source: AXAttributeNames.kAXIdentifierAttribute)
        }

        if let description = self.nonEmptyValue(self.attributeValueDirect(
            of: node,
            attributeName: AXAttributeNames.kAXDescriptionAttribute))
        {
            return ComputedNameDetails(value: description, source: AXAttributeNames.kAXDescriptionAttribute)
        }

        if let help = self.nonEmptyValue(self.attributeValueDirect(of: node, attributeName: AXAttributeNames.kAXHelpAttribute)) {
            return ComputedNameDetails(value: help, source: AXAttributeNames.kAXHelpAttribute)
        }

        if let placeholder = self.nonEmptyValue(self.attributeValueDirect(
            of: node,
            attributeName: AXAttributeNames.kAXPlaceholderValueAttribute))
        {
            return ComputedNameDetails(value: placeholder, source: AXAttributeNames.kAXPlaceholderValueAttribute)
        }

        if let selectedText = self.nonEmptyValue(self.attributeValueDirect(
            of: node,
            attributeName: AXAttributeNames.kAXSelectedTextAttribute))
        {
            return ComputedNameDetails(value: selectedText, source: AXAttributeNames.kAXSelectedTextAttribute)
        }

        if let role = self.nonEmptyValue(self.role(of: node)) {
            let roleLabel = role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
            return ComputedNameDetails(value: roleLabel, source: AXAttributeNames.kAXRoleAttribute)
        }

        return nil
    }

    private func valueCandidate(of node: Node) -> ComputedNameDetails? {
        if let value = self.nonEmptyValue(self.attributeValueDirect(of: node, attributeName: AXAttributeNames.kAXValueAttribute)) {
            return ComputedNameDetails(value: String(value.prefix(200)), source: AXAttributeNames.kAXValueAttribute)
        }

        return nil
    }

    private func nonEmptyValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let lowered = value.lowercased()
        if lowered == "nil" || lowered == "null" || lowered == "(null)" || lowered == "<null>" || lowered == "optional(nil)" {
            return nil
        }

        return value
    }

    private func isTextLikeRole(_ role: String) -> Bool {
        switch role {
        case AXRoleNames.kAXStaticTextRole,
            AXRoleNames.kAXTextFieldRole,
            AXRoleNames.kAXTextAreaRole,
            AXRoleNames.kAXComboBoxRole:
            return true
        default:
            return false
        }
    }
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
