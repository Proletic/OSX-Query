import AppKit
import Testing
@testable import AXorcist

// Helper type for decoding arbitrary JSON values
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = val.value
            }
            self.value = result
        } else {
            self.value = NSNull()
        }
    }
}

@Suite("AXorcist Application Query Tests", .tags(.safe))
struct ApplicationQueryTests {
    @Test("Collect all running applications", .tags(.safe))
    func getAllApplications() async throws {
        let result = try runAXORCCommand(arguments: [
            "--app", "focused",
            "--selector", "AXApplication",
            "--max-depth", "1",
            "--limit", "5",
            "--no-color",
        ])
        #expect(result.exitCode == 0, "Command should succeed")
        #expect(result.output?.contains("stats app=focused") == true, "Should include selector stats header")
        #expect(result.output?.contains("AXApplication") == true, "Should include AXApplication match rows")
    }

    @Test(
        "List TextEdit windows",
        .tags(.automation),
        .enabled(if: AXTestEnvironment.runAutomationScenarios))
    @MainActor
    func getWindowsOfApplication() async throws {
        await closeTextEdit()
        try await Task.sleep(for: .milliseconds(500))

        _ = try await setupTextEditAndGetInfo()
        defer {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first {
                app.terminate()
            }
        }

        try await Task.sleep(for: .seconds(1))

        let result = try runAXORCCommand(arguments: [
            "--app", "TextEdit",
            "--selector", "AXWindow",
            "--limit", "10",
            "--no-color",
        ])
        #expect(result.exitCode == 0)
        #expect(result.output?.contains("AXWindow") == true, "Output should include AXWindow entries")
    }

    @Test("Query non-existent application", .tags(.safe))
    func queryNonExistentApp() async throws {
        let result = try runAXORCCommand(arguments: [
            "--app", "NonExistentApp12345",
            "--selector", "*",
        ])

        #expect(result.exitCode != 0, "Command should fail when target app is not running")
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Could not find a running app") == true)
    }
}
