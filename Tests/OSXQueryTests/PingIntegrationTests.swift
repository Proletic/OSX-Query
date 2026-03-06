import Foundation
import Testing
@testable import OSXQuery

@Suite("OSXQuery CLI UX Tests", .tags(.safe))
struct PingIntegrationTests {
    @Test("Rejects legacy --stdin flag", .tags(.safe))
    func rejectsLegacyStdinFlag() throws {
        let result = try runOSQCommand(arguments: ["--stdin"])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Unknown option --stdin") == true)
        #expect(result.errorOutput?.contains("osq --help") == true)
    }

    @Test("Rejects legacy --file flag", .tags(.safe))
    func rejectsLegacyFileFlag() throws {
        let result = try runOSQCommand(arguments: ["--file", "/tmp/legacy.json"])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Unknown option --file") == true)
        #expect(result.errorOutput?.contains("osq --help") == true)
    }

    @Test("Rejects legacy --json flag", .tags(.safe))
    func rejectsLegacyJSONFlag() throws {
        let result = try runOSQCommand(arguments: ["--json", "{}"])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: Unknown option --json") == true)
        #expect(result.errorOutput?.contains("osq --help") == true)
    }

    @Test("Rejects legacy positional JSON payload", .tags(.safe))
    func rejectsLegacyPositionalPayload() throws {
        let payload = #"{"command":"ping"}"#
        let result = try runOSQCommand(arguments: [payload])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: No CLI mode selected") == true)
        #expect(result.errorOutput?.contains("osq --help") == true)
    }

    @Test("Rejects empty invocation without selector or AX exposure mode", .tags(.safe))
    func rejectsNoModeInvocation() throws {
        let result = try runOSQCommand(arguments: [])
        #expect(result.exitCode != 0)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("error: No CLI mode selected") == true)
        #expect(result.errorOutput?.contains("osq --help") == true)
    }

    @Test("Prints help with --help", .tags(.safe))
    func printsHelpLongFlag() throws {
        let result = try runOSQCommand(arguments: ["--help"])
        #expect(result.exitCode == 0)
        #expect(result.errorOutput?.isEmpty ?? true)
        #expect(result.output?.contains("USAGE") == true)
        #expect(result.output?.contains("OPTIONS") == true)
        #expect(result.output?.contains("--selector") == true)
    }

    @Test("Prints help with help command", .tags(.safe))
    func printsHelpCommand() throws {
        let result = try runOSQCommand(arguments: ["help"])
        #expect(result.exitCode == 0)
        #expect(result.errorOutput?.isEmpty ?? true)
        #expect(result.output?.contains("USAGE") == true)
        #expect(result.output?.contains("--enable-ax") == true)
    }
}
