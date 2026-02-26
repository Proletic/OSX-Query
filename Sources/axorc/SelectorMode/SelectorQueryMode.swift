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
    case missingInteraction
    case missingResultIndex
    case invalidResultIndex(Int)
    case unknownInteraction(String)
    case interactionValueRequired
    case interactionValueNotAllowed(String)
    case submitFlagRequiresSetValue
    case interactionTargetOutOfBounds(index: Int, matchedCount: Int)
    case interactionFailed(action: String, index: Int)

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
        case .missingInteraction:
            "Selector interaction requires --interaction."
        case .missingResultIndex:
            "Selector interaction requires --result-index."
        case let .invalidResultIndex(index):
            "--result-index must be greater than 0. Received: \(index)."
        case let .unknownInteraction(raw):
            "Unknown --interaction '\(raw)'. Supported values: click, press, focus, set-value."
        case .interactionValueRequired:
            "--interaction-value is required when --interaction is set to set-value."
        case let .interactionValueNotAllowed(action):
            "--interaction-value is only valid with --interaction set-value (received: \(action))."
        case .submitFlagRequiresSetValue:
            "--submit-after-set-value is only valid with --interaction set-value."
        case let .interactionTargetOutOfBounds(index, matchedCount):
            "--result-index \(index) is out of bounds for \(matchedCount) matched elements."
        case let .interactionFailed(action, index):
            "Interaction '\(action)' failed for result index \(index)."
        }
    }
}

enum SelectorInteractionAction: Equatable {
    case click
    case press
    case focus
    case setValue(String)
    case setValueAndSubmit(String)

    var rawName: String {
        switch self {
        case .click:
            return "click"
        case .press:
            return "press"
        case .focus:
            return "focus"
        case .setValue:
            return "set-value"
        case .setValueAndSubmit:
            return "set-value-submit"
        }
    }
}

struct SelectorInteractionRequest: Equatable {
    let resultIndex: Int
    let action: SelectorInteractionAction
}

struct SelectorInteractionSummary: Equatable {
    let resultIndex: Int
    let action: String
    let role: String
    let computedName: String?
}

struct SelectorQueryRequest: Equatable {
    let appIdentifier: String
    let selector: String
    let maxDepth: Int
    let limit: Int
    let colorEnabled: Bool
    let showPath: Bool
    let showNameSource: Bool
    let interaction: SelectorInteractionRequest?

    init(
        appIdentifier: String,
        selector: String,
        maxDepth: Int,
        limit: Int,
        colorEnabled: Bool,
        showPath: Bool,
        showNameSource: Bool = false,
        interaction: SelectorInteractionRequest? = nil)
    {
        self.appIdentifier = appIdentifier
        self.selector = selector
        self.maxDepth = maxDepth
        self.limit = limit
        self.colorEnabled = colorEnabled
        self.showPath = showPath
        self.showNameSource = showNameSource
        self.interaction = interaction
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
        interaction: String? = nil,
        interactionValue: String? = nil,
        submitAfterSetValue: Bool = false,
        resultIndex: Int? = nil,
        hasStructuredInput: Bool,
        stdoutSupportsANSI: Bool) throws -> SelectorQueryRequest?
    {
        let trimmedApp = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInteraction = interaction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnyInteractionInput = !(trimmedInteraction?.isEmpty ?? true) || interactionValue != nil || resultIndex != nil ||
            submitAfterSetValue

        let hasApp = !(trimmedApp?.isEmpty ?? true)
        let hasSelector = !(trimmedSelector?.isEmpty ?? true)

        if !hasApp, !hasSelector, !hasAnyInteractionInput {
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

        if let resultIndex, resultIndex <= 0 {
            throw SelectorQueryCLIError.invalidResultIndex(resultIndex)
        }

        let interactionRequest: SelectorInteractionRequest?
        if hasAnyInteractionInput {
            guard let trimmedInteraction, !trimmedInteraction.isEmpty else {
                throw SelectorQueryCLIError.missingInteraction
            }
            guard let resultIndex else {
                throw SelectorQueryCLIError.missingResultIndex
            }

            switch trimmedInteraction.lowercased() {
            case "click":
                if interactionValue != nil {
                    throw SelectorQueryCLIError.interactionValueNotAllowed("click")
                }
                if submitAfterSetValue {
                    throw SelectorQueryCLIError.submitFlagRequiresSetValue
                }
                interactionRequest = SelectorInteractionRequest(resultIndex: resultIndex, action: .click)

            case "press":
                if interactionValue != nil {
                    throw SelectorQueryCLIError.interactionValueNotAllowed("press")
                }
                if submitAfterSetValue {
                    throw SelectorQueryCLIError.submitFlagRequiresSetValue
                }
                interactionRequest = SelectorInteractionRequest(resultIndex: resultIndex, action: .press)

            case "focus":
                if interactionValue != nil {
                    throw SelectorQueryCLIError.interactionValueNotAllowed("focus")
                }
                if submitAfterSetValue {
                    throw SelectorQueryCLIError.submitFlagRequiresSetValue
                }
                interactionRequest = SelectorInteractionRequest(resultIndex: resultIndex, action: .focus)

            case "set-value":
                guard let interactionValue else {
                    throw SelectorQueryCLIError.interactionValueRequired
                }
                interactionRequest = SelectorInteractionRequest(
                    resultIndex: resultIndex,
                    action: submitAfterSetValue ? .setValueAndSubmit(interactionValue) : .setValue(interactionValue))

            default:
                throw SelectorQueryCLIError.unknownInteraction(trimmedInteraction)
            }
        } else {
            interactionRequest = nil
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
            showNameSource: showNameSource,
            interaction: interactionRequest)
    }
}

struct SelectorQueryExecutionReport: Equatable {
    let request: SelectorQueryRequest
    let elapsedMilliseconds: Double
    let traversedCount: Int
    let matchedCount: Int
    let shownCount: Int
    let interaction: SelectorInteractionSummary?
    let results: [SelectorMatchSummary]

