import AppKit
import OSXQuery
import ApplicationServices
import Foundation

@MainActor
enum OXAExecutor {
    private enum VisibilityProbeStatus: String {
        case visible
        case notVisible = "not_visible"
        case unknown
    }

    private struct VisibilityProbeTelemetry {
        let targetRef: String
        let status: VisibilityProbeStatus
        let reason: String
        let elementFrame: CGRect?
        let finalFrame: CGRect?
        let clippingAncestorCount: Int
    }

    private struct StatementExecutionResult {
        let readOutput: String?
        let warnings: [String]

        static let none = StatementExecutionResult(readOutput: nil, warnings: [])
    }

    private static let postPreflightDelaySeconds: TimeInterval = 0.1
    private static let appleScriptActivationTimeoutSeconds: TimeInterval = 0.35
    private static let processPollIntervalSeconds: TimeInterval = 0.01
    private static let appLaunchWaitTimeoutSeconds: TimeInterval = 2.0
    private static let windowCreationWaitTimeoutSeconds: TimeInterval = 1.0
    private static let axScrollToVisibleAction = "AXScrollToVisible"
    private static let emitClickVisibilityWarnings = false
    private static let clickVisibilityWarningText = "Warning: target element not visible, click success unknown"
    private static let minimumVisibleDimension: CGFloat = 2.0
    private static let minimumVisibleArea: CGFloat = 16.0
    private static var lastActivationFailureDescription: String?

    static func execute(programSource: String) throws -> String {
        let program = try OXAParser.parse(programSource)
        try self.preflightProgramApplication(program)

        var output: [String] = []
        for (index, statement) in program.statements.enumerated() {
            let result = try self.execute(statement)
            output.append("ok [\(index + 1)] \(self.describe(statement))")
            if let readOutput = result.readOutput {
                output.append("value [\(index + 1)] \(readOutput)")
            }
            output.append(contentsOf: result.warnings)
        }

        if output.isEmpty {
            return "ok actions=0"
        }

        return output.joined(separator: "\n")
    }

    private static func preflightProgramApplication(_ program: OXAProgram) throws {
        let references = self.elementReferencesRequiringActivation(in: program)
        guard !references.isEmpty else {
            return
        }

        var seenReferences = Set<String>()
        var resolvedElements: [Element] = []

        for reference in references {
            if !seenReferences.insert(reference).inserted {
                continue
            }

            let element = try self.resolveElementReference(reference)
            resolvedElements.append(element)
        }

        let allTargetsAreMenuContext = resolvedElements.allSatisfy { self.isMenuContextElement($0) }
        if allTargetsAreMenuContext {
            return
        }

        if let snapshotAppPID = SelectorActionRefStore.snapshotAppPID, snapshotAppPID > 0 {
            if self.ensureApplicationFrontmost(pid: snapshotAppPID) {
                Thread.sleep(forTimeInterval: self.postPreflightDelaySeconds)
            }
            return
        }

        var owningPid: pid_t?
        for element in resolvedElements {
            guard let pid = self.owningPID(for: element) else {
                throw OXAActionError.runtime(
                    "Unable to determine owning app for element reference. Re-run query to refresh refs.")
            }

            if let owningPid, owningPid != pid {
                throw OXAActionError.runtime("Action program references multiple apps. Re-run query and target a single app per action program.")
            }

            owningPid = pid
        }

        guard let owningPid else {
            return
        }

        if self.ensureApplicationFrontmost(pid: owningPid) {
            Thread.sleep(forTimeInterval: self.postPreflightDelaySeconds)
        }
    }

    private static func elementReferencesRequiringActivation(in program: OXAProgram) -> [String] {
        var references: [String] = []

        for statement in program.statements {
            switch statement {
            case let .sendText(_, targetRef),
                 let .sendTextAsKeys(_, targetRef),
                 let .sendClick(targetRef),
                 let .sendRightClick(targetRef),
                 let .sendHotkey(_, targetRef),
                 let .sendScroll(_, targetRef),
                 let .sendScrollIntoView(targetRef):
                references.append(targetRef)
            case let .sendDrag(sourceRef, targetRef):
                references.append(sourceRef)
                references.append(targetRef)
            case .readAttribute, .sleep, .open, .close:
                continue
            }
        }

        return references
    }

