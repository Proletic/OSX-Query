import AXFixtureShared
import AppKit
import Foundation

@main
@MainActor
struct AXFixtureAppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = FixtureAppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var stateStore = FixtureStateStore()

    private var window: NSWindow!
    private var countLabel: NSTextField!
    private var echoLabel: NSTextField!
    private var eventLabel: NSTextField!
    private var inputField: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.window = self.makeWindow()
        self.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.render()
        self.stateStore.markReady()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func controlTextDidChange(_ notification: Notification) {
        self.stateStore.withState {
            $0.textValue = self.inputField.stringValue
            $0.lastEvent = "typed:\(self.inputField.stringValue)"
        }
        self.render()
    }

    @objc
    private func incrementCounter(_ sender: NSButton) {
        self.stateStore.withState {
            $0.counter += 1
            $0.lastEvent = "increment"
        }
        self.render()
    }

    @objc
    private func focusInput(_ sender: NSButton) {
        self.window.makeFirstResponder(self.inputField)
        self.stateStore.withState {
            $0.lastEvent = "focus-input"
        }
        self.render()
    }

    private func render() {
        let state = self.stateStore.currentState
        self.countLabel.stringValue = "\(AXFixtureUI.countLabelPrefix)\(state.counter)"
        self.echoLabel.stringValue = "\(AXFixtureUI.echoLabelPrefix)\(state.textValue)"
        self.eventLabel.stringValue = "\(AXFixtureUI.eventLabelPrefix)\(state.lastEvent)"
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 240, y: 240, width: 460, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = AXFixtureUI.windowTitle
        window.center()
        window.contentView = self.makeContentView()
        return window
    }

    private func makeContentView() -> NSView {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 280))

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let controlsGroup = self.makeControlsGroup()
        let statusGroup = self.makeStatusGroup()

        rootStack.addArrangedSubview(controlsGroup)
        rootStack.addArrangedSubview(statusGroup)
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])

        return contentView
    }

    private func makeControlsGroup() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setAccessibilityIdentifier("fixture.controls")

        let title = self.makeLabel("Fixture Controls")
        title.font = .boldSystemFont(ofSize: 16)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .centerY

        let incrementButton = NSButton(title: AXFixtureUI.incrementButtonTitle, target: self, action: #selector(incrementCounter(_:)))
        incrementButton.bezelStyle = .rounded
        incrementButton.setAccessibilityIdentifier("fixture.increment")

        let focusButton = NSButton(title: AXFixtureUI.focusButtonTitle, target: self, action: #selector(focusInput(_:)))
        focusButton.bezelStyle = .rounded
        focusButton.setAccessibilityIdentifier("fixture.focus-input")

        buttonRow.addArrangedSubview(incrementButton)
        buttonRow.addArrangedSubview(focusButton)

        self.inputField = NSTextField(string: AXFixtureUI.textFieldSeedValue)
        self.inputField.delegate = self
        self.inputField.placeholderString = "Type here"
        self.inputField.setAccessibilityIdentifier("fixture.input")
        self.inputField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(buttonRow)
        stack.addArrangedSubview(self.inputField)
        return stack
    }

    private func makeStatusGroup() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setAccessibilityIdentifier("fixture.status")

        let title = self.makeLabel("Fixture Status")
        title.font = .boldSystemFont(ofSize: 16)

        self.countLabel = self.makeLabel("")
        self.countLabel.setAccessibilityIdentifier("fixture.count")

        self.echoLabel = self.makeLabel("")
        self.echoLabel.setAccessibilityIdentifier("fixture.echo")

        self.eventLabel = self.makeLabel("")
        self.eventLabel.setAccessibilityIdentifier("fixture.event")

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(self.countLabel)
        stack.addArrangedSubview(self.echoLabel)
        stack.addArrangedSubview(self.eventLabel)
        return stack
    }

    private func makeLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }
}

private struct FixtureStateStore {
    private let stateFileURL: URL?
    private let readyFileURL: URL?
    private(set) var currentState = AXFixtureState()

    init(processInfo: ProcessInfo = .processInfo) {
        let environment = processInfo.environment
        self.stateFileURL = environment[AXFixtureEnvironment.stateFileKey].map { URL(fileURLWithPath: $0) }
        self.readyFileURL = environment[AXFixtureEnvironment.readyFileKey].map { URL(fileURLWithPath: $0) }
    }

    mutating func withState(_ update: (inout AXFixtureState) -> Void) {
        update(&self.currentState)
        self.persistState()
    }

    func markReady() {
        self.persistState()
        guard let readyFileURL else { return }
        FileManager.default.createFile(atPath: readyFileURL.path, contents: Data(), attributes: nil)
    }

    private func persistState() {
        guard let stateFileURL else { return }
        do {
            let data = try JSONEncoder().encode(self.currentState)
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            fputs("AXFixtureApp failed to persist state: \(error)\n", stderr)
        }
    }
}
