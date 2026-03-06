import ApplicationServices
import Foundation
import Testing
@testable import osq

@Suite("AX Exposure Runner")
@MainActor
struct AXExposureRunnerTests {
    @Test("Focuses target app, injects attributes, and restores original focus")
    func focusesInjectsAndRestores() throws {
        let original = AXExposureApp(pid: 11, bundleIdentifier: "com.example.original", isTerminated: false)
        let target = AXExposureApp(pid: 22, bundleIdentifier: "com.example.target", isTerminated: false)
        let state = MutableState(frontmost: original)
        state.attributeValues["AXEnhancedUserInterface"] = false
        state.attributeValues["AXManualAccessibility"] = false

        let runner = AXExposureRunner(
            runningAppLookup: { bundle in
                bundle == target.bundleIdentifier ? target : nil
            },
            frontmostProvider: {
                state.frontmost
            },
            activatePid: { pid in
                state.activationPids.append(pid)
                if pid == target.pid {
                    state.frontmost = target
                } else if pid == original.pid {
                    state.frontmost = original
                }
                return true
            },
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            boolReader: { _, attribute in
                state.attributeValues[attribute]
            },
            boolWriter: { _, attribute, value in
                state.writes.append("\(attribute)=\(value)")
                state.attributeValues[attribute] = value
                return .success
            })

        let request = AXExposureRequest(bundleIdentifier: target.bundleIdentifier, focusTimeoutSeconds: 0.25)
        let report = try runner.execute(request)

        #expect(report.bundleIdentifier == target.bundleIdentifier)
        #expect(report.targetPid == target.pid)
        #expect(report.originalBundleIdentifier == original.bundleIdentifier)
        #expect(report.enhancedBefore == false)
        #expect(report.enhancedAfter == true)
        #expect(report.manualBefore == false)
        #expect(report.manualAfter == true)
        #expect(report.restoredOriginalFocus == true)
        #expect(state.activationPids == [target.pid, original.pid])
        #expect(state.writes == [
            "AXEnhancedUserInterface=true",
            "AXManualAccessibility=true",
            "AXEnhancedUserInterface=true",
        ])
    }

    @Test("Errors when target app is not running")
    func errorsWhenTargetAppMissing() {
        let runner = AXExposureRunner(
            runningAppLookup: { _ in nil },
            frontmostProvider: { nil },
            activatePid: { _ in false })

        do {
            _ = try runner.execute(AXExposureRequest(bundleIdentifier: "com.example.missing", focusTimeoutSeconds: 0.1))
            Issue.record("Expected missing-app failure")
        } catch let error as AXExposureCLIError {
            #expect(error == .applicationNotRunning("com.example.missing"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Errors when target app never becomes frontmost")
    func errorsWhenFocusTimesOut() {
        let original = AXExposureApp(pid: 11, bundleIdentifier: "com.example.original", isTerminated: false)
        let target = AXExposureApp(pid: 22, bundleIdentifier: "com.example.target", isTerminated: false)
        let state = MutableState(frontmost: original)

        let runner = AXExposureRunner(
            runningAppLookup: { _ in target },
            frontmostProvider: { state.frontmost },
            activatePid: { pid in
                state.activationPids.append(pid)
                return true
            },
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) })

        do {
            _ = try runner.execute(AXExposureRequest(bundleIdentifier: target.bundleIdentifier, focusTimeoutSeconds: 0.12))
            Issue.record("Expected focus-timeout failure")
        } catch let error as AXExposureCLIError {
            #expect(error == .focusTimedOut(target.bundleIdentifier))
            #expect(state.activationPids == [target.pid])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Errors when attribute write fails and still restores focus")
    func errorsWhenAttributeWriteFailsAndRestores() {
        let original = AXExposureApp(pid: 11, bundleIdentifier: "com.example.original", isTerminated: false)
        let target = AXExposureApp(pid: 22, bundleIdentifier: "com.example.target", isTerminated: false)
        let state = MutableState(frontmost: original)

        let runner = AXExposureRunner(
            runningAppLookup: { _ in target },
            frontmostProvider: { state.frontmost },
            activatePid: { pid in
                state.activationPids.append(pid)
                if pid == target.pid {
                    state.frontmost = target
                } else if pid == original.pid {
                    state.frontmost = original
                }
                return true
            },
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            boolReader: { _, _ in nil },
            boolWriter: { _, attribute, _ in
                if attribute == "AXManualAccessibility" {
                    return .attributeUnsupported
                }
                return .success
            })

        do {
            _ = try runner.execute(AXExposureRequest(bundleIdentifier: target.bundleIdentifier, focusTimeoutSeconds: 0.2))
            Issue.record("Expected attribute-write failure")
        } catch let error as AXExposureCLIError {
            #expect(error == .setAttributeFailed(
                attribute: "AXManualAccessibility",
                errorCode: AXError.attributeUnsupported.rawValue))
            #expect(state.activationPids == [target.pid, original.pid])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Accepts frontmost bundle match when PID differs")
    func acceptsFrontmostBundleMatchWhenPidDiffers() throws {
        let original = AXExposureApp(pid: 11, bundleIdentifier: "com.example.original", isTerminated: false)
        let target = AXExposureApp(pid: 22, bundleIdentifier: "com.example.target", isTerminated: false)
        let targetHelperFrontmost = AXExposureApp(pid: 33, bundleIdentifier: "com.example.target", isTerminated: false)
        let state = MutableState(frontmost: original)

        let runner = AXExposureRunner(
            runningAppLookup: { _ in target },
            frontmostProvider: { state.frontmost },
            activatePid: { pid in
                state.activationPids.append(pid)
                if pid == target.pid {
                    state.frontmost = targetHelperFrontmost
                } else if pid == original.pid {
                    state.frontmost = original
                }
                return true
            },
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            boolReader: { _, _ in nil },
            boolWriter: { _, _, _ in .success })

        let report = try runner.execute(
            AXExposureRequest(bundleIdentifier: target.bundleIdentifier, focusTimeoutSeconds: 0.2))

        #expect(report.restoredOriginalFocus == true)
        #expect(state.activationPids == [target.pid, original.pid])
    }

    @Test("Accepts AX focused-app signal when workspace frontmost is unavailable")
    func acceptsAXFocusedSignalWhenWorkspaceFrontmostMissing() throws {
        let target = AXExposureApp(pid: 22, bundleIdentifier: "com.example.target", isTerminated: false)
        let focusedHelper = AXExposureApp(pid: 44, bundleIdentifier: "com.example.target", isTerminated: false)
        let state = MutableState(frontmost: nil)

        let runner = AXExposureRunner(
            runningAppLookup: { _ in target },
            frontmostProvider: { state.frontmost },
            activatePid: { pid in
                state.activationPids.append(pid)
                return true
            },
            focusedApplicationProvider: { focusedHelper },
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            boolReader: { _, _ in nil },
            boolWriter: { _, _, _ in .success })

        let report = try runner.execute(
            AXExposureRequest(bundleIdentifier: target.bundleIdentifier, focusTimeoutSeconds: 0.2))

        #expect(report.restoredOriginalFocus == true)
        #expect(state.activationPids == [target.pid])
    }

    @Test("Accepts AX frontmost attribute signal")
    func acceptsAXFrontmostAttributeSignal() throws {
        let original = AXExposureApp(pid: 11, bundleIdentifier: "com.example.original", isTerminated: false)
        let target = AXExposureApp(pid: 22, bundleIdentifier: "com.example.target", isTerminated: false)
        let state = MutableState(frontmost: original)

        let runner = AXExposureRunner(
            runningAppLookup: { _ in target },
            frontmostProvider: { state.frontmost },
            activatePid: { pid in
                state.activationPids.append(pid)
                if pid == original.pid {
                    state.frontmost = original
                }
                return true
            },
            targetAXFrontmostProvider: { pid in
                pid == target.pid
            },
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            boolReader: { _, _ in nil },
            boolWriter: { _, _, _ in .success })

        let report = try runner.execute(
            AXExposureRequest(bundleIdentifier: target.bundleIdentifier, focusTimeoutSeconds: 0.2))

        #expect(report.restoredOriginalFocus == true)
        #expect(state.activationPids == [target.pid])
    }

    @Test("Falls back to another process when first candidate rejects AX attributes")
    func fallsBackToAnotherProcessWhenFirstCandidateFailsWrite() throws {
        let original = AXExposureApp(pid: 11, bundleIdentifier: "com.example.original", isTerminated: false)
        let helper = AXExposureApp(pid: 22, bundleIdentifier: "com.example.target", isTerminated: false, activationPolicy: .accessory)
        let main = AXExposureApp(pid: 33, bundleIdentifier: "com.example.target", isTerminated: false, activationPolicy: .regular)
        let state = MutableState(frontmost: original)

        let runner = AXExposureRunner(
            runningAppLookup: { _ in helper },
            runningAppsProvider: { _ in [helper, main] },
            frontmostProvider: { state.frontmost },
            activatePid: { pid in
                state.activationPids.append(pid)
                if pid == helper.pid {
                    state.frontmost = helper
                } else if pid == main.pid {
                    state.frontmost = main
                } else if pid == original.pid {
                    state.frontmost = original
                }
                return true
            },
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            boolReader: { _, _ in nil },
            boolWriter: { element, _, _ in
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                if pid == helper.pid {
                    return .illegalArgument
                }
                return .success
            })

        let report = try runner.execute(
            AXExposureRequest(bundleIdentifier: helper.bundleIdentifier, focusTimeoutSeconds: 0.2))

        #expect(report.targetPid == main.pid)
        #expect(report.restoredOriginalFocus == true)
        #expect(state.activationPids == [helper.pid, main.pid, original.pid])
    }
}

private final class MutableState {
    init(frontmost: AXExposureApp?) {
        self.frontmost = frontmost
    }

    var frontmost: AXExposureApp?
    var now: Date = .init(timeIntervalSince1970: 1_700_000_000)
    var activationPids: [pid_t] = []
    var writes: [String] = []
    var attributeValues: [String: Bool] = [:]
}