    private static func describe(_ statement: OXAStatement) -> String {
        switch statement {
        case let .sendText(text, targetRef):
            return "send text \"\(text)\" to \(targetRef)"
        case let .sendTextAsKeys(text, targetRef):
            return "send text \"\(text)\" as keys to \(targetRef)"
        case let .sendClick(targetRef):
            return "send click to \(targetRef)"
        case let .sendRightClick(targetRef):
            return "send right click to \(targetRef)"
        case let .sendDrag(sourceRef, targetRef):
            return "send drag \(sourceRef) to \(targetRef)"
        case let .sendHotkey(chord, targetRef):
            let hotkey = (chord.modifiers + [chord.baseKey]).joined(separator: "+")
            return "send hotkey \(hotkey) to \(targetRef)"
        case let .sendScroll(direction, targetRef):
            return "send scroll \(direction.rawValue) to \(targetRef)"
        case let .sendScrollIntoView(targetRef):
            return "send scroll to \(targetRef)"
        case let .readAttribute(attributeName, targetRef):
            return "read \(attributeName) from \(targetRef)"
        case let .sleep(milliseconds):
            return "sleep \(milliseconds)"
        case let .open(app):
            return "open \"\(app)\""
        case let .close(app):
            return "close \"\(app)\""
        }
    }

