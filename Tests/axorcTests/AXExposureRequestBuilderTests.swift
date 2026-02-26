import Testing
@testable import axorc

@Suite("AX Exposure Request Builder")
struct AXExposureRequestBuilderTests {
    @Test("Returns nil when AX exposure flag is absent")
    func returnsNilWhenFlagAbsent() throws {
        let request = try AXExposureRequestBuilder.build(
            bundleIdentifier: nil,
            hasStructuredInput: false,
            hasSelectorInput: false)

        #expect(request == nil)
    }

    @Test("Builds request with trimmed bundle identifier")
    func buildsTrimmedRequest() throws {
        let request = try AXExposureRequestBuilder.build(
            bundleIdentifier: "  com.apple.TextEdit  ",
            hasStructuredInput: false,
            hasSelectorInput: false)

        #expect(request?.bundleIdentifier == "com.apple.TextEdit")
        #expect(request?.focusTimeoutSeconds == 2)
    }

    @Test("Rejects empty bundle identifier")
    func rejectsEmptyBundleIdentifier() {
        do {
            _ = try AXExposureRequestBuilder.build(
                bundleIdentifier: "   ",
                hasStructuredInput: false,
                hasSelectorInput: false)
            Issue.record("Expected build failure")
        } catch let error as AXExposureCLIError {
            #expect(error == .missingBundleIdentifier)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects structured input with AX exposure mode")
    func rejectsStructuredInputConflict() {
        do {
            _ = try AXExposureRequestBuilder.build(
                bundleIdentifier: "com.apple.TextEdit",
                hasStructuredInput: true,
                hasSelectorInput: false)
            Issue.record("Expected build failure")
        } catch let error as AXExposureCLIError {
            #expect(error == .conflictingInputModes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects selector flags with AX exposure mode")
    func rejectsSelectorConflict() {
        do {
            _ = try AXExposureRequestBuilder.build(
                bundleIdentifier: "com.apple.TextEdit",
                hasStructuredInput: false,
                hasSelectorInput: true)
            Issue.record("Expected build failure")
        } catch let error as AXExposureCLIError {
            #expect(error == .conflictingSelectorMode)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
