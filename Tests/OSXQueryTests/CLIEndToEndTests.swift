import Foundation
import AXFixtureShared
import Testing

@Suite("OSX CLI end-to-end", .tags(.safe))
struct CLIEndToEndTests {
    @Test("Query rejects invalid max depth", .tags(.safe))
    func queryRejectsInvalidMaxDepth() throws {
        let result = try runOSXCommand(arguments: [
            "query",
            "--app", "focused",
            "--max-depth", "nope",
            "AXApplication",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Invalid value for --max-depth: nope") == true)
    }

    @Test("Query rejects invalid limit", .tags(.safe))
    func queryRejectsInvalidLimit() throws {
        let result = try runOSXCommand(arguments: [
            "query",
            "--app", "focused",
            "--limit", "oops",
            "AXApplication",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Invalid value for --limit: oops") == true)
    }

    @Test("Query rejects extra positional arguments", .tags(.safe))
    func queryRejectsExtraArguments() throws {
        let result = try runOSXCommand(arguments: [
            "query",
            "--app", "focused",
            "AXApplication",
            "extra",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Unexpected extra arguments for query.") == true)
    }

    @Test("Cached query surfaces selector parse errors", .tags(.safe))
    func cachedQuerySurfacesSelectorParseError() throws {
        let result = try runOSXCommand(arguments: [
            "query",
            "--cache-session",
            "--app", "focused",
            "[",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Invalid selector query:") == true)
    }

    @Test("Cached query can be reused for action reads", .tags(.safe))
    func cachedQueryCanBeReusedForActionReads() throws {
        let warmResult = try runOSXCommand(arguments: [
            "query",
            "--cache-session",
            "--app", "focused",
            "--max-depth", "1",
            "--limit", "1",
            "--no-color",
            "AXApplication",
        ])

        #expect(warmResult.exitCode == 0)
        let warmedOutput = try #require(warmResult.output)
        let reference = try #require(Self.firstReference(in: warmedOutput))

        let cachedResult = try runOSXCommand(arguments: [
            "query",
            "--use-cached",
            "--app", "focused",
            "--max-depth", "1",
            "--limit", "1",
            "--no-color",
            "AXApplication",
        ])

        #expect(cachedResult.exitCode == 0)
        #expect(cachedResult.output?.contains("ref=\(reference)") == true)

        let actionResult = try runOSXCommand(arguments: [
            "action",
            "read AXRole from \(reference);",
        ])

        #expect(actionResult.exitCode == 0)
        #expect(actionResult.output?.contains("ok [1] read AXRole from \(reference)") == true)
        #expect(actionResult.output?.contains("value [1] AXApplication") == true)
    }

    @Test("Interactive mode requires an app argument", .tags(.safe))
    func interactiveRequiresApp() throws {
        let result = try runOSXCommand(arguments: ["interactive"])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Interactive mode requires --app.") == true)
    }

    @Test("Interactive mode requires a TTY", .tags(.safe))
    func interactiveRequiresTTY() throws {
        let result = try runOSXCommand(arguments: [
            "interactive",
            "focused",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Interactive mode requires an interactive terminal") == true)
    }

    @Test("Action mode requires a program argument", .tags(.safe))
    func actionRequiresProgram() throws {
        let result = try runOSXCommand(arguments: ["action"])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Action requires a program argument.") == true)
    }

    @Test("Action mode surfaces cache snapshot errors", .tags(.safe))
    func actionSurfacesCacheSnapshotErrors() throws {
        let result = try runOSXCommand(arguments: [
            "action",
            "read AXRole from deadbeef0;",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Unknown element reference 'deadbeef0'") == true)
    }

    @Test("Enable AX requires a bundle identifier", .tags(.safe))
    func enableAXRequiresBundleIdentifier() throws {
        let result = try runOSXCommand(arguments: ["enable-ax"])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("enable-ax requires a bundle id argument.") == true)
    }

    @Test("Enable AX surfaces non-running bundle errors", .tags(.safe))
    func enableAXRejectsNonRunningBundle() throws {
        let result = try runOSXCommand(arguments: [
            "enable-ax",
            "com.example.DoesNotExist",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("No running application found for bundle id 'com.example.DoesNotExist'.") == true)
    }

    @Test("Selector cache daemon rejects positional arguments", .tags(.safe))
    func selectorCacheDaemonRejectsPositionalArguments() throws {
        let result = try runOSXCommand(arguments: [
            "selector-cache-daemon",
            "extra",
        ])

        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("selector-cache-daemon does not accept positional arguments.") == true)
    }

    @Test("Subcommand help renders command-specific usage", .tags(.safe))
    func subcommandHelpRendersSpecificUsage() throws {
        let queryHelp = try runOSXCommand(arguments: ["help", "query"])
        #expect(queryHelp.exitCode == 0)
        #expect(queryHelp.output?.contains("osx query") == true)
        #expect(queryHelp.output?.contains("osx query --app <target> <selector> [options]") == true)

        let interactiveHelp = try runOSXCommand(arguments: ["help", "interactive"])
        #expect(interactiveHelp.exitCode == 0)
        #expect(interactiveHelp.output?.contains("osx interactive") == true)
        #expect(interactiveHelp.output?.contains("osx interactive <app> [options]") == true)

        let enableAXHelp = try runOSXCommand(arguments: ["help", "enable-ax"])
        #expect(enableAXHelp.exitCode == 0)
        #expect(enableAXHelp.output?.contains("osx enable-ax") == true)
        #expect(enableAXHelp.output?.contains("osx enable-ax <bundle-id> [options]") == true)
    }

    @Test(
        "Fixture app receives click and text interactions",
        .tags(.automation),
        .enabled(if: AXTestEnvironment.runAutomationScenarios))
    @MainActor
    func fixtureAppReceivesClickAndTextInteractions() async throws {
        let session = try await launchFixtureApp()
        defer {
            Task { await terminateFixtureApp(session) }
        }

        try await activateFixtureApp(session)

        let buttonQuery = try runOSXCommand(arguments: [
            "query",
            "--cache-session",
            "--app", session.appIdentifier,
            "--limit", "1",
            "--no-color",
            #"AXButton[AXTitle="Increment Counter"]"#,
        ])
        #expect(buttonQuery.exitCode == 0)
        let buttonQueryOutput = try #require(buttonQuery.output)
        let buttonRef = try #require(Self.firstReference(in: buttonQueryOutput))

        let clickResult = try runOSXCommand(arguments: [
            "action",
            "send click to \(buttonRef);",
        ])
        #expect(clickResult.exitCode == 0)

        let clickState = try await session.waitForState { state in
            state.counter == 1 && state.lastEvent == "increment"
        }
        #expect(clickState.counter == 1)

        let textFieldQuery = try runOSXCommand(arguments: [
            "query",
            "--cache-session",
            "--app", session.appIdentifier,
            "--limit", "1",
            "--no-color",
            "AXTextField",
        ])
        #expect(textFieldQuery.exitCode == 0)
        let textFieldQueryOutput = try #require(textFieldQuery.output)
        let textFieldRef = try #require(Self.firstReference(in: textFieldQueryOutput))

        let actionResult = try runOSXCommand(arguments: [
            "action",
            """
            send click to \(textFieldRef);
            send text "hello fixture" as keys to \(textFieldRef);
            """,
        ])
        #expect(actionResult.exitCode == 0)

        let typedState = try await session.waitForState { state in
            state.textValue.contains("hello fixture")
        }
        #expect(typedState.textValue.contains("hello fixture"))

        let echoQuery = try runOSXCommand(arguments: [
            "query",
            "--app", session.appIdentifier,
            "--limit", "1",
            "--no-color",
            #"AXStaticText[AXValue="Echo: hello fixture"]"#,
        ])
        #expect(echoQuery.exitCode == 0)
        #expect(echoQuery.output?.contains("Echo: hello fixture") == true)
    }

    private static func firstReference(in output: String) -> String? {
        let pattern = #"ref=([0-9a-f]{9})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let matchRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }

        return String(output[matchRange])
    }
}
