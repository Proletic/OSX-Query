import AppKit
import ApplicationServices
import Testing
@testable import OSXQuery

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

@Suite("OSXQuery Application Query Tests", .tags(.safe))
struct ApplicationQueryTests {
    @Test("Collect all running applications", .tags(.safe))
    func getAllApplications() async throws {
        let result = try runOSXCommand(arguments: [
            "query",
            "--app", "focused",
            "--max-depth", "1",
            "--limit", "5",
            "--no-color",
            "AXApplication",
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

        let result = try runOSXCommand(arguments: [
            "query",
            "--app", "TextEdit",
            "--limit", "10",
            "--no-color",
            "AXWindow",
        ])
        #expect(result.exitCode == 0)
        #expect(result.output?.contains("AXWindow") == true, "Output should include AXWindow entries")
    }

    @Test(
        "Selector query does not activate target app",
        .tags(.automation),
        .enabled(if: AXTestEnvironment.runAutomationScenarios))
    @MainActor
    func selectorQueryDoesNotActivateTargetApp() async throws {
        await closeTextEdit()
        try await Task.sleep(for: .milliseconds(500))

        let (textEditPid, _) = try await setupTextEditAndGetInfo()
        guard let textEditApp = NSRunningApplication(processIdentifier: textEditPid) else {
            Issue.record("Could not resolve running TextEdit app for PID \(textEditPid).")
            return
        }
        defer {
            textEditApp.terminate()
        }

        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            _ = finder.activate(options: [.activateAllWindows])
            try await Task.sleep(for: .milliseconds(500))
        }

        let preQueryFrontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        #expect(preQueryFrontmostPid != textEditPid, "Expected another app to be frontmost before query.")

        let result = try runOSXCommand(arguments: [
            "query",
            "--app", "com.apple.TextEdit",
            "--limit", "1",
            "--no-color",
            "AXTextArea",
        ])

        #expect(result.exitCode == 0, "Query command should succeed.")
        try await Task.sleep(for: .milliseconds(500))

        let postQueryFrontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        #expect(postQueryFrontmostPid == preQueryFrontmostPid, "Query should not steal focus from the current frontmost app.")
    }

    @Test("Query non-existent application", .tags(.safe))
    func queryNonExistentApp() async throws {
        let result = try runOSXCommand(arguments: [
            "query",
            "--app", "NonExistentApp12345",
            "*",
        ])

        #expect(result.exitCode != 0, "Command should fail when target app is not running")
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Could not find a running app") == true)
    }
}
