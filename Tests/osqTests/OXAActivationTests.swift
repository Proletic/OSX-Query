import Foundation
import Testing
@testable import osq

@Suite("OXA Activation")
@MainActor
struct OXAActivationTests {
    @Test("Returns true when activation succeeds")
    func returnsTrueWhenActivationSucceeds() {
        let success = OXAExecutor.ensureApplicationFrontmost(
            pid: 42,
            timeout: 0.2,
            pollInterval: 0.01,
            now: Date.init,
            sleep: { _ in },
            activatePid: { _ in true },
            frontmostPidProvider: { nil },
            focusedPidProvider: { nil },
            axFrontmostProvider: { _ in false })

        #expect(success == true)
    }

    @Test("Returns false when activation fails")
    func returnsFalseWhenActivationFails() {
        let success = OXAExecutor.ensureApplicationFrontmost(
            pid: 42,
            timeout: 0.2,
            pollInterval: 0.01,
            now: Date.init,
            sleep: { _ in },
            activatePid: { _ in false },
            frontmostPidProvider: { 42 },
            focusedPidProvider: { 42 },
            axFrontmostProvider: { _ in true })

        #expect(success == false)
    }

    @Test("Passes target PID to activation callback")
    func passesTargetPidToActivationCallback() {
        var capturedPid: pid_t?

        _ = OXAExecutor.ensureApplicationFrontmost(
            pid: 77,
            timeout: 0.2,
            pollInterval: 0.01,
            now: Date.init,
            sleep: { _ in },
            activatePid: { pid in
                capturedPid = pid
                return true
            },
            frontmostPidProvider: { nil },
            focusedPidProvider: { nil },
            axFrontmostProvider: { _ in false })

        #expect(capturedPid == 77)
    }
}
