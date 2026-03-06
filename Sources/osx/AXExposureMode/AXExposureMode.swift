import AppKit
import ApplicationServices
import OSXQuery
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
        runningAppsProvider: @escaping @MainActor (String) -> [AXExposureApp] = { _ in [] },
        frontmostProvider: @escaping @MainActor () -> AXExposureApp?,
        activatePid: @escaping @MainActor (pid_t) -> Bool,
        focusedApplicationProvider: @escaping @MainActor () -> AXExposureApp? = { nil },
        targetAXFrontmostProvider: @escaping @MainActor (pid_t) -> Bool = { _ in false },
        now: @escaping @MainActor () -> Date = Date.init,
        sleep: @escaping @MainActor (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        boolReader: @escaping @MainActor (AXUIElement, String) -> Bool? = AXExposureRunner.liveReadBool,
        boolWriter: @escaping @MainActor (AXUIElement, String, Bool) -> AXError = AXExposureRunner.liveWriteBool)
    {
        self.runningAppLookup = runningAppLookup
        self.runningAppsProvider = runningAppsProvider
        self.frontmostProvider = frontmostProvider
        self.activatePid = activatePid
        self.focusedApplicationProvider = focusedApplicationProvider
        self.targetAXFrontmostProvider = targetAXFrontmostProvider
        self.now = now
        self.sleep = sleep
        self.boolReader = boolReader
        self.boolWriter = boolWriter
    }

    init() {
        self.init(
            runningAppLookup: AXExposureRunner.liveRunningAppLookup,
            runningAppsProvider: AXExposureRunner.liveRunningAppsProvider,
            frontmostProvider: AXExposureRunner.liveFrontmostProvider,
            activatePid: AXExposureRunner.liveActivatePid,
            focusedApplicationProvider: AXExposureRunner.liveFocusedApplicationProvider,
            targetAXFrontmostProvider: AXExposureRunner.liveTargetAXFrontmostProvider)
    }

    func execute(_ request: AXExposureRequest) throws -> AXExposureExecutionReport {
        var candidates = self.runningAppsProvider(request.bundleIdentifier)
            .filter { !$0.isTerminated }
        if candidates.isEmpty,
           let fallback = self.runningAppLookup(request.bundleIdentifier),
           !fallback.isTerminated
        {
            candidates = [fallback]
        }

        guard !candidates.isEmpty else {
            throw AXExposureCLIError.applicationNotRunning(request.bundleIdentifier)
        }

        let preferred = self.runningAppLookup(request.bundleIdentifier)
        candidates = self.orderedCandidates(
            candidates,
            preferred: preferred,
            bundleIdentifier: request.bundleIdentifier)

        let originalFrontmost = self.frontmostProvider()
        var lastError: AXExposureCLIError = .applicationNotRunning(request.bundleIdentifier)
        var successfulAttempt: (
            app: AXExposureApp,
            enhancedBefore: Bool?,
            enhancedAfter: Bool?,
            manualBefore: Bool?,
            manualAfter: Bool?)?

        for targetApp in candidates {
            guard self.activatePid(targetApp.pid) else {
                lastError = .activationFailed(request.bundleIdentifier)
                continue
            }

            do {
                try self.waitUntilFrontmost(
                    pid: targetApp.pid,
                    bundleIdentifier: request.bundleIdentifier,
                    timeout: request.focusTimeoutSeconds)
            } catch let focusError as AXExposureCLIError {
                lastError = focusError
                continue
            }

            let targetElement = AXUIElementCreateApplication(targetApp.pid)
            let enhancedBefore = self.boolReader(targetElement, AXExposureAttributes.enhancedUI)
            let manualBefore = self.boolReader(targetElement, AXExposureAttributes.manualAccessibility)

            let enhancedSetError = self.boolWriter(targetElement, AXExposureAttributes.enhancedUI, true)
            guard enhancedSetError == .success else {
                lastError = .setAttributeFailed(
                    attribute: AXExposureAttributes.enhancedUI,
                    errorCode: enhancedSetError.rawValue)
                continue
            }

            let manualSetError = self.boolWriter(targetElement, AXExposureAttributes.manualAccessibility, true)
            guard manualSetError == .success else {
                lastError = .setAttributeFailed(
                    attribute: AXExposureAttributes.manualAccessibility,
                    errorCode: manualSetError.rawValue)
                continue
            }

            _ = self.boolWriter(
                Element.systemWide().underlyingElement,
                AXExposureAttributes.enhancedUI,
                true)

            let enhancedAfter = self.boolReader(targetElement, AXExposureAttributes.enhancedUI)
            let manualAfter = self.boolReader(targetElement, AXExposureAttributes.manualAccessibility)

            successfulAttempt = (
                app: targetApp,
                enhancedBefore: enhancedBefore,
                enhancedAfter: enhancedAfter,
                manualBefore: manualBefore,
                manualAfter: manualAfter)
            break
        }

        guard let successfulAttempt else {
            _ = try? self.restoreFocus(to: originalFrontmost, timeout: request.focusTimeoutSeconds)
            throw lastError
        }

        let restored = try self.restoreFocus(to: originalFrontmost, timeout: request.focusTimeoutSeconds)

        return AXExposureExecutionReport(
            bundleIdentifier: request.bundleIdentifier,
            targetPid: successfulAttempt.app.pid,
            originalBundleIdentifier: originalFrontmost?.bundleIdentifier,
            enhancedBefore: successfulAttempt.enhancedBefore,
            enhancedAfter: successfulAttempt.enhancedAfter,
            manualBefore: successfulAttempt.manualBefore,
            manualAfter: successfulAttempt.manualAfter,
            restoredOriginalFocus: restored)
    }

    private let runningAppLookup: @MainActor (String) -> AXExposureApp?
    private let runningAppsProvider: @MainActor (String) -> [AXExposureApp]
    private let frontmostProvider: @MainActor () -> AXExposureApp?
    private let activatePid: @MainActor (pid_t) -> Bool
    private let focusedApplicationProvider: @MainActor () -> AXExposureApp?
    private let targetAXFrontmostProvider: @MainActor (pid_t) -> Bool
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
        to originalFrontmost: AXExposureApp?,
        timeout: TimeInterval) throws -> Bool
    {
        guard let originalFrontmost else { return true }
        if originalFrontmost.isTerminated {
            return true
        }
        if let currentFrontmost = self.frontmostProvider(),
           self.matchesTarget(
               currentFrontmost,
               pid: originalFrontmost.pid,
               bundleIdentifier: originalFrontmost.bundleIdentifier)
        {
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
        liveRunningAppsProvider(bundleIdentifier: bundleIdentifier).first
    }

    private static func liveRunningAppsProvider(bundleIdentifier: String) -> [AXExposureApp] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map(AXExposureApp.init)
    }

    private static func liveFrontmostProvider() -> AXExposureApp? {
        NSWorkspace.shared.frontmostApplication.map(AXExposureApp.init)
    }

    private static func liveFocusedApplicationProvider() -> AXExposureApp? {
        guard let focused = try? AXUIElement.focusedApplication() else {
            return nil
        }

        var pid: pid_t = 0
        let status = AXUIElementGetPid(focused, &pid)
        guard status == .success, pid > 0 else {
            return nil
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            return AXExposureApp(app)
        }
        return AXExposureApp(pid: pid, bundleIdentifier: "pid:\(pid)", isTerminated: false)
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

    private static func liveTargetAXFrontmostProvider(_ pid: pid_t) -> Bool {
        let element = AXUIElementCreateApplication(pid)
        return liveReadBool(element, AXAttributeNames.kAXFrontmostAttribute) == true
    }

    private func isFrontmostTarget(pid: pid_t, bundleIdentifier: String) -> Bool {
        if let frontmost = self.frontmostProvider(),
           self.matchesTarget(frontmost, pid: pid, bundleIdentifier: bundleIdentifier)
        {
            return true
        }
        if let focused = self.focusedApplicationProvider(),
           self.matchesTarget(focused, pid: pid, bundleIdentifier: bundleIdentifier)
        {
            return true
        }
        return self.targetAXFrontmostProvider(pid)
    }

    private func matchesTarget(_ app: AXExposureApp, pid: pid_t, bundleIdentifier: String) -> Bool {
        if app.pid == pid {
            return true
        }
        return app.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }

    private func orderedCandidates(
        _ candidates: [AXExposureApp],
        preferred: AXExposureApp?,
        bundleIdentifier: String) -> [AXExposureApp]
    {
        var seen = Set<pid_t>()
        var deduped: [AXExposureApp] = []
        for candidate in candidates where !seen.contains(candidate.pid) {
            seen.insert(candidate.pid)
            deduped.append(candidate)
        }

        let frontmost = self.frontmostProvider()
        let focused = self.focusedApplicationProvider()

        return deduped.sorted { lhs, rhs in
            let leftRank = self.candidateRank(
                lhs,
                preferred: preferred,
                frontmost: frontmost,
                focused: focused,
                bundleIdentifier: bundleIdentifier)
            let rightRank = self.candidateRank(
                rhs,
                preferred: preferred,
                frontmost: frontmost,
                focused: focused,
                bundleIdentifier: bundleIdentifier)
            if leftRank == rightRank {
                return lhs.pid < rhs.pid
            }
            return leftRank < rightRank
        }
    }

    private func candidateRank(
        _ candidate: AXExposureApp,
        preferred: AXExposureApp?,
        frontmost: AXExposureApp?,
        focused: AXExposureApp?,
        bundleIdentifier: String) -> Int
    {
        if let preferred, preferred.pid == candidate.pid {
            return 0
        }
        if let frontmost, self.matchesTarget(frontmost, pid: candidate.pid, bundleIdentifier: bundleIdentifier) {
            return 1
        }
        if let focused, self.matchesTarget(focused, pid: candidate.pid, bundleIdentifier: bundleIdentifier) {
            return 2
        }

        switch candidate.activationPolicy {
        case .regular:
            return 3
        case .accessory:
            return 4
        case .prohibited:
            return 5
        case .none:
            return 6
        @unknown default:
            return 7
        }
    }
}

struct AXExposureApp: Equatable {
    init(
        pid: pid_t,
        bundleIdentifier: String,
        isTerminated: Bool,
        activationPolicy: NSApplication.ActivationPolicy? = nil)
    {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.isTerminated = isTerminated
        self.activationPolicy = activationPolicy
    }

    init(_ app: NSRunningApplication) {
        self.pid = app.processIdentifier
        self.bundleIdentifier = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        self.isTerminated = app.isTerminated
        self.activationPolicy = app.activationPolicy
    }

    let pid: pid_t
    let bundleIdentifier: String
    let isTerminated: Bool
    let activationPolicy: NSApplication.ActivationPolicy?
}

private enum AXExposureAttributes {
    static let enhancedUI = "AXEnhancedUserInterface"
    static let manualAccessibility = "AXManualAccessibility"
}
