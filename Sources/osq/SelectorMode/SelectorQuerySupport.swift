import Darwin
import Foundation

@MainActor
func selectorQueryInvalidateCaches() {
    LiveSelectorQueryExecutor.invalidateCacheSessionState()
    SelectorActionRefStore.clear()
}

enum OutputCapabilities {
    static var stdoutSupportsANSI: Bool {
        guard isatty(STDOUT_FILENO) == 1 else { return false }
        let term = ProcessInfo.processInfo.environment["TERM"]?.lowercased()
        return term != "dumb"
    }
}
