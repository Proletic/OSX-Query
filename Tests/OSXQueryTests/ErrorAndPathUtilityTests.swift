import ApplicationServices
import Foundation
import Testing
@testable import OSXQuery

@Suite("Error and Path Utilities")
struct ErrorAndPathUtilityTests {
    @Test("AXError string and localized descriptions are mapped")
    func axErrorDescriptionsAreMapped() {
        #expect(AXError.success.stringValue == "success")
        #expect(AXError.failure.stringValue == "failure")
        #expect(AXError.apiDisabled.localizedDescription == "Accessibility API is disabled")
        #expect(AXError.notificationNotRegistered.localizedDescription == "Notification is not registered")
    }

    @Test("AXError throwIfError throws only for failures")
    func axErrorThrowIfError() {
        do {
            try AXError.success.throwIfError()
        } catch {
            Issue.record("Success should not throw: \(error)")
        }

        do {
            try AXError.illegalArgument.throwIfError()
            Issue.record("Expected failure to throw")
        } catch let error as AccessibilitySystemError {
            #expect(error.axError == .illegalArgument)
            #expect(error.errorDescription == "Illegal argument")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("AXError converts to AccessibilityError with context")
    func axErrorToAccessibilityErrorUsesContext() {
        #expect(AXError.apiDisabled.toAccessibilityError().description.contains("Accessibility API is disabled"))
        #expect(AXError.invalidUIElement.toAccessibilityError().description == AccessibilityError.invalidElement.description)
        #expect(
            AXError.attributeUnsupported
                .toAccessibilityError(context: "AXTitle")
                .description
                .contains("Attribute 'AXTitle' is not supported"))
        #expect(
            AXError.actionUnsupported
                .toAccessibilityError(context: "AXPress")
                .description
                .contains("Action 'AXPress' is not supported"))
        #expect(
            AXError.noValue
                .toAccessibilityError(context: "AXValue")
                .description
                .contains("Attribute 'AXValue' is not readable"))
        #expect(
            AXError.cannotComplete
                .toAccessibilityError(context: "Timed out")
                .description == "Timed out")
        #expect(
            AXError.failure
                .toAccessibilityError(context: nil)
                .description
                .contains("unexpected Accessibility Framework error"))
    }

    @Test("AccessibilityError descriptions and exit codes are stable")
    func accessibilityErrorDescriptionsAndExitCodes() {
        let errors: [(AccessibilityError, Int32, String)] = [
            (.apiDisabled, 10, "Accessibility API is disabled"),
            (.notAuthorized("denied"), 10, "Accessibility permissions are not granted"),
            (.invalidCommand("bad"), 20, "Invalid command specified"),
            (.missingArgument("selector"), 20, "Missing required argument: selector."),
            (.invalidArgument("maxDepth"), 20, "Invalid argument: maxDepth."),
            (.appNotFound("TextEdit"), 30, "Application 'TextEdit' not found or not running."),
            (.elementNotFound("AXButton"), 30, "No element matches"),
            (.invalidElement, 30, "The specified UI element is invalid"),
            (.observerSetupFailed(details: "boom"), 70, "AXObserver setup failed: boom."),
            (.tokenNotFound(tokenId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), 70, "Subscription token ID"),
            (.attributeUnsupported(attribute: "AXTitle", elementDescription: "Button"), 40, "Attribute 'AXTitle' is not supported on element 'Button'."),
            (.attributeNotReadable(attribute: "AXTitle", elementDescription: nil), 40, "Attribute 'AXTitle' is not readable."),
            (.attributeNotSettable(attribute: "AXTitle", elementDescription: nil), 40, "Attribute 'AXTitle' is not settable."),
            (.typeMismatch(expected: "String", actual: "Int", attribute: "AXValue"), 40, "Type mismatch: Expected 'String', got 'Int' for attribute 'AXValue'."),
            (.valueParsingFailed(details: "bad number", attribute: "AXValue"), 40, "Value parsing failed: bad number for attribute 'AXValue'."),
            (.valueNotAXValue(attribute: "AXPosition", elementDescription: nil), 40, "Value for attribute 'AXPosition' is not an AXValue type as expected."),
            (.actionUnsupported(action: "AXPress", elementDescription: "Button"), 50, "Action 'AXPress' is not supported on element 'Button'."),
            (.actionFailed(action: "AXPress", elementDescription: "Button", underlyingError: .failure), 50, "Action 'AXPress' failed."),
            (.jsonEncodingFailed(nil), 60, "Failed to encode the response to JSON."),
            (.jsonDecodingFailed(nil), 60, "Failed to decode the JSON command input."),
            (.genericError("plain"), 1, "plain"),
        ]

        for (error, exitCode, snippet) in errors {
            #expect(error.exitCode == exitCode)
            #expect(error.description.contains(snippet))
        }
    }

    @Test("PathUtils maps common shortcuts and parses path strings")
    func pathUtilsParsesComponents() {
        #expect(PathUtils.attributeKeyMappings["role"] == AXAttributeNames.kAXRoleAttribute)
        #expect(PathUtils.attributeKeyMappings["cpname"] == AXMiscConstants.computedNameAttributeKey)

        let simple = PathUtils.parsePathComponent(" title : Save ")
        #expect(simple.attributeName == "title ")
        #expect(simple.expectedValue == " Save")

        let invalid = PathUtils.parsePathComponent("not-a-pair")
        #expect(invalid.attributeName.isEmpty)
        #expect(invalid.expectedValue.isEmpty)

        let rich = PathUtils.parseRichPathComponent("role:AXButton, title:\"Save\", value:'Primary', malformed")
        #expect(rich["role"] == "AXButton")
        #expect(rich["title"] == "Save")
        #expect(rich["value"] == "Primary")
        #expect(rich["malformed"] == nil)
    }
}
