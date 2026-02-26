import AppKit
import ApplicationServices
import AXorcist
import Foundation

enum AXExposureCLIError: LocalizedError, Equatable {
    case missingBundleIdentifier
    case conflictingInputModes
    case conflictingSelectorMode
    case applicationNotRunning(String)
    case activationFailed(String)
    case focusTimedOut(String)
    case setAttributeFailed(attribute: String, errorCode: Int32)
    case restoreFocusFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            "AX exposure mode requires a non-empty bundle identifier."
        case .conflictingInputModes:
            "AX exposure mode cannot be combined with JSON input flags or payloads."
        case .conflictingSelectorMode:
            "AX exposure mode cannot be combined with selector mode flags."
        case let .applicationNotRunning(bundle):
            "No running application found for bundle id '\(bundle)'."
        case let .activationFailed(bundle):
            "Failed to focus target app '\(bundle)' before injecting AX attributes."
        case let .focusTimedOut(bundle):
            "Timed out waiting for app '\(bundle)' to become frontmost."
        case let .setAttributeFailed(attribute, errorCode):
            "Failed to set attribute '\(attribute)' (AXError \(errorCode))."
        case let .restoreFocusFailed(bundle):
            "Failed to restore focus to original app '\(bundle)'."
        }
    }
}

struct AXExposureRequest: Equatable {
    let bundleIdentifier: String
    let focusTimeoutSeconds: TimeInterval
}

enum AXExposureRequestBuilder {
    private static let defaultFocusTimeoutSeconds: TimeInterval = 2

    static func build(
        bundleIdentifier: String?,
        hasStructuredInput: Bool,
        hasSelectorInput: Bool) throws -> AXExposureRequest?
    {
        guard let bundleIdentifier else { return nil }
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw AXExposureCLIError.missingBundleIdentifier
        }
        if hasStructuredInput {
            throw AXExposureCLIError.conflictingInputModes
        }
        if hasSelectorInput {
            throw AXExposureCLIError.conflictingSelectorMode
        }

        return AXExposureRequest(
            bundleIdentifier: trimmed,
            focusTimeoutSeconds: defaultFocusTimeoutSeconds)
    }
}

struct AXExposureExecutionReport: Equatable {
    let bundleIdentifier: String
    let targetPid: pid_t
    let originalBundleIdentifier: String?
    let enhancedBefore: Bool?
    let enhancedAfter: Bool?
    let manualBefore: Bool?
    let manualAfter: Bool?
    let restoredOriginalFocus: Bool
}

enum AXExposureOutputFormatter {
    static func format(report: AXExposureExecutionReport) -> String {
        let original = report.originalBundleIdentifier ?? "none"
        let enhancedBefore = report.enhancedBefore.map(String.init(describing:)) ?? "nil"
        let enhancedAfter = report.enhancedAfter.map(String.init(describing:)) ?? "nil"
        let manualBefore = report.manualBefore.map(String.init(describing:)) ?? "nil"
        let manualAfter = report.manualAfter.map(String.init(describing:)) ?? "nil"

        return "ax_exposure bundle=\(report.bundleIdentifier) pid=\(report.targetPid) original=\(original) enhanced_before=\(enhancedBefore) enhanced_after=\(enhancedAfter) manual_before=\(manualBefore) manual_after=\(manualAfter) restored=\(report.restoredOriginalFocus)"
    }
}

