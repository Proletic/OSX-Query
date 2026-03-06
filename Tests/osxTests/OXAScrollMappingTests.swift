import Testing
@testable import osx

@Suite("OXA Scroll Mapping")
struct OXAScrollMappingTests {
    @Test("Natural scroll disabled keeps legacy wheel-sign mapping")
    func naturalScrollDisabledMapping() {
        let up = OXAExecutor.scrollDeltas(for: .up, amount: 80, naturalScrollEnabled: false)
        let down = OXAExecutor.scrollDeltas(for: .down, amount: 80, naturalScrollEnabled: false)
        let left = OXAExecutor.scrollDeltas(for: .left, amount: 80, naturalScrollEnabled: false)
        let right = OXAExecutor.scrollDeltas(for: .right, amount: 80, naturalScrollEnabled: false)

        #expect(up.deltaX == 0)
        #expect(up.deltaY == 80)
        #expect(down.deltaX == 0)
        #expect(down.deltaY == -80)
        #expect(left.deltaX == 80)
        #expect(left.deltaY == 0)
        #expect(right.deltaX == -80)
        #expect(right.deltaY == 0)
    }

    @Test("Natural scroll enabled flips wheel-sign mapping")
    func naturalScrollEnabledMapping() {
        let up = OXAExecutor.scrollDeltas(for: .up, amount: 80, naturalScrollEnabled: true)
        let down = OXAExecutor.scrollDeltas(for: .down, amount: 80, naturalScrollEnabled: true)
        let left = OXAExecutor.scrollDeltas(for: .left, amount: 80, naturalScrollEnabled: true)
        let right = OXAExecutor.scrollDeltas(for: .right, amount: 80, naturalScrollEnabled: true)

        #expect(up.deltaX == 0)
        #expect(up.deltaY == -80)
        #expect(down.deltaX == 0)
        #expect(down.deltaY == 80)
        #expect(left.deltaX == -80)
        #expect(left.deltaY == 0)
        #expect(right.deltaX == 80)
        #expect(right.deltaY == 0)
    }
}
