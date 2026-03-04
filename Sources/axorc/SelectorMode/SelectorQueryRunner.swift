import Foundation

@MainActor
struct SelectorQueryRunner {
    typealias QueryExecutor = @MainActor (SelectorQueryRequest) throws -> SelectorQueryResult
    typealias NanosecondClock = @MainActor () -> UInt64

    init(
        queryExecutor: @escaping QueryExecutor = LiveSelectorQueryExecutor.execute,
        nowNanoseconds: @escaping NanosecondClock = defaultNowNanoseconds)
    {
        self.queryExecutor = queryExecutor
        self.nowNanoseconds = nowNanoseconds
    }

    func execute(_ request: SelectorQueryRequest) throws -> SelectorQueryExecutionReport {
        let startedAt = self.nowNanoseconds()
        let result = try self.queryExecutor(request)
        let endedAt = self.nowNanoseconds()

        let elapsedMilliseconds = Double(endedAt &- startedAt) / 1_000_000

        return SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: elapsedMilliseconds,
            traversedCount: result.traversedCount,
            matchedCount: result.matchedCount,
            shownCount: result.shown.count,
            results: result.shown)
    }

    private let queryExecutor: QueryExecutor
    private let nowNanoseconds: NanosecondClock

    private static func defaultNowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
