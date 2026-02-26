import AppKit
import AXorcist
import Darwin
import Foundation

enum SelectorQueryCLIError: LocalizedError, Equatable {
    case missingApplication
    case missingSelector
    case conflictingInputModes
    case invalidMaxDepth(Int)
    case invalidLimit(Int)
    case applicationNotFound(String)

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

    init(
        appIdentifier: String,
        selector: String,
        maxDepth: Int,
        limit: Int,
        colorEnabled: Bool,
        showPath: Bool,
        showNameSource: Bool = false)
    {
        self.appIdentifier = appIdentifier
        self.selector = selector
        self.maxDepth = maxDepth
        self.limit = limit
        self.colorEnabled = colorEnabled
        self.showPath = showPath
        self.showNameSource = showNameSource
    }
}

enum SelectorQueryRequestBuilder {
    private static let unlimitedMaxDepth = Int.max
    private static let defaultLimit = 50
    private static let unlimitedLimit = Int.max

    static func build(
        app: String?,
        selector: String?,
        maxDepth: Int?,
        limit: Int?,
        noColor: Bool,
        showPath: Bool,
        showNameSource: Bool = false,
        hasStructuredInput: Bool,
        stdoutSupportsANSI: Bool) throws -> SelectorQueryRequest?
    {
        let trimmedApp = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasApp = !(trimmedApp?.isEmpty ?? true)
        let hasSelector = !(trimmedSelector?.isEmpty ?? true)

        if !hasApp, !hasSelector {
            return nil
        }

        if hasStructuredInput {
            throw SelectorQueryCLIError.conflictingInputModes
        }

        guard hasApp else { throw SelectorQueryCLIError.missingApplication }
        guard hasSelector else { throw SelectorQueryCLIError.missingSelector }

        if let maxDepth, maxDepth <= 0 {
            throw SelectorQueryCLIError.invalidMaxDepth(maxDepth)
        }

        if let limit, limit < 0 {
            throw SelectorQueryCLIError.invalidLimit(limit)
        }

        let resolvedLimit: Int
        if let limit {
            resolvedLimit = (limit == 0) ? unlimitedLimit : limit
        } else {
            resolvedLimit = defaultLimit
        }

        return SelectorQueryRequest(
            appIdentifier: trimmedApp!,
            selector: trimmedSelector!,
            maxDepth: maxDepth ?? unlimitedMaxDepth,
            limit: resolvedLimit,
            colorEnabled: stdoutSupportsANSI && !noColor,
            showPath: showPath,
            showNameSource: showNameSource)
    }
}

struct SelectorQueryExecutionReport: Equatable {
    let request: SelectorQueryRequest
    let elapsedMilliseconds: Double
    let traversedCount: Int
    let matchedCount: Int
    let shownCount: Int
    let results: [SelectorMatchSummary]
}

struct SelectorQueryResult: Equatable {
    let traversedCount: Int
    let matchedCount: Int
    let shown: [SelectorMatchSummary]
}

struct SelectorMatchSummary: Equatable {
    let role: String
    let computedName: String?
    let computedNameSource: String?
    let roleDescription: String?
    let isEnabled: Bool?
    let isFocused: Bool?
    let childCount: Int?
    let title: String?
    let value: String?
    let identifier: String?
    let descriptionText: String?
    let path: String?

    init(
        role: String,
        computedName: String?,
        computedNameSource: String? = nil,
        roleDescription: String? = nil,
        isEnabled: Bool? = nil,
        isFocused: Bool? = nil,
        childCount: Int? = nil,
        title: String?,
        value: String?,
        identifier: String?,
        descriptionText: String?,
        path: String?)
    {
        self.role = role
        self.computedName = computedName
        self.computedNameSource = computedNameSource
        self.roleDescription = roleDescription
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.childCount = childCount
        self.title = title
        self.value = value
        self.identifier = identifier
        self.descriptionText = descriptionText
        self.path = path
    }

    @MainActor
    init(
        element: Element,
        includePath: Bool,
        roleDescription: String?,
        isEnabled: Bool?,
        isFocused: Bool?,
        childCount: Int?)
    {
        let computedNameDetails = element.computedNameDetails()
        self.role = element.role() ?? "AXUnknown"
        self.computedName = SelectorMatchSummary.normalize(computedNameDetails?.value)
        self.computedNameSource = SelectorMatchSummary.normalize(computedNameDetails?.source)
        self.roleDescription = SelectorMatchSummary.normalize(roleDescription)
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.childCount = childCount
        self.title = SelectorMatchSummary.normalize(element.title())
        self.value = SelectorMatchSummary.normalize(SelectorMatchSummary.stringify(element.value()))
        self.identifier = SelectorMatchSummary.normalize(element.identifier())
        self.descriptionText = SelectorMatchSummary.normalize(element.descriptionText())
        self.path = includePath ? SelectorMatchSummary.normalize(element.generatePathString()) : nil
    }

    private static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }

        if value is NSNull {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let strings = value as? [String] {
            return strings.joined(separator: ",")
        }
        if let array = value as? [Any] {
            return array.map { stringify($0) ?? String(describing: $0) }.joined(separator: ",")
        }

        return String(describing: value)
    }
}

@MainActor
struct SelectorQueryRunner {
    typealias QueryExecutor = @MainActor (SelectorQueryRequest) throws -> SelectorQueryResult
    typealias NanosecondClock = @MainActor () -> UInt64

    init(
        queryExecutor: @escaping QueryExecutor = LiveSelectorQueryExecutor.execute,
        nowNanoseconds: @escaping NanosecondClock = defaultNowNanoseconds)
    {
        self.queryExecutor = queryExecutor
        self.nowNanoseconds = nowNanoseconds
    }

