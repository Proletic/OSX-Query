import Foundation

@MainActor
struct OXQElementSearch {
    // MARK: Lifecycle

    init(parser: OXQParser = OXQParser()) {
        self.engine = OXQSelectorEngine<Element>(
            parser: parser,
            children: { element in
                element.children(strict: false) ?? []
            },
            role: { element in
                element.role()
            },
            attributeValue: { element, attributeName in
                OXQElementSearch.stringValue(for: element, attributeName: attributeName)
            })
    }

    // MARK: Internal

    func findFirst(
        matching selectorQuery: String,
        from root: Element,
        maxDepth: Int) throws -> Element?
    {
        let memoizationContext = OXQQueryMemoizationContext<Element>(
            childrenProvider: { element in
                element.children(strict: false) ?? []
            },
            roleProvider: { element in
                element.role()
            },
            attributeValueProvider: { element, attributeName in
                OXQElementSearch.stringValue(for: element, attributeName: attributeName)
            })

        return try self.engine.findFirst(
            matching: selectorQuery,
            from: root,
            maxDepth: maxDepth,
            memoizationContext: memoizationContext)
    }

    // MARK: Private

    private let engine: OXQSelectorEngine<Element>

    private static func stringValue(for element: Element, attributeName: String) -> String? {
        let canonicalName = if let mapped = PathUtils.attributeKeyMappings[attributeName.lowercased()] {
            mapped
        } else {
            attributeName
        }

        switch canonicalName {
        case AXAttributeNames.kAXRoleAttribute:
            return element.role()
        case AXAttributeNames.kAXSubroleAttribute:
            return element.subrole()
        case AXAttributeNames.kAXPIDAttribute:
            if let pid = element.pid() {
                return String(pid)
            }
            return nil
        case AXMiscConstants.computedNameAttributeKey:
            return element.computedName()
        case AXMiscConstants.isIgnoredAttributeKey:
            return element.isIgnored() ? "true" : "false"
        default:
            break
        }

        guard let rawValue: Any = element.attribute(Attribute<Any>(canonicalName)) else {
            return nil
        }
        return self.stringify(rawValue)
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            // Keep explicit Bool handling so true/false do not become 1/0.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let strings = value as? [String] {
            return strings.joined(separator: ",")
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let array = value as? [Any] {
            return array.map { self.stringify($0) }.joined(separator: ",")
        }
        return String(describing: value)
    }
}
