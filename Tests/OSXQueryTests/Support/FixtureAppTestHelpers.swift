@preconcurrency import AppKit
import AXFixtureShared
import Foundation

struct AXFixtureAppSession {
    let process: Process
    let stateFileURL: URL
    let readyFileURL: URL

    var pid: pid_t {
        pid_t(self.process.processIdentifier)
    }

    var appIdentifier: String {
        String(self.pid)
    }

    @MainActor
    var runningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: self.pid)
    }

    func readState() throws -> AXFixtureState {
        let data = try Data(contentsOf: self.stateFileURL)
        return try JSONDecoder().decode(AXFixtureState.self, from: data)
    }

    func waitForState(
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: (AXFixtureState) -> Bool) async throws -> AXFixtureState
    {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let state = try? self.readState(), predicate(state) {
                return state
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        let latestState = try? self.readState()
        throw TestError.generic("Fixture state did not satisfy condition. Latest state: \(String(describing: latestState)) @\(file):\(line)")
    }
}

@MainActor
func launchFixtureApp() async throws -> AXFixtureAppSession {
    let fixtureURL = productsDirectory.appendingPathComponent("AXFixtureApp")
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("axfixture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let stateFileURL = tempDir.appendingPathComponent("state.json")
    let readyFileURL = tempDir.appendingPathComponent("ready")

    let process = Process()
    process.executableURL = fixtureURL
    process.environment = ProcessInfo.processInfo.environment.merging([
        AXFixtureEnvironment.stateFileKey: stateFileURL.path,
        AXFixtureEnvironment.readyFileKey: readyFileURL.path,
    ]) { _, new in new }

    try process.run()

    let session = AXFixtureAppSession(
        process: process,
        stateFileURL: stateFileURL,
        readyFileURL: readyFileURL)
    try await waitForFixtureReady(session)
    return session
}

@MainActor
func terminateFixtureApp(_ session: AXFixtureAppSession) async {
    guard let app = session.runningApplication else {
        if session.process.isRunning {
            session.process.terminate()
        }
        return
    }

    app.terminate()
    for _ in 0..<10 {
        if app.isTerminated { return }
        try? await Task.sleep(for: .milliseconds(100))
    }

    if !app.isTerminated {
        app.forceTerminate()
        try? await Task.sleep(for: .milliseconds(100))
    }
}

@MainActor
func activateFixtureApp(_ session: AXFixtureAppSession) async throws {
    guard let app = session.runningApplication else {
        throw TestError.appNotRunning("Fixture app is not running.")
    }
    _ = app.activate(options: [.activateAllWindows])
    try await Task.sleep(for: .milliseconds(400))
}

@MainActor
private func waitForFixtureReady(_ session: AXFixtureAppSession) async throws {
    for _ in 0..<50 {
        if FileManager.default.fileExists(atPath: session.readyFileURL.path),
           (try? session.readState()) != nil,
           session.runningApplication != nil
        {
            try await Task.sleep(for: .milliseconds(300))
            return
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    throw TestError.appNotRunning("Fixture app did not become ready.")
}
