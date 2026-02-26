import Testing
@testable import axorc

@Suite("Interactive Selector Request Builder")
struct InteractiveSelectorRequestBuilderTests {
    @Test("Returns nil when interactive flag is absent")
    func noInteractiveFlagReturnsNil() throws {
        let request = try InteractiveSelectorRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            interactive: false,
            hasStructuredInput: false)

        #expect(request == nil)
    }

    @Test("Builds request with trimmed app and selector")
    func buildsRequest() throws {
        let request = try InteractiveSelectorRequestBuilder.build(
            app: "  com.apple.TextEdit ",
            selector: "  AXButton  ",
            maxDepth: nil,
            interactive: true,
            hasStructuredInput: false)

        #expect(request?.appIdentifier == "com.apple.TextEdit")
        #expect(request?.initialSelector == "AXButton")
        #expect(request?.maxDepth == Int.max)
        #expect(request?.refocusTerminalAfterInteractions == false)
    }

    @Test("Builds request with terminal refocus enabled")
    func buildsRequestWithTerminalRefocusEnabled() throws {
        let request = try InteractiveSelectorRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            interactive: true,
            refocusTerminalAfterInteractions: true,
            hasStructuredInput: false)

        #expect(request?.refocusTerminalAfterInteractions == true)
    }

    @Test("Builds request with nil initial selector when selector is empty")
    func buildsRequestWithEmptySelector() throws {
        let request = try InteractiveSelectorRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "   ",
            maxDepth: 7,
            interactive: true,
            hasStructuredInput: false)

        #expect(request?.appIdentifier == "com.apple.TextEdit")
        #expect(request?.initialSelector == nil)
        #expect(request?.maxDepth == 7)
    }

    @Test("Rejects missing application")
    func rejectsMissingApplication() {
        do {
            _ = try InteractiveSelectorRequestBuilder.build(
                app: nil,
                selector: "AXButton",
                maxDepth: nil,
                interactive: true,
                hasStructuredInput: false)
            Issue.record("Expected build failure")
        } catch let error as InteractiveSelectorCLIError {
            #expect(error == .missingApplication)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects structured input mixed with interactive mode")
    func rejectsMixedInputModes() {
        do {
            _ = try InteractiveSelectorRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                interactive: true,
                hasStructuredInput: true)
            Issue.record("Expected build failure")
        } catch let error as InteractiveSelectorCLIError {
            #expect(error == .conflictingInputModes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects invalid max depth")
    func rejectsInvalidMaxDepth() {
        do {
            _ = try InteractiveSelectorRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: 0,
                interactive: true,
                hasStructuredInput: false)
            Issue.record("Expected build failure")
        } catch let error as InteractiveSelectorCLIError {
            #expect(error == .invalidMaxDepth(0))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
