import Foundation
import Testing
@testable import OSXQuery

@Suite("OSXQuery CLI UX Tests", .tags(.safe))
struct PingIntegrationTests {
    @Test("Rejects legacy --stdin flag", .tags(.safe))
    func rejectsLegacyStdinFlag() throws {
        let result = try runOSXCommand(arguments: ["--stdin"])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Unknown option --stdin") == true)
        #expect(result.errorOutput?.contains("osx --help") == true)
    }

    @Test("Rejects legacy --file flag", .tags(.safe))
    func rejectsLegacyFileFlag() throws {
        let result = try runOSXCommand(arguments: ["--file", "/tmp/legacy.json"])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Unknown option --file") == true)
        #expect(result.errorOutput?.contains("osx --help") == true)
    }

    @Test("Rejects legacy --json flag", .tags(.safe))
    func rejectsLegacyJSONFlag() throws {
        let result = try runOSXCommand(arguments: ["--json", "{}"])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Unknown option --json") == true)
        #expect(result.errorOutput?.contains("osx --help") == true)
    }

    @Test("Rejects legacy positional JSON payload", .tags(.safe))
    func rejectsLegacyPositionalPayload() throws {
        let payload = #"{"command":"ping"}"#
        let result = try runOSXCommand(arguments: [payload])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Unknown subcommand") == true)
        #expect(result.errorOutput?.contains("osx --help") == true)
    }

    @Test("Rejects empty invocation without a subcommand", .tags(.safe))
    func rejectsNoModeInvocation() throws {
        let result = try runOSXCommand(arguments: [])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Command 'osx' requires a subcommand") == true)
        #expect(result.errorOutput?.contains("osx --help") == true)
    }

    @Test("Prints help with --help", .tags(.safe))
    func printsHelpLongFlag() throws {
        let result = try runOSXCommand(arguments: ["--help"])
        #expect(result.exitCode == 0)
        #expect(result.errorOutput?.isEmpty ?? true)
        #expect(result.output?.contains("USAGE") == true)
        #expect(result.output?.contains("COMMANDS") == true)
        #expect(result.output?.contains("query") == true)
    }

    @Test("Prints help with help command", .tags(.safe))
    func printsHelpCommand() throws {
        let result = try runOSXCommand(arguments: ["help"])
        #expect(result.exitCode == 0)
        #expect(result.errorOutput?.isEmpty ?? true)
        #expect(result.output?.contains("USAGE") == true)
        #expect(result.output?.contains("enable-ax") == true)
    }
}
