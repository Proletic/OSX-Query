import Testing
@testable import osq

@Suite("Selector Query Runner")
struct SelectorQueryRunnerTests {
    @MainActor
    @Test("Executes query and applies display limit")
    func executesQueryAndLimitsOutput() throws {
        let request = SelectorQueryRequest(
            appIdentifier: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: 5,
            limit: 2,
            colorEnabled: false,
            showPath: false)

        var capturedRequest: SelectorQueryRequest?
        var timestamps: [UInt64] = [1_000_000_000, 1_005_000_000]

        let runner = SelectorQueryRunner(
            queryExecutor: { request in
                capturedRequest = request
                return SelectorQueryResult(traversedCount: 9, matchedCount: 3, shown: [
                    SelectorMatchSummary(role: "AXButton", computedName: nil, title: "A", value: nil, identifier: nil, descriptionText: nil, path: nil),
                    SelectorMatchSummary(role: "AXButton", computedName: nil, title: "B", value: nil, identifier: nil, descriptionText: nil, path: nil),
                ])
            },
            nowNanoseconds: {
                timestamps.removeFirst()
            })

        let report = try runner.execute(request)

        #expect(capturedRequest?.appIdentifier == "com.apple.TextEdit")
        #expect(capturedRequest?.selector == "AXButton")
        #expect(capturedRequest?.maxDepth == 5)
        #expect(capturedRequest?.limit == 2)
        #expect(capturedRequest?.showPath == false)

        #expect(report.traversedCount == 9)
        #expect(report.matchedCount == 3)
        #expect(report.shownCount == 2)
        #expect(report.results.count == 2)
        #expect(report.results.map { $0.title ?? "" } == ["A", "B"])
        #expect(report.elapsedMilliseconds == 5)
    }

    @MainActor
    @Test("Propagates query executor failures")
    func propagatesQueryErrors() {
        let request = SelectorQueryRequest(
            appIdentifier: "missing-app",
            selector: "AXButton",
            maxDepth: 5,
            limit: 10,
            colorEnabled: false,
            showPath: false)

        let runner = SelectorQueryRunner(
            queryExecutor: { _ in
                throw SelectorQueryCLIError.applicationNotFound("missing-app")
            },
            nowNanoseconds: { 0 })

        do {
            _ = try runner.execute(request)
            Issue.record("Expected runner failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .applicationNotFound("missing-app"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
