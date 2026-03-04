import Foundation

enum OXAActionError: LocalizedError {
    case parse(String)
    case noSnapshot
    case unknownElementReference(String)
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case let .parse(message):
            "Invalid OXA program: \(message)"
        case .noSnapshot:
            "No cached query snapshot available. Run a selector query through the cache daemon first (query+)."
        case let .unknownElementReference(reference):
            "Unknown element reference '\(reference)'. Re-run query to refresh refs."
        case let .runtime(message):
            message
        }
    }
}

struct OXAHotkeyChord: Equatable {
    let modifiers: [String]
    let baseKey: String
}

enum OXAScrollDirection: String, Equatable {
    case up
    case down
    case left
    case right
}

enum OXAStatement: Equatable {
    case sendText(text: String, targetRef: String)
    case sendTextAsKeys(text: String, targetRef: String)
    case sendClick(targetRef: String)
    case sendRightClick(targetRef: String)
    case sendDrag(sourceRef: String, targetRef: String)
    case sendHotkey(chord: OXAHotkeyChord, targetRef: String)
    case sendScroll(direction: OXAScrollDirection, targetRef: String)
    case sendScrollIntoView(targetRef: String)
    case readAttribute(attributeName: String, targetRef: String)
    case sleep(milliseconds: Int)
    case open(app: String)
    case close(app: String)
}

struct OXAProgram: Equatable {
    let statements: [OXAStatement]
}