    func execute(_ request: SelectorQueryRequest) throws -> SelectorQueryExecutionReport {
        let startedAt = self.nowNanoseconds()
        let result = try self.queryExecutor(request)
        let endedAt = self.nowNanoseconds()

        let elapsedMilliseconds = Double(endedAt &- startedAt) / 1_000_000

        return SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: elapsedMilliseconds,
            traversedCount: result.traversedCount,
            matchedCount: result.matchedCount,
            shownCount: result.shown.count,
            results: result.shown)
    }

    private let queryExecutor: QueryExecutor
    private let nowNanoseconds: NanosecondClock

    private static func defaultNowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

@MainActor
private enum LiveSelectorQueryExecutor {
    static func execute(_ request: SelectorQueryRequest) throws -> SelectorQueryResult
    {
        guard let root = self.resolveRootElement(appIdentifier: request.appIdentifier) else {
            throw SelectorQueryCLIError.applicationNotFound(request.appIdentifier)
        }

        let childrenProvider: (Element) -> [Element] = { element in
            element.children(strict: false, includeApplicationExtras: element == root) ?? []
        }
        let roleProvider: (Element) -> String? = { element in
            element.role()
        }
        let attributeValueProvider: (Element, String) -> String? = { element, attributeName in
            self.stringValue(for: element, attributeName: attributeName)
        }

        let selectorEngine = OXQSelectorEngine<Element>(
            children: childrenProvider,
            role: roleProvider,
            attributeValue: attributeValueProvider)

        let memoizationContext = OXQQueryMemoizationContext<Element>(
            childrenProvider: childrenProvider,
            roleProvider: roleProvider,
            attributeValueProvider: attributeValueProvider)

        let evaluation = try selectorEngine.findAllWithMetrics(
            matching: request.selector,
            from: root,
            maxDepth: request.maxDepth,
            memoizationContext: memoizationContext)
        let matchedElements = evaluation.matches

        let shownElements = matchedElements.prefix(request.limit)
        let shownSummaries = shownElements.map { element in
            let roleDescription = memoizationContext.attributeValue(
                of: element,
                attributeName: AXAttributeNames.kAXRoleDescriptionAttribute)
            let isEnabled = self.parseBool(memoizationContext.attributeValue(
                of: element,
                attributeName: AXAttributeNames.kAXEnabledAttribute))
            let isFocused = self.parseBool(memoizationContext.attributeValue(
                of: element,
                attributeName: AXAttributeNames.kAXFocusedAttribute))
            let childCount = memoizationContext.children(of: element).count

            return SelectorMatchSummary(
                element: element,
                includePath: request.showPath,
                roleDescription: roleDescription,
                isEnabled: isEnabled,
                isFocused: isFocused,
                childCount: childCount)
        }

        return SelectorQueryResult(
            traversedCount: evaluation.traversedNodeCount,
            matchedCount: matchedElements.count,
            shown: shownSummaries)
    }

    private static func resolveRootElement(appIdentifier: String) -> Element? {
        let normalizedIdentifier = appIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedIdentifier.caseInsensitiveCompare("focused") == .orderedSame,
           let frontmost = RunningApplicationHelper.frontmostApplication
        {
            return getApplicationElement(for: frontmost.processIdentifier)
        }

        if let pid = pid_t(normalizedIdentifier) {
            return getApplicationElement(for: pid)
        }

        if let directBundleMatch = getApplicationElement(for: normalizedIdentifier) {
            return directBundleMatch
        }

        guard let app = self.findRunningApplication(matching: normalizedIdentifier) else {
            return nil
        }

        return getApplicationElement(for: app.processIdentifier)
    }

    private static func findRunningApplication(matching identifier: String) -> NSRunningApplication? {
        let normalized = identifier.lowercased()

        return RunningApplicationHelper.allApplications().first { app in
            let bundleMatch = app.bundleIdentifier?.lowercased() == normalized
            let nameMatch = app.localizedName?.lowercased() == normalized
            return bundleMatch || nameMatch
        }
    }

    private static func stringValue(for element: Element, attributeName: String) -> String? {
        let canonicalName = PathUtils.attributeKeyMappings[attributeName.lowercased()] ?? attributeName

        switch canonicalName {
        case AXAttributeNames.kAXRoleAttribute:
            return element.role()
        case AXAttributeNames.kAXSubroleAttribute:
            return element.subrole()
        case AXAttributeNames.kAXPIDAttribute:
            return element.pid().map(String.init)
        case AXAttributeNames.kAXTitleAttribute:
            return element.title()
        case AXAttributeNames.kAXDescriptionAttribute:
            return element.descriptionText()
        case AXAttributeNames.kAXHelpAttribute:
            return element.help()
        case AXAttributeNames.kAXIdentifierAttribute:
            return element.identifier()
        case AXAttributeNames.kAXRoleDescriptionAttribute:
            return element.roleDescription()
        case AXAttributeNames.kAXPlaceholderValueAttribute:
            return element.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute))
        case AXAttributeNames.kAXEnabledAttribute:
            return element.isEnabled().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXFocusedAttribute:
            return element.isFocused().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXValueAttribute:
            return SelectorMatchSummary.stringify(element.value())
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
        return SelectorMatchSummary.stringify(rawValue)
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}

enum OutputCapabilities {
    static var stdoutSupportsANSI: Bool {
        guard isatty(STDOUT_FILENO) == 1 else { return false }
        let term = ProcessInfo.processInfo.environment["TERM"]?.lowercased()
        return term != "dumb"
    }
}
