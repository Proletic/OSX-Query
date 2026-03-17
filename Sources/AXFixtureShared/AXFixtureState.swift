import Foundation

public enum AXFixtureEnvironment {
    public static let readyFileKey = "AX_FIXTURE_READY_FILE"
    public static let stateFileKey = "AX_FIXTURE_STATE_FILE"
}

public enum AXFixtureUI {
    public static let appName = "AXFixtureApp"
    public static let windowTitle = "AXFixtureApp Main Window"
    public static let incrementButtonTitle = "Increment Counter"
    public static let focusButtonTitle = "Focus Input"
    public static let countLabelPrefix = "Count: "
    public static let echoLabelPrefix = "Echo: "
    public static let eventLabelPrefix = "Last Event: "
    public static let textFieldSeedValue = ""
}

public struct AXFixtureState: Codable, Equatable, Sendable {
    public init(counter: Int = 0, textValue: String = AXFixtureUI.textFieldSeedValue, lastEvent: String = "launched") {
        self.counter = counter
        self.textValue = textValue
        self.lastEvent = lastEvent
    }

    public var counter: Int
    public var textValue: String
    public var lastEvent: String
}