@MainActor
struct AXExposureRunner {
    init(
        runningAppLookup: @escaping @MainActor (String) -> AXExposureApp?,
        frontmostProvider: @escaping @MainActor () -> AXExposureApp?,
        activatePid: @escaping @MainActor (pid_t) -> Bool,
        now: @escaping @MainActor () -> Date = Date.init,
        sleep: @escaping @MainActor (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        boolReader: @escaping @MainActor (AXUIElement, String) -> Bool? = AXExposureRunner.liveReadBool,
        boolWriter: @escaping @MainActor (AXUIElement, String, Bool) -> AXError = AXExposureRunner.liveWriteBool)
    {
        self.runningAppLookup = runningAppLookup
        self.frontmostProvider = frontmostProvider
        self.activatePid = activatePid
        self.now = now
        self.sleep = sleep
        self.boolReader = boolReader
        self.boolWriter = boolWriter
    }

    init() {
        self.init(
            runningAppLookup: AXExposureRunner.liveRunningAppLookup,
            frontmostProvider: AXExposureRunner.liveFrontmostProvider,
            activatePid: AXExposureRunner.liveActivatePid)
    }

    func execute(_ request: AXExposureRequest) throws -> AXExposureExecutionReport {
        guard let targetApp = self.runningAppLookup(request.bundleIdentifier), !targetApp.isTerminated else {
            throw AXExposureCLIError.applicationNotRunning(request.bundleIdentifier)
        }

        let originalFrontmost = self.frontmostProvider()

        guard self.activatePid(targetApp.pid) else {
            throw AXExposureCLIError.activationFailed(request.bundleIdentifier)
        }
        try self.waitUntilFrontmost(pid: targetApp.pid, bundleIdentifier: request.bundleIdentifier, timeout: request.focusTimeoutSeconds)

        do {
            let targetElement = AXUIElementCreateApplication(targetApp.pid)
            let enhancedBefore = self.boolReader(targetElement, AXExposureAttributes.enhancedUI)
            let manualBefore = self.boolReader(targetElement, AXExposureAttributes.manualAccessibility)

            let enhancedSetError = self.boolWriter(targetElement, AXExposureAttributes.enhancedUI, true)
            guard enhancedSetError == .success else {
                throw AXExposureCLIError.setAttributeFailed(
                    attribute: AXExposureAttributes.enhancedUI,
                    errorCode: enhancedSetError.rawValue)
            }

            let manualSetError = self.boolWriter(targetElement, AXExposureAttributes.manualAccessibility, true)
            guard manualSetError == .success else {
                throw AXExposureCLIError.setAttributeFailed(
                    attribute: AXExposureAttributes.manualAccessibility,
                    errorCode: manualSetError.rawValue)
            }

            let enhancedAfter = self.boolReader(targetElement, AXExposureAttributes.enhancedUI)
            let manualAfter = self.boolReader(targetElement, AXExposureAttributes.manualAccessibility)

            let restored = try self.restoreFocus(
                originalFrontmost: originalFrontmost,
                focusedTarget: targetApp,
                timeout: request.focusTimeoutSeconds)

            return AXExposureExecutionReport(
                bundleIdentifier: request.bundleIdentifier,
                targetPid: targetApp.pid,
                originalBundleIdentifier: originalFrontmost?.bundleIdentifier,
                enhancedBefore: enhancedBefore,
                enhancedAfter: enhancedAfter,
                manualBefore: manualBefore,
                manualAfter: manualAfter,
                restoredOriginalFocus: restored)
        } catch {
            _ = try? self.restoreFocus(
                originalFrontmost: originalFrontmost,
                focusedTarget: targetApp,
                timeout: request.focusTimeoutSeconds)
            throw error
        }
    }

    private let runningAppLookup: @MainActor (String) -> AXExposureApp?
    private let frontmostProvider: @MainActor () -> AXExposureApp?
    private let activatePid: @MainActor (pid_t) -> Bool
    private let now: @MainActor () -> Date
    private let sleep: @MainActor (TimeInterval) -> Void
    private let boolReader: @MainActor (AXUIElement, String) -> Bool?
    private let boolWriter: @MainActor (AXUIElement, String, Bool) -> AXError

    private func waitUntilFrontmost(pid: pid_t, bundleIdentifier: String, timeout: TimeInterval) throws {
        let deadline = self.now().addingTimeInterval(timeout)
        while self.now() < deadline {
            if self.isFrontmostTarget(pid: pid, bundleIdentifier: bundleIdentifier) {
                return
            }
            self.sleep(0.05)
        }
        throw AXExposureCLIError.focusTimedOut(bundleIdentifier)
    }

    private func restoreFocus(
        originalFrontmost: AXExposureApp?,
        focusedTarget: AXExposureApp,
        timeout: TimeInterval) throws -> Bool
    {
        guard let originalFrontmost else { return true }
        if originalFrontmost.pid == focusedTarget.pid || originalFrontmost.isTerminated {
            return true
        }
        guard self.activatePid(originalFrontmost.pid) else {
            throw AXExposureCLIError.restoreFocusFailed(originalFrontmost.bundleIdentifier)
        }
        try self.waitUntilFrontmost(
            pid: originalFrontmost.pid,
            bundleIdentifier: originalFrontmost.bundleIdentifier,
            timeout: timeout)
        return true
    }

    private static func liveRunningAppLookup(bundleIdentifier: String) -> AXExposureApp? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
            .map(AXExposureApp.init)
    }

    private static func liveFrontmostProvider() -> AXExposureApp? {
        NSWorkspace.shared.frontmostApplication.map(AXExposureApp.init)
    }

    private static func liveActivatePid(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            return false
        }
        if app.activate(options: [.activateAllWindows]) {
            return true
        }
        // Fallback: ask the AX application element to become frontmost.
        return Element(AXUIElementCreateApplication(pid)).activate()
    }

    private static func liveReadBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func liveWriteBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(
            element,
            attribute as CFString,
            CFConstants.cfBoolean(from: value))
    }

    private func isFrontmostTarget(pid: pid_t, bundleIdentifier: String) -> Bool {
        guard let frontmost = self.frontmostProvider() else { return false }
        if frontmost.pid == pid {
            return true
        }

        return frontmost.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
}

struct AXExposureApp: Equatable {
    init(pid: pid_t, bundleIdentifier: String, isTerminated: Bool) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.isTerminated = isTerminated
    }

    init(_ app: NSRunningApplication) {
        self.pid = app.processIdentifier
        self.bundleIdentifier = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        self.isTerminated = app.isTerminated
    }

    let pid: pid_t
    let bundleIdentifier: String
    let isTerminated: Bool
}

private enum AXExposureAttributes {
    static let enhancedUI = "AXEnhancedUserInterface"
    static let manualAccessibility = "AXManualAccessibility"
}
