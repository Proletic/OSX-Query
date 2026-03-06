// OSQMain.swift - Main entry point for OSQ CLI

import AppKit
import OSXQuery
@preconcurrency import Commander
import Foundation

@main
struct OSQCommand: ParsableCommand {
    static func main() async {
        let code = await OSQCLIEntrypoint.run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(code)
    }

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        let version = MainActor.assumeIsolated { osqVersion }
        return CommandDescription(
            commandName: "osq",
            abstract: "OSQ CLI - OXQ selector query mode. Version \(version)",
            usageExamples: [
                CommandUsageExample(
                    command: "osq --app com.apple.TextEdit --selector \"AXTextArea\"",
                    description: "Query an app with the OXQ selector language."),
                CommandUsageExample(
                    command: "osq --app com.apple.TextEdit --selector -i",
                    description: "Open the interactive full-screen query TUI."),
                CommandUsageExample(
                    command: "osq --enable-ax com.apple.TextEdit",
                    description: "Temporarily focus an app and apply AX exposure attributes."),
                CommandUsageExample(
                    command: "osq --actions 'send click to 28e6a93cf;'",
                    description: "Execute OXA actions against refs from the cache daemon (query+ then action*)."),
            ])
    }

    // `--debug` now enables *normal* diagnostic output. Use the new `--verbose` flag for the extremely chatty logs.
    @Flag(name: .long, help: "Enable debug logging (normal detail level). Use --verbose for maximum detail.")
    var debug: Bool = false

    @Flag(name: .long, help: "Enable *verbose* debug logging – every internal step. Produces large output.")
    var verbose: Bool = false

    @Option(name: .long, help: "Target app for selector mode (bundle id, app name, PID, or 'focused').")
    var app: String?

    @Option(name: .long, help: "OXQ selector query for selector mode.")
    var selector: String?

    @Option(name: .long, help: "Run OXA action program against selector cache daemon refs.")
    var actions: String?

    @Flag(
        names: [.customShort("i", allowingJoined: false), .customLong("interactive")],
        help: "Open interactive selector mode (full-screen query and result navigation).")
    var interactive: Bool = false

    @Option(name: .customLong("max-depth"), help: "Selector mode max traversal depth (default unlimited).")
    var selectorMaxDepth: Int?

    @Option(name: .long, help: "Selector mode max result rows to print (default 50, 0 = no cap).")
    var limit: Int?

    @Flag(name: .customLong("no-color"), help: "Disable ANSI color output in selector mode.")
    var noColor: Bool = false

    @Flag(name: .customLong("show-path"), help: "Include full generated path per selector match.")
    var showPath: Bool = false

    @Flag(name: .customLong("show-name-source"), help: "Include computed name source (e.g. AXTitle) per selector match.")
    var showNameSource: Bool = false

    @Flag(name: .customLong("tree"), help: "Render selector matches as a tree using inferred ancestors where needed.")
    var tree: Bool = false

    @Flag(name: .customLong("tree-full"), help: "Render selector matches as a full tree including inferred unmatched ancestors.")
    var treeFull: Bool = false

    @Flag(
        name: .customLong("cache-session"),
        help: "Use a background daemon to reuse the last prefetched tree across selector CLI calls.")
    var cacheSession: Bool = false

    @Flag(
        name: .customLong("use-cached"),
        help: "Use the warm cached tree from the last --cache-session query (no refresh).")
    var useCached: Bool = false

    @Option(
        name: .customLong("enable-ax"),
        help: "Enable AXEnhancedUserInterface and AXManualAccessibility for a running bundle id. Temporarily focuses target app and restores original focus.")
    var enableAppAx: String?

    @Flag(name: .customLong("selector-cache-daemon"), help: "Internal: run selector cache daemon.")
    var selectorCacheDaemon: Bool = false

    @Option(name: .customLong("selector-cache-daemon-socket"), help: "Internal: selector cache daemon socket path.")
    var selectorCacheDaemonSocket: String?

    mutating func run() async throws {
        try await MainActor.run {
            try self.runMain()
        }
    }

    @MainActor
    private mutating func runMain() throws {
        self.configureLogging()
        self.logDebugVersion()

        if self.selectorCacheDaemon {
            let socketPath = self.selectorCacheDaemonSocket ?? SelectorCacheDaemonClient.defaultSocketPath()
            try SelectorCacheDaemonServer.run(socketPath: socketPath)
            return
        }

        if let actionProgram = try self.buildActionProgramIfNeeded() {
            try self.runActionMode(request: actionProgram)
            return
        }

        if let exposureRequest = try self.buildAXExposureRequestIfNeeded() {
            try self.runAXExposureMode(request: exposureRequest)
            return
        }

        if let interactiveRequest = try self.buildInteractiveSelectorRequestIfNeeded() {
            try self.runInteractiveSelectorMode(request: interactiveRequest)
            return
        }

        if let selectorRequest = try self.buildSelectorRequestIfNeeded() {
            try self.runSelectorMode(request: selectorRequest)
            return
        }

        throw ValidationError(
            "No CLI mode selected. Use --app with --selector (or -i) for querying, or --enable-ax for AX exposure.")
    }

    private func configureLogging() {
        if self.verbose {
            GlobalAXLogger.shared.isLoggingEnabled = true
            GlobalAXLogger.shared.detailLevel = .verbose
        } else if self.debug {
            GlobalAXLogger.shared.isLoggingEnabled = true
            GlobalAXLogger.shared.detailLevel = .normal
        } else {
            GlobalAXLogger.shared.isLoggingEnabled = false
            GlobalAXLogger.shared.detailLevel = .minimal
        }
    }

    private func logDebugVersion() {
        guard self.debug || self.verbose else { return }
        let version = MainActor.assumeIsolated { osqVersion }
        fputs(
            logSegments(
                "OSQMain.run: osq version \(version) build \(osqBuildStamp)",
                "Detail level: \(GlobalAXLogger.shared.detailLevel).") + "\n",
            stderr)
    }

    private func hasAnySelectorInput() -> Bool {
        let hasApp = !(self.app?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasSelector = !(self.selector?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasApp || hasSelector || self.selectorMaxDepth != nil || self.limit != nil || self.noColor ||
            self.showPath || self.showNameSource || self.tree || self.treeFull || self.interactive || self.cacheSession || self.useCached
    }

    private mutating func buildAXExposureRequestIfNeeded() throws -> AXExposureRequest? {
        do {
            return try AXExposureRequestBuilder.build(
                bundleIdentifier: self.enableAppAx,
                hasStructuredInput: false,
                hasSelectorInput: self.hasAnySelectorInput())
        } catch let exposureError as AXExposureCLIError {
            throw ValidationError(exposureError.localizedDescription)
        }
    }

    private mutating func runAXExposureMode(request: AXExposureRequest) throws {
        do {
            let runner = AXExposureRunner()
            let report = try runner.execute(request)
            print(AXExposureOutputFormatter.format(report: report))
            fflush(stdout)
            axClearLogs()
        } catch let exposureError as AXExposureCLIError {
            throw ValidationError(exposureError.localizedDescription)
        }
    }

    private struct ActionProgramRequest {
        let program: String
    }

    private mutating func buildActionProgramIfNeeded() throws -> ActionProgramRequest? {
        guard let actionProgram = self.actions?.trimmingCharacters(in: .whitespacesAndNewlines), !actionProgram.isEmpty else {
            return nil
        }

        if self.enableAppAx != nil {
            throw ValidationError("Action mode (--actions) cannot be combined with --enable-ax.")
        }

        if self.hasAnySelectorInput() {
            throw ValidationError("Action mode (--actions) cannot be combined with selector flags. Use query+ then action* as separate calls.")
        }

        return ActionProgramRequest(program: actionProgram)
    }

    private mutating func runActionMode(request: ActionProgramRequest) throws {
        do {
            let output = try SelectorCacheDaemonClient().execute(actionsProgram: request.program)
            print(output)
            fflush(stdout)
            axClearLogs()
        } catch let cacheError as SelectorCacheDaemonError {
            throw ValidationError(cacheError.localizedDescription)
        }
    }

    private mutating func buildInteractiveSelectorRequestIfNeeded() throws -> InteractiveSelectorRequest? {
        let interactiveRequested = self.interactive || self.consumeInteractiveSelectorShortcut()
        do {
            return try InteractiveSelectorRequestBuilder.build(
                app: self.app,
                selector: self.selector,
                maxDepth: self.selectorMaxDepth,
                interactive: interactiveRequested,
                hasStructuredInput: false)
        } catch let interactiveError as InteractiveSelectorCLIError {
            throw ValidationError(interactiveError.localizedDescription)
        }
    }

    private mutating func runInteractiveSelectorMode(request: InteractiveSelectorRequest) throws {
        do {
            try InteractiveSelectorRunner.run(request: request)
            axClearLogs()
        } catch let interactiveError as InteractiveSelectorCLIError {
            throw ValidationError(interactiveError.localizedDescription)
        }
    }

    private mutating func consumeInteractiveSelectorShortcut() -> Bool {
        guard let selectorValue = self.selector?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        guard selectorValue == "-i" || selectorValue == "--interactive" else {
            return false
        }
        self.selector = nil
        return true
    }

    private mutating func buildSelectorRequestIfNeeded() throws -> SelectorQueryRequest? {
        do {
            return try SelectorQueryRequestBuilder.build(
                app: self.app,
                selector: self.selector,
                maxDepth: self.selectorMaxDepth,
                limit: self.limit,
                noColor: self.noColor,
                showPath: self.showPath,
                showNameSource: self.showNameSource,
                tree: self.tree,
                treeFull: self.treeFull,
                cacheSession: self.cacheSession,
                useCached: self.useCached,
                hasStructuredInput: false,
                stdoutSupportsANSI: OutputCapabilities.stdoutSupportsANSI)
        } catch let selectorError as SelectorQueryCLIError {
            throw ValidationError(selectorError.localizedDescription)
        }
    }

    private mutating func runSelectorMode(request: SelectorQueryRequest) throws {
        do {
            if request.cacheSessionEnabled {
                let output = try SelectorCacheDaemonClient().execute(request: request)
                print(output)
            } else {
                let runner = SelectorQueryRunner()
                let report = try runner.execute(request)
                print(SelectorQueryOutputFormatter.format(report: report))
            }
            fflush(stdout)
            axClearLogs()
        } catch let parseError as OXQParseError {
            throw ValidationError("Invalid selector query: \(parseError.description)")
        } catch let selectorError as SelectorQueryCLIError {
            throw ValidationError(selectorError.localizedDescription)
        } catch let cacheError as SelectorCacheDaemonError {
            throw ValidationError(cacheError.localizedDescription)
        }
    }

}

// MARK: - Commander Parsing

extension OSQCommand {
    static func parseCommandLineArguments(arguments: [String]) throws -> ParsedValues {
        let prototype = Self()
        let signature = CommandSignature.describe(prototype)
        let parser = CommandParser(signature: signature)
        let normalizedArguments = Self.normalizeArguments(arguments)
        return try parser.parse(arguments: normalizedArguments)
    }

    private static func normalizeArguments(_ arguments: [String]) -> [String] {
        guard !arguments.isEmpty else { return arguments }

        var normalized: [String] = []
        normalized.reserveCapacity(arguments.count)

        var index = 0
        while index < arguments.count {
            if arguments[index] == "--selector",
               index + 1 < arguments.count,
               arguments[index + 1] == "-i"
            {
                // Allow shorthand flow: --selector -i
                index += 1
                continue
            }

            normalized.append(arguments[index])
            index += 1
        }

        return normalized
    }

    mutating func apply(parsedValues: ParsedValues) throws {
        self.debug = parsedValues.flags.contains("debug")
        self.verbose = parsedValues.flags.contains("verbose")
        self.noColor = parsedValues.flags.contains("noColor")
        self.showPath = parsedValues.flags.contains("showPath")
        self.showNameSource = parsedValues.flags.contains("showNameSource")
        self.tree = parsedValues.flags.contains("tree")
        self.treeFull = parsedValues.flags.contains("treeFull")
        self.cacheSession = parsedValues.flags.contains("cacheSession")
        self.useCached = parsedValues.flags.contains("useCached")
        self.interactive = parsedValues.flags.contains("interactive")
        self.selectorCacheDaemon = parsedValues.flags.contains("selectorCacheDaemon")

        if let maxDepthString = parsedValues.options["selectorMaxDepth"]?.last {
            guard let depthValue = Int(maxDepthString) else {
                throw ValidationError("Invalid value for --max-depth: \(maxDepthString)")
            }
            self.selectorMaxDepth = depthValue
        }

        if let limitString = parsedValues.options["limit"]?.last {
            guard let limitValue = Int(limitString) else {
                throw ValidationError("Invalid value for --limit: \(limitString)")
            }
            self.limit = limitValue
        }

        if let appValue = parsedValues.options["app"]?.last {
            self.app = appValue
        }

        if let selectorValue = parsedValues.options["selector"]?.last {
            self.selector = selectorValue
        }

        if let actionsValue = parsedValues.options["actions"]?.last {
            self.actions = actionsValue
        }

        if let enableAppAxValue = parsedValues.options["enableAppAx"]?.last {
            self.enableAppAx = enableAppAxValue
        }

        if let selectorCacheDaemonSocket = parsedValues.options["selectorCacheDaemonSocket"]?.last {
            self.selectorCacheDaemonSocket = selectorCacheDaemonSocket
        }
    }

}
