import Foundation
import Testing
@testable import OSXQuery

extension Comment {
    init(_ text: String) {
        self.init(stringLiteral: text)
    }
}

extension Tag {
    @Tag static var safe: Self
    @Tag static var automation: Self
}

@preconcurrency
enum AXTestEnvironment {
    @inline(__always)
    @preconcurrency nonisolated static func flag(_ key: String) -> Bool {
        ProcessInfo.processInfo.environment[key]?.lowercased() == "true"
    }

    @preconcurrency nonisolated(unsafe) static var runAutomationScenarios: Bool {
        flag("RUN_AUTOMATION_TESTS") || flag("RUN_LOCAL_TESTS")
    }
}

struct CommandResult {
    let output: String?
    let errorOutput: String?
    let exitCode: Int32
}

func runOSXCommand(arguments: [String]) throws -> CommandResult {
    let osxURL = productsDirectory.appendingPathComponent("osx")

    let process = Process()
    process.executableURL = osxURL
    process.arguments = arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let readStdout = startStreaming(pipe: outputPipe)
    let readStderr = startStreaming(pipe: errorPipe)

    try process.run()
    process.waitUntilExit()

    let outputData = readStdout()
    let errorData = readStderr()

    let output = String(data: outputData, encoding: String.Encoding.utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let errorOutput = String(data: errorData, encoding: String.Encoding.utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return CommandResult(output: output, errorOutput: errorOutput, exitCode: process.terminationStatus)
}

// MARK: - Error Types

enum TestError: Error, CustomStringConvertible {
    case appNotRunning(String)
    case generic(String)

    var description: String {
        switch self {
        case let .appNotRunning(string): "AppNotRunning: \(string)"
        case let .generic(string): "GenericTestError: \(string)"
        }
    }
}

// MARK: - Helper Properties

var productsDirectory: URL {
    #if os(macOS)
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return bundle.bundleURL.deletingLastPathComponent()
    }

    let currentFileURL = URL(fileURLWithPath: #filePath)
    let packageRootPath = currentFileURL.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    let buildPathsToTry = [
        packageRootPath.appendingPathComponent(".build/debug"),
        packageRootPath.appendingPathComponent(".build/arm64-apple-macosx/debug"),
        packageRootPath.appendingPathComponent(".build/x86_64-apple-macosx/debug"),
    ]

    let fileManager = FileManager.default
    for path in buildPathsToTry where fileManager.fileExists(atPath: path.appendingPathComponent("osx").path) {
        return path
    }

    let searchedPaths = buildPathsToTry.map(\.path).joined(separator: ", ")
    fatalError(
        "couldn't find the products directory via Bundle or SPM fallback. " +
            "Package root guessed as: \(packageRootPath.path). " +
            "Searched paths: \(searchedPaths)")
    #else
    return Bundle.main.bundleURL
    #endif
}