    private static func execute(_ statement: OXAStatement) throws -> StatementExecutionResult {
        switch statement {
        case let .sendText(text, targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            guard self.focusTargetForInput(target) else {
                throw OXAActionError.runtime("Failed to focus target element \(targetRef) for text input.")
            }
            guard target.setValue(text, forAttribute: AXAttributeNames.kAXValueAttribute) else {
                throw OXAActionError.runtime("Failed to set AXValue on target element \(targetRef).")
            }
            return .none

        case let .sendTextAsKeys(text, targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            guard self.focusTargetForInput(target) else {
                throw OXAActionError.runtime("Failed to focus target element \(targetRef) for text input.")
            }

            let targetPid = SelectorActionRefStore.snapshotAppPID ?? self.owningPID(for: target)
            guard let targetPid else {
                throw OXAActionError.runtime("Unable to determine owning app for text input target \(targetRef).")
            }
            try self.executeTextAsKeys(text, targetPid: targetPid)
            return .none

        case let .sendClick(targetRef):
            let target = try self.resolveElementReference(targetRef)
            let warnings: [String]
            if self.emitClickVisibilityWarnings {
                let visibilityProbe = self.visibilityProbe(for: targetRef)
                warnings = self.warningFromVisibilityProbe(visibilityProbe).map { [$0] } ?? []
            } else {
                warnings = []
            }
            self.preflightTargetElement(target)
            try self.clickElementCenter(target)
            return StatementExecutionResult(
                readOutput: nil,
                warnings: warnings)

        case let .sendRightClick(targetRef):
            let target = try self.resolveElementReference(targetRef)
            let warnings: [String]
            if self.emitClickVisibilityWarnings {
                let visibilityProbe = self.visibilityProbe(for: targetRef)
                warnings = self.warningFromVisibilityProbe(visibilityProbe).map { [$0] } ?? []
            } else {
                warnings = []
            }
            self.preflightTargetElement(target)
            try self.clickElementCenter(target, button: .right)
            return StatementExecutionResult(
                readOutput: nil,
                warnings: warnings)

        case let .sendDrag(sourceRef, targetRef):
            let source = try self.resolveElementReference(sourceRef)
            let destination = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(source)

            guard let sourceCenter = self.centerPoint(for: source) else {
                throw OXAActionError.runtime("Unable to resolve frame for drag source \(sourceRef).")
            }
            guard let destinationCenter = self.centerPoint(for: destination) else {
                throw OXAActionError.runtime("Unable to resolve frame for drag target \(targetRef).")
            }

            try InputDriver.drag(from: sourceCenter, to: destinationCenter, steps: 20, interStepDelay: 0.005)
            return .none

        case let .sendHotkey(chord, targetRef):
            let target = try self.resolveElementReference(targetRef)
            let targetPid = SelectorActionRefStore.snapshotAppPID ?? self.owningPID(for: target)
            guard let targetPid else {
                throw OXAActionError.runtime("Unable to determine owning app for hotkey target \(targetRef).")
            }
            try self.executeHotkey(chord, targetPid: targetPid)
            return .none

        case let .sendScroll(direction, targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            guard let center = self.centerPoint(for: target) else {
                throw OXAActionError.runtime("Unable to resolve frame for scroll target \(targetRef).")
            }
            try self.scroll(direction: direction, at: center)
            return .none

        case let .sendScrollIntoView(targetRef):
            let target = try self.resolveElementReference(targetRef)
            self.preflightTargetElement(target)
            _ = try self.scrollElementIntoView(target, targetRef: targetRef)
            return .none

        case let .readAttribute(attributeName, targetRef):
            let target = try self.resolveElementReference(targetRef)
            guard let value = self.readAttributeValue(from: target, attributeName: attributeName) else {
                throw OXAActionError.runtime(
                    "Attribute '\(attributeName)' has no readable value on target \(targetRef).")
            }
            return StatementExecutionResult(readOutput: value, warnings: [])

        case let .sleep(milliseconds):
            guard milliseconds >= 0 else {
                throw OXAActionError.runtime("Sleep duration must be non-negative.")
            }
            Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
            return .none

        case let .open(app):
            try self.openApplication(app)
            selectorQueryInvalidateCaches()
            return .none

        case let .close(app):
            try self.closeApplication(app)
            selectorQueryInvalidateCaches()
            return .none
        }
    }

    private static func resolveElementReference(_ reference: String) throws -> Element {
        guard SelectorActionRefStore.hasSnapshot else {
            throw OXAActionError.noSnapshot
        }

        guard let element = SelectorActionRefStore.element(for: reference) else {
            throw OXAActionError.unknownElementReference(reference)
        }

        return element
    }

    private static func warningFromVisibilityProbe(_ telemetry: VisibilityProbeTelemetry) -> String? {
        telemetry.status == .visible ? nil : self.clickVisibilityWarningText
    }

    private static func visibilityProbe(for reference: String) -> VisibilityProbeTelemetry {
        let normalizedReference = reference.lowercased()
        guard let elementFrame = SelectorActionRefStore.frame(for: normalizedReference) else {
            return VisibilityProbeTelemetry(
                targetRef: normalizedReference,
                status: .unknown,
                reason: "missing_target_frame",
                elementFrame: nil,
                finalFrame: nil,
                clippingAncestorCount: 0)
        }
        guard self.hasPositiveArea(elementFrame) else {
            return VisibilityProbeTelemetry(
                targetRef: normalizedReference,
                status: .notVisible,
                reason: "non_positive_target_frame",
                elementFrame: elementFrame,
                finalFrame: elementFrame,
                clippingAncestorCount: 0)
        }

        if !self.meetsMinimumVisibleSize(elementFrame) {
            return VisibilityProbeTelemetry(
                targetRef: normalizedReference,
                status: .unknown,
                reason: "target_frame_below_minimum_size",
                elementFrame: elementFrame,
                finalFrame: elementFrame,
                clippingAncestorCount: 0)
        }

        var visibleRect = elementFrame
        var currentReference = normalizedReference
        var depth = 0
        var clippingAncestorCount = 0

        while depth < 512 {
            guard let parentReference = SelectorActionRefStore.parentReference(for: currentReference) else {
                break
            }
            currentReference = parentReference
            depth += 1

            guard self.isClippingRole(SelectorActionRefStore.role(for: currentReference)) else {
                continue
            }
            clippingAncestorCount += 1

            guard let parentFrame = SelectorActionRefStore.frame(for: currentReference) else {
                return VisibilityProbeTelemetry(
                    targetRef: normalizedReference,
                    status: .unknown,
                    reason: "missing_clipping_frame:\(currentReference)",
                    elementFrame: elementFrame,
                    finalFrame: visibleRect,
                    clippingAncestorCount: clippingAncestorCount)
            }
            guard self.hasPositiveArea(parentFrame) else {
                return VisibilityProbeTelemetry(
                    targetRef: normalizedReference,
                    status: .notVisible,
                    reason: "non_positive_clipping_frame:\(currentReference)",
                    elementFrame: elementFrame,
                    finalFrame: parentFrame,
                    clippingAncestorCount: clippingAncestorCount)
            }

            visibleRect = visibleRect.intersection(parentFrame)
            if visibleRect.isNull || visibleRect.isEmpty || !self.hasPositiveArea(visibleRect) {
                return VisibilityProbeTelemetry(
                    targetRef: normalizedReference,
                    status: .notVisible,
                    reason: "clipped_empty_by:\(currentReference)",
                    elementFrame: elementFrame,
                    finalFrame: nil,
                    clippingAncestorCount: clippingAncestorCount)
            }
        }

        if clippingAncestorCount == 0 {
            return VisibilityProbeTelemetry(
                targetRef: normalizedReference,
                status: .unknown,
                reason: "no_clipping_ancestors",
                elementFrame: elementFrame,
                finalFrame: visibleRect,
                clippingAncestorCount: 0)
        }

        if let screenViewport = self.globalScreenViewport() {
            visibleRect = visibleRect.intersection(screenViewport)
            if visibleRect.isNull || visibleRect.isEmpty || !self.hasPositiveArea(visibleRect) {
                return VisibilityProbeTelemetry(
                    targetRef: normalizedReference,
                    status: .notVisible,
                    reason: "clipped_by_screen_viewport",
                    elementFrame: elementFrame,
                    finalFrame: nil,
                    clippingAncestorCount: clippingAncestorCount)
            }
        }

        if !self.meetsMinimumVisibleSize(visibleRect) {
            return VisibilityProbeTelemetry(
                targetRef: normalizedReference,
                status: .unknown,
                reason: "final_frame_below_minimum_size",
                elementFrame: elementFrame,
                finalFrame: visibleRect,
                clippingAncestorCount: clippingAncestorCount)
        }

        return VisibilityProbeTelemetry(
            targetRef: normalizedReference,
            status: .visible,
            reason: "visible_after_clip_intersections",
            elementFrame: elementFrame,
            finalFrame: visibleRect,
            clippingAncestorCount: clippingAncestorCount)
    }

    private static func isClippingRole(_ role: String?) -> Bool {
        role == AXRoleNames.kAXScrollAreaRole ||
            role == AXRoleNames.kAXWindowRole ||
            role == AXRoleNames.kAXWebAreaRole ||
            role == AXRoleNames.kAXLayoutAreaRole ||
            role == AXRoleNames.kAXSplitGroupRole
    }

    private static func hasPositiveArea(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0
    }

    private static func meetsMinimumVisibleSize(_ rect: CGRect) -> Bool {
        rect.width >= self.minimumVisibleDimension &&
            rect.height >= self.minimumVisibleDimension &&
            (rect.width * rect.height) >= self.minimumVisibleArea
    }

    private static func globalScreenViewport() -> CGRect? {
        let frames = NSScreen.screens.map(\.frame)
        guard let first = frames.first else {
            return nil
        }

        return frames.dropFirst().reduce(first) { partialResult, frame in
            partialResult.union(frame)
        }
    }

    private static func preflightTargetElement(_ element: Element) {
        if self.isMenuContextElement(element) {
            return
        }

        if let window = self.owningWindow(for: element) {
            _ = AXUIElementSetAttributeValue(
                window.underlyingElement,
                AXAttributeNames.kAXMainAttribute as CFString,
                kCFBooleanTrue)
            _ = window.focusWindow()
        }

        Thread.sleep(forTimeInterval: self.postPreflightDelaySeconds)
    }

    private static func isMenuContextElement(_ element: Element) -> Bool {
        var current: Element? = element
        var depth = 0

        while let candidate = current, depth < 256 {
            if self.isMenuRole(candidate.role()) {
                return true
            }

            current = candidate.parent()
            depth += 1
        }

        return false
    }

    private static func isMenuRole(_ role: String?) -> Bool {
        guard let role else {
            return false
        }

        return role == AXRoleNames.kAXMenuRole || role == AXRoleNames.kAXMenuItemRole
    }

    static func ensureApplicationFrontmost(pid: pid_t, targetBundleIdentifier: String? = nil) -> Bool {
        self.lastActivationFailureDescription = nil
        return self.liveActivatePid(pid)
    }

    static func ensureApplicationFrontmost(
        pid: pid_t,
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        now: () -> Date,
        sleep: (TimeInterval) -> Void,
        activatePid: (pid_t) -> Bool,
        frontmostPidProvider: () -> pid_t?,
        focusedPidProvider: () -> pid_t?,
        axFrontmostProvider: (pid_t) -> Bool,
        targetBundleIdentifier: String? = nil,
        frontmostBundleIdentifierProvider: () -> String? = { nil },
        focusedBundleIdentifierProvider: () -> String? = { nil }) -> Bool
    {
        _ = timeout
        _ = pollInterval
        _ = now
        _ = sleep
        _ = frontmostPidProvider
        _ = focusedPidProvider
        _ = axFrontmostProvider
        _ = targetBundleIdentifier
        _ = frontmostBundleIdentifierProvider
        _ = focusedBundleIdentifierProvider
        return activatePid(pid)
    }

    private static func liveActivatePid(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            self.lastActivationFailureDescription = "No running app found for pid \(pid)."
            return false
        }

        if app.isHidden {
            app.unhide()
        }

        if self.activateViaAppleScript(app) {
            return true
        }

        if self.activateViaRunningApplication(app) {
            self.lastActivationFailureDescription = nil
            return true
        }

        return false
    }

    private static func activateViaAppleScript(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
            self.lastActivationFailureDescription = "Target app has no bundle identifier."
            return false
        }

        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(escapedBundleIdentifier)\" to activate"]
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            self.lastActivationFailureDescription = "AppleScript activation failed to launch: \(error.localizedDescription)"
            return false
        }

