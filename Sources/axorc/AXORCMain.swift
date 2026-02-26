// AXORCMain.swift - Main entry point for AXORC CLI

import AppKit
import AXorcist
@preconcurrency import Commander
import CoreFoundation
import Foundation

@main
struct AXORCCommand: ParsableCommand {
    static func main() async {
        do {
            let parsedValues = try Self.parseCommandLineArguments()
            var command = AXORCCommand()
            try command.apply(parsedValues: parsedValues)
            try await command.run()
        } catch let error as CommanderError {
            Self.emitArgumentError(message: error.description)
            Foundation.exit(ExitCode.failure.rawValue)
        } catch let validation as ValidationError {
            Self.emitArgumentError(message: validation.description)
            Foundation.exit(ExitCode.failure.rawValue)
        } catch let exitCode as ExitCode {
            Foundation.exit(exitCode.rawValue)
        } catch {
            fputs("axorc error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        let version = MainActor.assumeIsolated { axorcVersion }
        return CommandDescription(
            commandName: "axorc",
            // Use axorcVersion from AXORCModels.swift or a shared constant place
            abstract: "AXORC CLI - JSON command mode and OXQ selector query mode. Version \(version)")
    }

    // `--debug` now enables *normal* diagnostic output. Use the new `--verbose` flag for the extremely chatty logs.
    @Flag(name: .long, help: "Enable debug logging (normal detail level). Use --verbose for maximum detail.")
    var debug: Bool = false

    @Flag(name: .long, help: "Enable *verbose* debug logging – every internal step. Produces large output.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Read JSON payload from STDIN.")
    var stdin: Bool = false

    @Option(name: .long, help: "Read JSON payload from the specified file path.")
    var file: String?

    @Option(name: .long, help: "Read JSON payload directly from this string argument, expecting a JSON string.")
    var json: String?

    @Option(name: .long, help: "Target app for selector mode (bundle id, app name, PID, or 'focused').")
    var app: String?

    @Option(name: .long, help: "OXQ selector query for selector mode.")
    var selector: String?

    @Flag(
        names: [.customShort("i", allowingJoined: false), .customLong("interactive")],
        help: "Open interactive selector mode (full-screen query and result navigation).")
    var interactive: Bool = false

    @Flag(
        names: [.customShort("r", allowingJoined: false), .customLong("refocus-terminal")],
        help: "With -i, refocus the terminal app after click/focus/set-value-submit interactions.")
    var refocusTerminal: Bool = false

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

    @Option(name: .customLong("result-index"), help: "1-based matched selector result index to target for interaction.")
    var selectorResultIndex: Int?

    @Option(name: .long, help: "Interaction for targeted selector result (click, press, focus, set-value).")
    var interaction: String?

    @Option(name: .customLong("interaction-value"), help: "Value used for --interaction set-value.")
    var interactionValue: String?

    @Flag(
        name: .customLong("submit-after-set-value"),
        help: "With --interaction set-value, click the target first, set value, then press Return.")
    var submitAfterSetValue: Bool = false

    @Option(
        name: .customLong("enable-ax"),
        help: "Enable AXEnhancedUserInterface and AXManualAccessibility for a running bundle id. Temporarily focuses target app and restores original focus.")
    var enableAppAx: String?

    @Option(name: .long, help: "Traversal timeout in seconds (overrides default 30).")
    var timeout: Int?

    @Flag(name: .long, help: "Traverse every node (ignore container role pruning). May be extremely slow.")
    var scanAll: Bool = false

    @Flag(name: .customLong("no-stop-first"), help: "Do not stop at first match; collect deeper matches as well.")
    var noStopFirst: Bool = false

    @Argument(
        help: logSegments(
            "Read JSON payload directly from this string argument.",
            "Ignored when other input flags (--stdin, --file, --json) are provided."))
    var directPayload: String?

    @MainActor
    private var suppressFinalLogDump = false

    // Helper function to process and execute a CommandEnvelope
    @MainActor private func processAndExecuteCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) {
        if debugCLI {
            axDebugLog("Successfully parsed command: \(command.command) (ID: \(command.commandId))")
        }

        let resultJsonString = CommandExecutor.execute(
            command: command,
            axorcist: axorcist,
            debugCLI: debugCLI)
        print(resultJsonString)
        fflush(stdout)

        if command.command == .observe {
            self.handleObserveCommand(resultJsonString: resultJsonString, debugCLI: self.debug)
        } else {
            axClearLogs()
        }
    }

    @MainActor
    private func handleObserveCommand(resultJsonString: String, debugCLI: Bool) {
        let observerSetupSucceeded = self.parseObserveSetup(resultJsonString)
        if observerSetupSucceeded {
            axInfoLog(
                logSegments(
                    "AXORCMain: Observer setup successful",
                    "Process will remain alive by running current RunLoop"))
            #if DEBUG
            axInfoLog("AXORCMain: DEBUG mode - entering RunLoop.current.run() for observer.")
            RunLoop.current.run()
            axInfoLog("AXORCMain: DEBUG mode - RunLoop.current.run() finished.")
            #else
            let errorPayload = [
                "{\"error\": \"The 'observe' command is intended for DEBUG builds or specific use cases.",
                " In release, it sets up the observer but will not keep the process alive indefinitely by itself.",
                " Exiting normally after setup.\"}\n",
            ].joined()
            fputs(errorPayload, stderr)
            fflush(stderr)
            #endif
        } else {
            axErrorLog(
                logSegments(
                    "AXORCMain: Observe command setup reported failure or result was not a success status",
                    "Exiting"))
        }
    }

    private func parseObserveSetup(_ jsonString: String) -> Bool {
        guard let resultData = jsonString.data(using: .utf8) else {
            axErrorLog("AXORCMain: Could not convert result JSON string to data for observe setup check.")
            return false
        }

        do {
            if
                let jsonOutput = try JSONSerialization.jsonObject(with: resultData, options: []) as?
                [String: Any],
                let success = jsonOutput["success"] as? Bool,
                let status = jsonOutput["status"] as? String
            {
                axInfoLog(
                    logSegments(
                        "AXORCMain: Parsed initial response for observe",
                        "success=\(success)",
                        "status=\(status)"))
                if success, status == "observer_started" {
                    axInfoLog("AXORCMain: Observer setup deemed SUCCEEDED for observe command.")
                    return true
                }
                axInfoLog(
                    logSegments(
                        "AXORCMain: Observer setup deemed FAILED for observe command",
                        "success=\(success)",
                        "status=\(status)"))
                return false
            }
            axErrorLog(
                logSegments(
                    "AXORCMain: Failed to parse expected fields (success, status)",
                    "from observe setup JSON"))
            return false
        } catch {
            axErrorLog(
                logSegments(
                    "AXORCMain: Could not parse result JSON from observe setup to check for success",
                    error.localizedDescription))
            return false
        }
    }

    mutating func run() async throws {
        try await MainActor.run {
            try self.runMain()
        }
    }

    @MainActor
    private mutating func runMain() throws {
        self.configureLogging()
        self.applyGlobalFlags()
        self.logDebugVersion()

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

        let inputResult = InputHandler.parseInput(
            stdin: self.stdin,
            file: self.file,
            json: self.json,
            directPayload: self.directPayload)
        axorcInputSource = inputResult.sourceDescription

        let axorcistInstance = AXorcist.shared

        if self.handleInputError(inputResult) {
            return
        }

        guard let jsonStringFromInput = inputResult.jsonString else {
            self.handleMissingInput()
            return
        }

        self.logDebug(
            logSegments(
                "AXORCMain Test: Received jsonStringFromInput",
                "[\(jsonStringFromInput)]",
                "length: \(jsonStringFromInput.count)"))

        try self.decodeAndExecute(
            jsonString: jsonStringFromInput,
            axorcist: axorcistInstance)

        if self.debug, self.commandShouldPrintLogsAtEnd() {
            self.flushDebugLogs()
        }
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

    private func applyGlobalFlags() {
        axorcScanAll = self.scanAll
        axorcStopAtFirstMatch = !self.noStopFirst
        if let timeout {
            axorcTraversalTimeout = TimeInterval(timeout)
        }
    }

    private func logDebugVersion() {
        guard self.debug || self.verbose else { return }
        let version = MainActor.assumeIsolated { axorcVersion }
        fputs(
            logSegments(
                "AXORCMain.run: AXorc version \(version) build \(axorcBuildStamp)",
                "Detail level: \(GlobalAXLogger.shared.detailLevel).") + "\n",
            stderr)
    }

    private func handleInputError(_ inputResult: InputHandler.Result) -> Bool {
        guard let error = inputResult.error else { return false }
        self.respondWithError(
            commandId: "input_error",
            error: error,
            logs: self.debug ? axGetLogsAsStrings(format: .text) : nil)
        return true
    }

    private func handleMissingInput() {
        self.respondWithError(
            commandId: "no_input",
            error: "No valid JSON input received",
            logs: self.debug ? axGetLogsAsStrings(format: .text) : nil)
    }

    private func respondWithError(commandId: String, error: String, logs: [String]?) {
        Self.printErrorResponse(commandId: commandId, error: error, logs: logs)
    }

    private func hasAnyStructuredInput() -> Bool {
        let hasPositionalPayload = !(self.directPayload?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return self.stdin || self.file != nil || self.json != nil || hasPositionalPayload
    }

    private func hasAnySelectorInput() -> Bool {
        let hasApp = !(self.app?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasSelector = !(self.selector?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasApp || hasSelector || self.selectorMaxDepth != nil || self.limit != nil || self.noColor ||
            self.showPath || self.showNameSource || self.selectorResultIndex != nil || self.interaction != nil ||
            self.interactionValue != nil || self.submitAfterSetValue || self.interactive || self.refocusTerminal
    }

    private mutating func buildAXExposureRequestIfNeeded() throws -> AXExposureRequest? {
        do {
            return try AXExposureRequestBuilder.build(
                bundleIdentifier: self.enableAppAx,
                hasStructuredInput: self.hasAnyStructuredInput(),
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

    private mutating func buildInteractiveSelectorRequestIfNeeded() throws -> InteractiveSelectorRequest? {
        let interactiveRequested = self.interactive || self.consumeInteractiveSelectorShortcut()
        do {
            return try InteractiveSelectorRequestBuilder.build(
                app: self.app,
                selector: self.selector,
                maxDepth: self.selectorMaxDepth,
                interactive: interactiveRequested,
                refocusTerminalAfterInteractions: self.refocusTerminal,
                hasStructuredInput: self.hasAnyStructuredInput())
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
                interaction: self.interaction,
                interactionValue: self.interactionValue,
                submitAfterSetValue: self.submitAfterSetValue,
                resultIndex: self.selectorResultIndex,
                hasStructuredInput: self.hasAnyStructuredInput(),
                stdoutSupportsANSI: OutputCapabilities.stdoutSupportsANSI)
        } catch let selectorError as SelectorQueryCLIError {
            throw ValidationError(selectorError.localizedDescription)
        }
    }

    private mutating func runSelectorMode(request: SelectorQueryRequest) throws {
        do {
            let runner = SelectorQueryRunner()
            let report = try runner.execute(request)
            print(SelectorQueryOutputFormatter.format(report: report))
            fflush(stdout)
            axClearLogs()
        } catch let parseError as OXQParseError {
            throw ValidationError("Invalid selector query: \(parseError.description)")
        } catch let selectorError as SelectorQueryCLIError {
            throw ValidationError(selectorError.localizedDescription)
        }
    }

    private mutating func decodeAndExecute(jsonString: String, axorcist: AXorcist) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = jsonString.data(using: .utf8) else {
            axDebugLog("AXORCMain Test: Failed to convert jsonStringFromInput to data.")
            self.respondWithError(
                commandId: "data_conversion_error",
                error: "Failed to convert JSON string to data",
                logs: self.debug ? axGetLogsAsStrings() : nil)
            return
        }

        do {
            let commands = try decoder.decode([CommandEnvelope].self, from: data)
            self.suppressFinalLogDump = commands.contains { $0.command == .observe }
            if let command = commands.first {
                self.processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: self.debug)
                return
            }
            self.logDebug("AXORCMain Test: Decode attempt 1: Decoded [CommandEnvelope] but array was empty.")
            throw NSError(
                domain: "AXORCErrorDomain",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Decoded empty command array from [CommandEnvelope] attempt."])
        } catch let arrayDecodeError {
            logDebug(
                logSegments(
                    "AXORCMain Test: Decode attempt 1 (as [CommandEnvelope]) FAILED",
                    "Error: \(arrayDecodeError)",
                    "Will try as single CommandEnvelope"))
            do {
                let command = try decoder.decode(CommandEnvelope.self, from: data)
                suppressFinalLogDump = command.command == .observe
                processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: debug)
            } catch let singleDecodeError {
                logDebug(
                    logSegments(
                        "AXORCMain Test: Decode attempt 2 (as single CommandEnvelope) ALSO FAILED",
                        "Error: \(singleDecodeError)",
                        "Original array decode error was: \(arrayDecodeError)"))
                respondWithError(
                    commandId: "decode_error",
                    error: "Failed to decode JSON input: \(singleDecodeError.localizedDescription)",
                    logs: debug ? axGetLogsAsStrings() : nil)
            }
        }
    }

    private func flushDebugLogs() {
        let logMessages = axGetLogsAsStrings(format: .text)
        guard !logMessages.isEmpty else { return }
        fputs("\n--- Debug Logs (axorc run end) ---\n", stderr)
        logMessages.forEach { fputs($0 + "\n", stderr) }
        fputs("--- End Debug Logs ---\n", stderr)
        fflush(stderr)
    }

    private func logDebug(_ message: String) {
        axDebugLog(message)
    }

    private func commandShouldPrintLogsAtEnd() -> Bool {
        !self.suppressFinalLogDump
    }
}

// MARK: - Commander Parsing

extension AXORCCommand {
    private static func parseCommandLineArguments() throws -> ParsedValues {
        let prototype = Self()
        let signature = CommandSignature.describe(prototype)
        let parser = CommandParser(signature: signature)
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let normalizedArguments = Self.normalizeArguments(rawArguments)
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

    private mutating func apply(parsedValues: ParsedValues) throws {
        self.debug = parsedValues.flags.contains("debug")
        self.verbose = parsedValues.flags.contains("verbose")
        self.stdin = parsedValues.flags.contains("stdin")
        self.scanAll = parsedValues.flags.contains("scanAll")
        self.noStopFirst = parsedValues.flags.contains("noStopFirst")
        self.noColor = parsedValues.flags.contains("noColor")
        self.showPath = parsedValues.flags.contains("showPath")
        self.showNameSource = parsedValues.flags.contains("showNameSource")
        self.interactive = parsedValues.flags.contains("interactive")
        self.refocusTerminal = parsedValues.flags.contains("refocusTerminal")
        self.submitAfterSetValue = parsedValues.flags.contains("submitAfterSetValue")

        if let fileValue = parsedValues.options["file"]?.last {
            self.file = fileValue
        }

        if let jsonValue = parsedValues.options["json"]?.last {
            self.json = jsonValue
        }

        if let timeoutString = parsedValues.options["timeout"]?.last {
            guard let timeoutValue = Int(timeoutString) else {
                throw ValidationError("Invalid value for --timeout: \(timeoutString)")
            }
            self.timeout = timeoutValue
        }

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

        if let resultIndexString = parsedValues.options["selectorResultIndex"]?.last {
            guard let resultIndexValue = Int(resultIndexString) else {
                throw ValidationError("Invalid value for --result-index: \(resultIndexString)")
            }
            self.selectorResultIndex = resultIndexValue
        }

        if let appValue = parsedValues.options["app"]?.last {
            self.app = appValue
        }

        if let selectorValue = parsedValues.options["selector"]?.last {
            self.selector = selectorValue
        }

        if let interactionValue = parsedValues.options["interaction"]?.last {
            self.interaction = interactionValue
        }

        if let selectorInteractionValue = parsedValues.options["interactionValue"]?.last {
            self.interactionValue = selectorInteractionValue
        }

        if let enableAppAxValue = parsedValues.options["enableAppAx"]?.last {
            self.enableAppAx = enableAppAxValue
        }

        self.directPayload = parsedValues.positional.first
    }

    private static func emitArgumentError(message: String) {
        self.printErrorResponse(commandId: "argument_error", error: message, logs: nil)
    }

    private static func printErrorResponse(commandId: String, error: String, logs: [String]?) {
        let errorResponse = ErrorResponse(commandId: commandId, error: error, debugLogs: logs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let jsonData = try? encoder.encode(errorResponse),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        } else {
            print("{\"error\": \"Failed to encode error response\"}")
        }
    }
}

// ErrorResponse struct is now defined in AXORCModels.swift
// struct ErrorResponse: Codable {
// var commandId: String
// var status: String = "error"
// var error: String
// var debugLogs: [String]?
// }
