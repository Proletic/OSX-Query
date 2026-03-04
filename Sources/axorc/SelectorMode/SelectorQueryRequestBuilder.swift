import Foundation

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
        cacheSession: Bool = false,
        useCached: Bool = false,
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
            showNameSource: showNameSource,
            cacheSessionEnabled: cacheSession || useCached,
            useCachedSnapshot: useCached)
    }
}
