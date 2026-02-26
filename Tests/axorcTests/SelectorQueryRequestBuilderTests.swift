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