        guard self.waitForProcessExit(
            process,
            timeout: self.appleScriptActivationTimeoutSeconds,
            pollInterval: self.processPollIntervalSeconds)
        else {
            self.lastActivationFailureDescription = "AppleScript activation timed out."
            return false
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stderr, !stderr.isEmpty {
                self.lastActivationFailureDescription = "AppleScript activation failed (exit \(process.terminationStatus)): \(stderr)"
            } else {
                self.lastActivationFailureDescription = "AppleScript activation failed (exit \(process.terminationStatus))."
            }
            return false
        }

        self.lastActivationFailureDescription = nil
        return true
    }

    private static func activateViaRunningApplication(_ app: NSRunningApplication) -> Bool {
        let options: NSApplication.ActivationOptions = [.activateAllWindows, .activateIgnoringOtherApps]
        guard app.activate(options: options) else {
            let previous = self.lastActivationFailureDescription
            if let previous, !previous.isEmpty {
                self.lastActivationFailureDescription =
                    "\(previous) Fallback activation via NSRunningApplication.activate failed."
            } else {
                self.lastActivationFailureDescription =
                    "Fallback activation via NSRunningApplication.activate failed."
            }
            return false
        }
        return true
    }

    private static func waitForProcessExit(
        _ process: Process,
        timeout: TimeInterval,
        pollInterval: TimeInterval) -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
        }

        guard process.isRunning else {
            return true
        }

        process.terminate()
        for _ in 0..<10 where process.isRunning {
            Thread.sleep(forTimeInterval: pollInterval)
        }

        return !process.isRunning
    }

    private static func owningPID(for element: Element) -> pid_t? {
        if let pid = self.axPid(for: element), pid > 0 {
            return pid
        }

        var current = element.parent()
        var depth = 0
        while let candidate = current, depth < 256 {
            if let pid = self.axPid(for: candidate), pid > 0 {
                return pid
            }
            current = candidate.parent()
            depth += 1
        }

        return nil
    }

    private static func axPid(for element: Element) -> pid_t? {
        if let pid = element.pid(), pid > 0 {
            return pid
        }

        var pid: pid_t = 0
        let status = AXUIElementGetPid(element.underlyingElement, &pid)
        guard status == .success, pid > 0 else {
            return nil
        }
        return pid
    }

    private static func owningWindow(for element: Element) -> Element? {
        if element.role() == AXRoleNames.kAXWindowRole {
            return element
        }

        if let windowUIElement: AXUIElement = element.attribute(.window) {
            return Element(windowUIElement)
        }

        var current = element.parent()
        var depth = 0
        while let candidate = current, depth < 256 {
            if candidate.role() == AXRoleNames.kAXWindowRole {
                return candidate
            }
            current = candidate.parent()
            depth += 1
        }

        return nil
    }

    private static func centerPoint(for element: Element) -> CGPoint? {
        guard let frame = element.frame() else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func clickPoint(for element: Element) -> CGPoint? {
        guard let elementFrame = element.frame() else {
            return nil
        }

        if element.role() == AXRoleNames.kAXLinkRole,
           let descendantPoint = self.deepestDescendantPointInBounds(
               root: element,
               bounds: elementFrame)
        {
            return descendantPoint
        }

        return CGPoint(x: elementFrame.midX, y: elementFrame.midY)
    }

    private static func deepestDescendantPointInBounds(root: Element, bounds: CGRect) -> CGPoint? {
        var bestPoint: CGPoint?
        var bestDepth = -1
        var visited: Set<Element> = [root]

        func visit(_ element: Element, depth: Int) {
            guard depth < 256 else {
                return
            }

            guard let children = element.children(strict: false, includeApplicationExtras: false), !children.isEmpty else {
                return
            }

            for child in children {
                if visited.contains(child) {
                    continue
                }
                visited.insert(child)

                if let frame = child.frame(),
                   frame.width > 0,
                   frame.height > 0
                {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    if bounds.contains(center), depth > bestDepth {
                        bestDepth = depth
                        bestPoint = center
                    }
                }

                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 1)
        return bestPoint
    }

    private static func clickElementCenter(_ element: Element, button: MouseButton = .left) throws {
        guard let center = self.clickPoint(for: element) else {
            throw OXAActionError.runtime("Unable to resolve element frame for click.")
        }
        try self.movePointerToElementCenter(center)
        try InputDriver.click(at: center, button: button)
    }

    private static func movePointerToElementCenter(_ point: CGPoint) throws {
        try InputDriver.move(to: point)

        if let current = InputDriver.currentLocation() {
            let deltaX = current.x - point.x
            let deltaY = current.y - point.y
            if (deltaX * deltaX + deltaY * deltaY) <= 1 {
                return
            }
        }

        _ = CGWarpMouseCursorPosition(point)
    }

    private static func focusTargetForInput(_ element: Element) -> Bool {
        if element.setValue(true, forAttribute: AXAttributeNames.kAXFocusedAttribute) {
            return true
        }

        if element.press() {
            return true
        }

        do {
            try self.clickElementCenter(element)
            return true
        } catch {
            return false
        }
    }

    static func executeHotkey(
        _ chord: OXAHotkeyChord,
        targetPid: pid_t,
        dispatch: ([String], pid_t) throws -> Void = { keys, pid in
            try InputDriver.hotkey(keys: keys, targetPid: pid, holdDuration: 0)
        }) throws
    {
        let keys = chord.modifiers + [self.driverKeyName(for: chord.baseKey)]
        try dispatch(keys, targetPid)
    }

    static func executeTextAsKeys(
        _ text: String,
        targetPid: pid_t,
        dispatch: (String, pid_t) throws -> Void = { value, pid in
            try InputDriver.type(value, targetPid: pid, delayPerCharacter: 0)
        }) throws
    {
        try dispatch(text, targetPid)
    }

    private static func driverKeyName(for baseKey: String) -> String {
        switch baseKey {
        case "page_up":
            return "pageup"
        case "page_down":
            return "pagedown"
        case "backspace":
            return "delete"
        default:
            return baseKey
        }
    }

    private static func scroll(direction: OXAScrollDirection, at point: CGPoint) throws {
        let amount: Double = 80
        let deltas = self.scrollDeltas(
            for: direction,
            amount: amount,
            naturalScrollEnabled: self.isNaturalScrollEnabled())
        try InputDriver.scroll(deltaX: deltas.deltaX, deltaY: deltas.deltaY, at: point)
    }

    private static func scrollElementIntoView(_ element: Element, targetRef: String) throws -> String? {
        if let actions = element.supportedActions(), !actions.contains(self.axScrollToVisibleAction) {
            throw OXAActionError.runtime(
                "AXScrollToVisible is not supported for \(targetRef).")
        }

        do {
            _ = try element.performAction(self.axScrollToVisibleAction)
            return nil
        } catch {
            throw OXAActionError.runtime(
                "AXScrollToVisible failed for \(targetRef): \(String(describing: error))")
        }
    }

    static func scrollDeltas(
        for direction: OXAScrollDirection,
        amount: Double,
        naturalScrollEnabled: Bool) -> (deltaX: Double, deltaY: Double)
    {
        let verticalUnit = naturalScrollEnabled ? -amount : amount
        let horizontalUnit = naturalScrollEnabled ? -amount : amount

        switch direction {
        case .up:
            return (0, verticalUnit)
        case .down:
            return (0, -verticalUnit)
        case .left:
            return (horizontalUnit, 0)
        case .right:
            return (-horizontalUnit, 0)
        }
    }

    private static func isNaturalScrollEnabled() -> Bool {
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let value = domain?["com.apple.swipescrolldirection"] as? Bool {
            return value
        }

        return true
    }

    private static func readAttributeValue(from element: Element, attributeName: String) -> String? {
        let canonicalName = self.canonicalAttributeName(attributeName)

        switch canonicalName {
        case AXAttributeNames.kAXRoleAttribute:
            return element.role()
        case AXAttributeNames.kAXSubroleAttribute:
            return element.subrole()
        case AXAttributeNames.kAXPIDAttribute:
            return element.pid().map(String.init)
        case AXAttributeNames.kAXTitleAttribute:
            return element.title()
        case AXAttributeNames.kAXDescriptionAttribute:
            return element.descriptionText()
        case AXAttributeNames.kAXHelpAttribute:
            return element.help()
        case AXAttributeNames.kAXIdentifierAttribute:
            return element.identifier()
        case AXAttributeNames.kAXRoleDescriptionAttribute:
            return element.roleDescription()
        case AXAttributeNames.kAXPlaceholderValueAttribute:
            return element.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute))
        case AXAttributeNames.kAXEnabledAttribute:
            return element.isEnabled().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXFocusedAttribute:
            return element.isFocused().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXValueAttribute:
            return SelectorMatchSummary.stringify(element.value())
        case AXMiscConstants.computedNameAttributeKey:
            return element.computedName()
        case AXMiscConstants.isIgnoredAttributeKey:
            return element.isIgnored() ? "true" : "false"
        default:
            break
        }

        guard let rawValue: Any = element.attribute(Attribute<Any>(canonicalName)) else {
            return nil
        }
        return SelectorMatchSummary.stringify(rawValue)
    }

    private static func canonicalAttributeName(_ name: String) -> String {
        PathUtils.attributeKeyMappings[name.lowercased()] ?? name
    }

    private static func openApplication(_ applicationIdentifier: String) throws {
        if let runningApp = self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated }) {
            let targetBundleIdentifier = runningApp.bundleIdentifier ??
                (self.looksLikeBundleIdentifier(applicationIdentifier) ? applicationIdentifier : nil)
            guard self.ensureApplicationFrontmost(
                pid: runningApp.processIdentifier,
                targetBundleIdentifier: targetBundleIdentifier)
            else {
                let details = self.lastActivationFailureDescription.map { " \($0)" } ?? ""
                throw OXAActionError.runtime("Failed to activate '\(applicationIdentifier)'.\(details)")
            }

            if !self.applicationHasAnyWindow(runningApp) {
                _ = self.reopenViaAppleScript(runningApp)
                _ = self.waitForAnyWindow(in: runningApp, timeout: self.windowCreationWaitTimeoutSeconds)
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        if self.looksLikeBundleIdentifier(applicationIdentifier) {
            process.arguments = ["-b", applicationIdentifier]
        } else {
            process.arguments = ["-a", applicationIdentifier]
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw OXAActionError.runtime("Failed to launch '\(applicationIdentifier)': \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            throw OXAActionError.runtime("Failed to launch '\(applicationIdentifier)' (exit code \(process.terminationStatus)).")
        }

        guard let launchedApp = self.waitForRunningApplication(
            matching: applicationIdentifier,
            timeout: self.appLaunchWaitTimeoutSeconds)
        else {
            return
        }

        let targetBundleIdentifier = launchedApp.bundleIdentifier ??
            (self.looksLikeBundleIdentifier(applicationIdentifier) ? applicationIdentifier : nil)
        guard self.ensureApplicationFrontmost(
            pid: launchedApp.processIdentifier,
            targetBundleIdentifier: targetBundleIdentifier)
        else {
            let details = self.lastActivationFailureDescription.map { " \($0)" } ?? ""
            throw OXAActionError.runtime("Launched '\(applicationIdentifier)' but failed to activate it.\(details)")
        }

        if !self.applicationHasAnyWindow(launchedApp) {
            _ = self.reopenViaAppleScript(launchedApp)
            _ = self.waitForAnyWindow(in: launchedApp, timeout: self.windowCreationWaitTimeoutSeconds)
        }
    }

    private static func closeApplication(_ applicationIdentifier: String) throws {
        let matches = self.runningApplications(matching: applicationIdentifier)
        guard !matches.isEmpty else {
            return
        }

        for application in matches {
            if !application.terminate() {
                _ = application.forceTerminate()
                continue
            }

            for _ in 0..<20 where !application.isTerminated {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if !application.isTerminated {
                _ = application.forceTerminate()
            }
        }
    }

    private static func reopenViaAppleScript(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return false
        }

        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(escapedBundleIdentifier)\" to reopen"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }

        guard self.waitForProcessExit(
            process,
            timeout: self.appleScriptActivationTimeoutSeconds,
            pollInterval: self.processPollIntervalSeconds)
        else {
            return false
        }

        return process.terminationStatus == 0
    }

    private static func applicationHasAnyWindow(_ app: NSRunningApplication) -> Bool {
        guard let appElement = getApplicationElement(for: app.processIdentifier) else {
            return false
        }
        guard let windows = appElement.windows() else {
            return false
        }
        return !windows.isEmpty
    }

    private static func waitForAnyWindow(in app: NSRunningApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if self.applicationHasAnyWindow(app) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return self.applicationHasAnyWindow(app)
    }

    private static func waitForRunningApplication(
        matching applicationIdentifier: String,
        timeout: TimeInterval) -> NSRunningApplication?
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated }) {
                return app
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated })
    }

    private static func runningApplications(matching applicationIdentifier: String) -> [NSRunningApplication] {
        let normalizedIdentifier = applicationIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if self.looksLikeBundleIdentifier(applicationIdentifier) {
            return NSRunningApplication.runningApplications(withBundleIdentifier: applicationIdentifier)
        }

        return NSWorkspace.shared.runningApplications.filter { app in
            guard let name = app.localizedName?.lowercased() else { return false }
            return name == normalizedIdentifier
        }
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(".") && !trimmed.contains(" ")
    }
}
