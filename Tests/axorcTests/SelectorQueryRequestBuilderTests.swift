import Testing
@testable import axorc

@Suite("Selector Query Request Builder")
struct SelectorQueryRequestBuilderTests {
    @Test("Returns nil when selector mode flags are absent")
    func noSelectorModeFlagsReturnsNil() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: nil,
            selector: nil,
            maxDepth: nil,
            limit: nil,
            noColor: false,
            showPath: false,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request == nil)
    }

    @Test("Builds request with defaults and trimmed values")
    func buildsDefaultRequest() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "  com.apple.TextEdit  ",
            selector: "  AXButton  ",
            maxDepth: nil,
            limit: nil,
            noColor: false,
            showPath: false,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request != nil)
        #expect(request?.appIdentifier == "com.apple.TextEdit")
        #expect(request?.selector == "AXButton")
        #expect(request?.maxDepth == Int.max)
        #expect(request?.limit == 50)
        #expect(request?.colorEnabled == true)
        #expect(request?.showPath == false)
        #expect(request?.showNameSource == false)
    }

    @Test("Uses explicit max depth when provided")
    func usesExplicitMaxDepth() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: 7,
            limit: nil,
            noColor: false,
            showPath: false,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.maxDepth == 7)
    }

    @Test("Disables color when stdout is not ANSI-capable")
    func disablesColorForNonAnsiOutput() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            limit: nil,
            noColor: false,
            showPath: false,
            hasStructuredInput: false,
            stdoutSupportsANSI: false)

        #expect(request?.colorEnabled == false)
    }

    @Test("Disables color when --no-color is set")
    func disablesColorWhenNoColorFlagSet() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            limit: nil,
            noColor: true,
            showPath: false,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.colorEnabled == false)
    }

    @Test("Enables path output when --show-path is set")
    func enablesPathOutput() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            limit: nil,
            noColor: true,
            showPath: true,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.showPath == true)
    }

    @Test("Enables name source output when --show-name-source is set")
    func enablesNameSourceOutput() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            limit: nil,
            noColor: true,
            showPath: false,
            showNameSource: true,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.showNameSource == true)
    }

    @Test("Builds click interaction request when provided")
    func buildsClickInteractionRequest() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            limit: nil,
            noColor: false,
            showPath: false,
            interaction: "click",
            resultIndex: 1,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.interaction?.resultIndex == 1)
        #expect(request?.interaction?.action == .click)
    }

    @Test("Rejects interaction-only selector mode without app and selector")
    func rejectsInteractionOnlyModeWithoutAppSelector() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: nil,
                selector: nil,
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: "click",
                resultIndex: 1,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .missingApplication)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Builds press interaction request when provided")
    func buildsPressInteractionRequest() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            limit: nil,
            noColor: false,
            showPath: false,
            interaction: "press",
            resultIndex: 2,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.interaction?.resultIndex == 2)
        #expect(request?.interaction?.action == .press)
    }

    @Test("Builds focus interaction request when provided")
    func buildsFocusInteractionRequest() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXTextField",
            maxDepth: nil,
            limit: nil,
            noColor: false,
            showPath: false,
            interaction: "focus",
            resultIndex: 3,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.interaction?.resultIndex == 3)
        #expect(request?.interaction?.action == .focus)
    }

    @Test("Builds set-value submit interaction when submit flag is set")
    func buildsSetValueSubmitInteractionRequest() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXTextField",
            maxDepth: nil,
            limit: nil,
            noColor: false,
            showPath: false,
            interaction: "set-value",
            interactionValue: "hello",
            submitAfterSetValue: true,
            resultIndex: 1,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request?.interaction?.resultIndex == 1)
        #expect(request?.interaction?.action == .setValueAndSubmit("hello"))
    }

    @Test("Rejects interaction when result index is missing")
    func rejectsInteractionMissingResultIndex() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: "click",
                resultIndex: nil,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .missingResultIndex)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects non-positive interaction result index")
    func rejectsNonPositiveInteractionResultIndex() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: "click",
                resultIndex: 0,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .invalidResultIndex(0))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects set-value interaction when value is missing")
    func rejectsSetValueMissingInteractionValue() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: "set-value",
                interactionValue: nil,
                resultIndex: 1,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .interactionValueRequired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects interaction value for focus")
    func rejectsInteractionValueForFocus() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: "focus",
                interactionValue: "ignored",
                resultIndex: 1,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .interactionValueNotAllowed("focus"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects submit-after-set-value for non set-value interactions")
    func rejectsSubmitFlagForNonSetValueInteraction() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: "click",
                submitAfterSetValue: true,
                resultIndex: 1,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .submitFlagRequiresSetValue)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects submit-after-set-value when interaction is omitted")
    func rejectsSubmitFlagWithoutInteraction() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: nil,
                submitAfterSetValue: true,
                resultIndex: 1,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .missingInteraction)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects interaction value for click")
    func rejectsInteractionValueForClick() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                interaction: "click",
                interactionValue: "ignored",
                resultIndex: 1,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .interactionValueNotAllowed("click"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects missing app")
    func rejectsMissingApp() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: nil,
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .missingApplication)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects missing selector")
    func rejectsMissingSelector() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: nil,
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .missingSelector)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects structured input mixed with selector mode")
    func rejectsMixedModes() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                hasStructuredInput: true,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .conflictingInputModes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects invalid max depth")
    func rejectsInvalidMaxDepth() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: 0,
                limit: nil,
                noColor: false,
                showPath: false,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .invalidMaxDepth(0))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects invalid limit")
    func rejectsInvalidLimit() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "AXButton",
                maxDepth: nil,
                limit: -1,
                noColor: false,
                showPath: false,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .invalidLimit(-1))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Supports unlimited limit when set to zero")
    func supportsUnlimitedLimitWhenZero() throws {
        let request = try SelectorQueryRequestBuilder.build(
            app: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: nil,
            limit: 0,
            noColor: false,
            showPath: false,
            hasStructuredInput: false,
            stdoutSupportsANSI: true)

        #expect(request != nil)
        #expect(request?.limit == Int.max)
    }

    @Test("Rejects empty app and selector strings")
    func rejectsEmptyFlags() {
        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "   ",
                selector: "AXButton",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .missingApplication)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try SelectorQueryRequestBuilder.build(
                app: "com.apple.TextEdit",
                selector: "  ",
                maxDepth: nil,
                limit: nil,
                noColor: false,
                showPath: false,
                hasStructuredInput: false,
                stdoutSupportsANSI: true)
            Issue.record("Expected build failure")
        } catch let error as SelectorQueryCLIError {
            #expect(error == .missingSelector)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