    init(
        request: SelectorQueryRequest,
        elapsedMilliseconds: Double,
        traversedCount: Int,
        matchedCount: Int,
        shownCount: Int,
        interaction: SelectorInteractionSummary? = nil,
        results: [SelectorMatchSummary])
    {
        self.request = request
        self.elapsedMilliseconds = elapsedMilliseconds
        self.traversedCount = traversedCount
        self.matchedCount = matchedCount
        self.shownCount = shownCount
        self.interaction = interaction
        self.results = results
    }
}

struct SelectorQueryResult: Equatable {
    let traversedCount: Int
    let matchedCount: Int
    let interaction: SelectorInteractionSummary?
    let shown: [SelectorMatchSummary]

    init(
        traversedCount: Int,
        matchedCount: Int,
        interaction: SelectorInteractionSummary? = nil,
        shown: [SelectorMatchSummary])
    {
        self.traversedCount = traversedCount
        self.matchedCount = matchedCount
        self.interaction = interaction
        self.shown = shown
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
        path: String?)
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
        self.value = SelectorMatchSummary.normalize(SelectorMatchSummary.stringify(element.value()))
        self.identifier = SelectorMatchSummary.normalize(element.identifier())
        self.descriptionText = SelectorMatchSummary.normalize(element.descriptionText())
        self.path = includePath ? SelectorMatchSummary.normalize(element.generatePathString()) : nil
    }

    private static func normalize(_ value: String?) -> String? {
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
            interaction: result.interaction,
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
        let interactionSummary = try self.performInteractionIfRequested(
            request.interaction,
            matchedElements: matchedElements)

        let shownElements = matchedElements.prefix(request.limit)
        let shownSummaries = shownElements.map { element in
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
                isEnabled: isEnabled,
                isFocused: isFocused,
                childCount: childCount)
        }

        return SelectorQueryResult(
            traversedCount: evaluation.traversedNodeCount,
            matchedCount: matchedElements.count,
            interaction: interactionSummary,
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

    @MainActor
    private static func performInteractionIfRequested(
        _ interaction: SelectorInteractionRequest?,
        matchedElements: [Element]) throws -> SelectorInteractionSummary?
    {
        guard let interaction else { return nil }
        guard interaction.resultIndex <= matchedElements.count else {
            throw SelectorQueryCLIError.interactionTargetOutOfBounds(
                index: interaction.resultIndex,
                matchedCount: matchedElements.count)
        }

        let targetElement = matchedElements[interaction.resultIndex - 1]

        let succeeded: Bool
        switch interaction.action {
        case .click:
            succeeded = ((try? targetElement.click()) != nil)
        case .press:
            succeeded = targetElement.press()
        case .focus:
            succeeded = self.focusElement(targetElement)
        case let .setValue(value):
            succeeded = targetElement.setValue(value, forAttribute: AXAttributeNames.kAXValueAttribute)
        case let .setValueAndSubmit(value):
            guard ((try? targetElement.click()) != nil) else {
                succeeded = false
                break
            }

            guard targetElement.setValue(value, forAttribute: AXAttributeNames.kAXValueAttribute) else {
                succeeded = false
                break
            }

            do {
                try Element.typeKey(.return)
                succeeded = true
            } catch {
                succeeded = false
            }
        }

        guard succeeded else {
            throw SelectorQueryCLIError.interactionFailed(
                action: interaction.action.rawName,
                index: interaction.resultIndex)
        }

        return SelectorInteractionSummary(
            resultIndex: interaction.resultIndex,
            action: interaction.action.rawName,
            role: targetElement.role() ?? "AXUnknown",
            computedName: SelectorMatchSummary.stringify(targetElement.computedName()))
    }

    @MainActor
    private static func focusElement(_ element: Element) -> Bool {
        if element.setValue(true, forAttribute: AXAttributeNames.kAXFocusedAttribute) {
            return true
        }
        if element.press() {
            return true
        }
        return ((try? element.click()) != nil)
    }
}

enum OutputCapabilities {
    static var stdoutSupportsANSI: Bool {
        guard isatty(STDOUT_FILENO) == 1 else { return false }
        let term = ProcessInfo.processInfo.environment["TERM"]?.lowercased()
        return term != "dumb"
    }
}
