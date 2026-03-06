import OSXQuery
import Foundation

enum SelectorQueryCLIError: LocalizedError, Equatable {
    case missingApplication
    case missingSelector
    case conflictingInputModes
    case invalidMaxDepth(Int)
    case invalidLimit(Int)
    case applicationNotFound(String)
    case cachedSnapshotUnavailable(String)
    case referenceCollision(String)

    var errorDescription: String? {
        switch self {
        case .missingApplication:
            "Selector mode requires --app."
        case .missingSelector:
            "Selector mode requires --selector."
        case .conflictingInputModes:
            "Selector mode (--app/--selector) cannot be combined with JSON input flags or payloads."
        case let .invalidMaxDepth(value):
            "--max-depth must be greater than 0. Received: \(value)."
        case let .invalidLimit(value):
            "--limit must be 0 or greater. Use 0 for no cap. Received: \(value)."
        case let .applicationNotFound(identifier):
            "Could not find a running app for '\(identifier)'. Use a bundle id (e.g. com.apple.TextEdit), running app name, PID, or 'focused'."
        case let .cachedSnapshotUnavailable(message):
            message
        case let .referenceCollision(reference):
            "Selector query produced a duplicate element reference '\(reference)'. Re-run query."
        }
    }
}

struct SelectorQueryRequest: Equatable {
    let appIdentifier: String
    let selector: String
    let maxDepth: Int
    let limit: Int
    let colorEnabled: Bool
    let showPath: Bool
    let showNameSource: Bool
    let treeMode: SelectorTreeMode
    let cacheSessionEnabled: Bool
    let useCachedSnapshot: Bool

    init(
        appIdentifier: String,
        selector: String,
        maxDepth: Int,
        limit: Int,
        colorEnabled: Bool,
        showPath: Bool,
        showNameSource: Bool = false,
        treeMode: SelectorTreeMode = .none,
        cacheSessionEnabled: Bool = false,
        useCachedSnapshot: Bool = false)
    {
        self.appIdentifier = appIdentifier
        self.selector = selector
        self.maxDepth = maxDepth
        self.limit = limit
        self.colorEnabled = colorEnabled
        self.showPath = showPath
        self.showNameSource = showNameSource
        self.treeMode = treeMode
        self.cacheSessionEnabled = cacheSessionEnabled
        self.useCachedSnapshot = useCachedSnapshot
    }
}

enum SelectorTreeMode: String, Equatable, Codable {
    case none
    case compact
    case full
}

struct SelectorQueryExecutionReport: Equatable {
    let request: SelectorQueryRequest
    let elapsedMilliseconds: Double
    let traversedCount: Int
    let matchedCount: Int
    let shownCount: Int
    let results: [SelectorMatchSummary]

    init(
        request: SelectorQueryRequest,
        elapsedMilliseconds: Double,
        traversedCount: Int,
        matchedCount: Int,
        shownCount: Int,
        results: [SelectorMatchSummary])
    {
        self.request = request
        self.elapsedMilliseconds = elapsedMilliseconds
        self.traversedCount = traversedCount
        self.matchedCount = matchedCount
        self.shownCount = shownCount
        self.results = results
    }
}

struct SelectorQueryResult: Equatable {
    let traversedCount: Int
    let matchedCount: Int
    let shown: [SelectorMatchSummary]

    init(
        traversedCount: Int,
        matchedCount: Int,
        shown: [SelectorMatchSummary])
    {
        self.traversedCount = traversedCount
        self.matchedCount = matchedCount
        self.shown = shown
    }
}

struct SelectorTreeNodeSummary: Equatable {
    let reference: String
    let role: String
    let computedName: String?
    let title: String?
    let value: String?
    let identifier: String?

    var displayLabel: String {
        var parts: [String] = [self.role]
        if let name = SelectorMatchSummary.normalize(self.computedName) {
            parts.append("name=\"\(name)\"")
        } else if let title = SelectorMatchSummary.normalize(self.title) {
            parts.append("title=\"\(title)\"")
        } else if let value = SelectorMatchSummary.normalize(self.value) {
            parts.append("value=\"\(value)\"")
        }
        if let identifier = SelectorMatchSummary.normalize(self.identifier) {
            parts.append("id=\"\(identifier)\"")
        }
        return parts.joined(separator: " ")
    }
}

