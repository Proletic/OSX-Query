import Foundation
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
        #expect(result.errorOutput?.contains("No cached query snapshot available.") == true)
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
}
