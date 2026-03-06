import Foundation
import Testing
@testable import osx

@Suite("OXA Hotkey Execution")
@MainActor
struct OXAHotkeyExecutionTests {
    @Test("Execute hotkey dispatches chord to target pid")
    func executeHotkeyDispatchesChordToTargetPid() throws {
        var dispatchedKeys: [String] = []
        var dispatchedPid: pid_t = 0

        try OXAExecutor.executeHotkey(
            OXAHotkeyChord(modifiers: ["cmd", "shift"], baseKey: "a"),
            targetPid: 77,
            dispatch: { keys, pid in
                dispatchedKeys = keys
                dispatchedPid = pid
            })

        #expect(dispatchedKeys == ["cmd", "shift", "a"])
        #expect(dispatchedPid == 77)
    }

    @Test("Execute hotkey normalizes base key aliases")
    func executeHotkeyNormalizesAliases() throws {
        var dispatchedKeys: [String] = []

        try OXAExecutor.executeHotkey(
            OXAHotkeyChord(modifiers: [], baseKey: "down"),
            targetPid: 42,
            dispatch: { keys, _ in
                dispatchedKeys = keys
            })

        #expect(dispatchedKeys == ["down"])
    }

    @Test("Execute text as keys dispatches text to target pid")
    func executeTextAsKeysDispatchesTextToTargetPid() throws {
        var dispatchedText = ""
        var dispatchedPid: pid_t = 0

        try OXAExecutor.executeTextAsKeys(
            "hello",
            targetPid: 123,
            dispatch: { text, pid in
                dispatchedText = text
                dispatchedPid = pid
            })

        #expect(dispatchedText == "hello")
        #expect(dispatchedPid == 123)
    }
}