struct SelectorMatchSummary: Equatable {
    let role: String
    let computedName: String?
    let computedNameSource: String?
    let isEnabled: Bool?
    let isFocused: Bool?
    let childCount: Int?
    let title: String?
    let value: String?
    let identifier: String?
    let descriptionText: String?
    let path: String?
    let reference: String?
    let ancestry: [SelectorTreeNodeSummary]

    var resultDisplayName: String? {
        if self.role == AXRoleNames.kAXStaticTextRole, let value = self.value {
            return value
        }
        return self.computedName
    }

    var resultDisplayNameSource: String? {
        if self.role == AXRoleNames.kAXStaticTextRole, let value = self.value {
            if value != self.computedName {
                return AXAttributeNames.kAXValueAttribute
            }
        }
        return self.computedNameSource
    }

    var resultDisplayValue: String? {
        guard let value = self.value else { return nil }
        guard value != self.resultDisplayName else { return nil }
        return value
    }

    init(
        role: String,
        computedName: String?,
        computedNameSource: String? = nil,
        isEnabled: Bool? = nil,
        isFocused: Bool? = nil,
        childCount: Int? = nil,
        title: String?,
        value: String?,
        identifier: String?,
        descriptionText: String?,
        path: String?,
        reference: String? = nil,
        ancestry: [SelectorTreeNodeSummary] = [])
    {
        self.role = role
        self.computedName = computedName
        self.computedNameSource = computedNameSource
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.childCount = childCount
        self.title = title
        self.value = value
        self.identifier = identifier
        self.descriptionText = descriptionText
        self.path = path
        self.reference = reference
        self.ancestry = ancestry
    }

    @MainActor
    init(
        element: Element,
        includePath: Bool,
        isEnabled: Bool?,
        isFocused: Bool?,
        childCount: Int?)
    {
        let computedNameDetails = element.computedNameDetails()
        self.role = element.role() ?? "AXUnknown"
        self.computedName = SelectorMatchSummary.normalize(computedNameDetails?.value)
        self.computedNameSource = SelectorMatchSummary.normalize(computedNameDetails?.source)
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.childCount = childCount
        self.title = SelectorMatchSummary.normalize(element.title())
        self.value = SelectorMatchSummary.normalize(SelectorMatchSummary.preferredValueString(for: element))
        self.identifier = SelectorMatchSummary.normalize(element.identifier())
        self.descriptionText = SelectorMatchSummary.normalize(element.descriptionText())
        self.path = includePath ? SelectorMatchSummary.normalize(element.generatePathString()) : nil
        self.reference = nil
        self.ancestry = []
    }

    static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if self.isNullLikeString(trimmed) {
            return nil
        }
        return trimmed
    }

    static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        guard let unwrappedValue = self.unwrapOptional(value) else { return nil }

        if unwrappedValue is NSNull {
            return nil
        }
        if let string = unwrappedValue as? String {
            if self.isNullLikeString(string) {
                return nil
            }
            return string
        }
        if let attributed = unwrappedValue as? NSAttributedString {
            return attributed.string
        }
        if let number = unwrappedValue as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let bool = unwrappedValue as? Bool {
            return bool ? "true" : "false"
        }
        if let strings = unwrappedValue as? [String] {
            return strings.joined(separator: ",")
        }
        if let array = unwrappedValue as? [Any] {
            let parts = array.compactMap { stringify($0) }
            return parts.isEmpty ? nil : parts.joined(separator: ",")
        }

        let described = String(describing: unwrappedValue)
        if self.isNullLikeString(described) {
            return nil
        }
        return described
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }
        guard let wrapped = mirror.children.first?.value else {
            return nil
        }
        return self.unwrapOptional(wrapped)
    }

    private static func isNullLikeString(_ value: String) -> Bool {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token == "nil" ||
            token == "null" ||
            token == "(null)" ||
            token == "<null>" ||
            token == "optional(nil)"
    }

    @MainActor
    private static func preferredValueString(for element: Element) -> String? {
        if let directValue: String = element.attribute(Attribute<String>(AXAttributeNames.kAXValueAttribute)) {
            return directValue
        }

        if let normalizedValue = self.stringify(element.value()) {
            return normalizedValue
        }

        if let selectedText = element.selectedText() {
            return selectedText
        }

        return nil
    }
}
