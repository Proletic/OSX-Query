import CoreGraphics
import Foundation
import Testing
@testable import OSXQuery

@Suite("Serialization and Model Contracts")
struct SerializationModelTests {
    @Test("AnyCodable encodes and decodes primitive values")
    func anyCodablePrimitiveRoundTrips() throws {
        let values: [AnyCodable] = [
            AnyCodable(true),
            AnyCodable(42),
            AnyCodable(2.5),
            AnyCodable("hello"),
            AnyCodable(nil as String?),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("AnyCodable round trips arrays and dictionaries")
    func anyCodableCollectionRoundTrips() throws {
        let original = AnyCodable([
            "list": [1, "two", true] as [Any],
            "nested": [
                "flag": false,
                "value": 3.14,
            ] as [String: Any],
        ] as [String: Any])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        #expect(decoded == original)
    }

    @Test("AnyCodable encodes custom Encodable payloads")
    func anyCodableEncodesCustomEncodable() throws {
        struct Payload: Codable, Equatable {
            let id: Int
            let name: String
        }

        let wrapped = AnyCodable(Payload(id: 7, name: "widget"))
        let data = try JSONEncoder().encode(wrapped)
        let decoded = try JSONDecoder().decode(Payload.self, from: data)

        #expect(decoded == Payload(id: 7, name: "widget"))
    }

    @Test("AttributeValue exposes typed accessors and anyValue")
    func attributeValueTypedAccessors() {
        let dictionary = AttributeValue.dictionary([
            "name": .string("Button"),
            "enabled": .bool(true),
            "children": .array([.int(1), .double(2.5)]),
        ])

        #expect(AttributeValue.string("hello").stringValue == "hello")
        #expect(AttributeValue.bool(true).boolValue == true)
        #expect(AttributeValue.int(8).intValue == 8)
        #expect(AttributeValue.double(4.5).doubleValue == 4.5)
        #expect(AttributeValue.null.isNull)
        #expect(dictionary.dictionaryValue?["name"]?.stringValue == "Button")

        let anyValue = dictionary.anyValue as? [String: Any]
        #expect(anyValue?["name"] as? String == "Button")
        #expect(anyValue?["enabled"] as? Bool == true)
    }

    @Test("AttributeValue converts Foundation values")
    func attributeValueFromAny() {
        let integralNumber = NSNumber(value: 9)
        let fractionalNumber = NSNumber(value: 1.25)
        let boolNumber = kCFBooleanTrue
        let nullValue = NSNull()

        #expect(AttributeValue(from: integralNumber) == .int(9))
        #expect(AttributeValue(from: fractionalNumber) == .double(1.25))
        #expect(AttributeValue(from: boolNumber) == .bool(true))
        #expect(AttributeValue(from: nullValue) == .null)
        #expect(AttributeValue(from: ["a": 1, "b": "two"]) == .dictionary([
            "a": .int(1),
            "b": .string("two"),
        ]))
    }

    @Test("AXValueWrapper sanitizes nested dictionaries and arrays")
    @MainActor
    func axValueWrapperSanitizesCollections() {
        let wrapper = AXValueWrapper(value: [
            "title": "Hello",
            "flags": [true, false],
            "details": [
                "count": 3,
                "value": 1.5,
            ],
            "nullish": nil,
        ] as [String: Any?])

        guard case let .dictionary(dict)? = wrapper.anyValue else {
            Issue.record("Expected dictionary payload")
            return
        }

        #expect(dict["title"] == .string("Hello"))
        #expect(dict["flags"] == .array([.bool(true), .bool(false)]))
        #expect(dict["details"] == .dictionary([
            "count": .double(3.0),
            "value": .double(1.5),
        ]))
        #expect(dict["nullish"] == .null)
    }

    @Test("Criterion and PathStep encode optional match metadata")
    func criterionAndPathStepCoding() throws {
        let step = PathStep(
            criteria: [Criterion(attribute: "AXRole", value: "AXButton", matchType: .contains)],
            matchType: .contains,
            matchAllCriteria: false,
            maxDepthForStep: 4)

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(PathStep.self, from: data)

        #expect(decoded.criteria.count == 1)
        #expect(decoded.criteria[0].matchType == .contains)
        #expect(decoded.matchType == .contains)
        #expect(decoded.matchAllCriteria == false)
        #expect(decoded.maxDepthForStep == 4)
        #expect(decoded.descriptionForLog().contains("Depth: 4"))
    }

    @Test("Locator maps path_from_root when decoding")
    func locatorCodingUsesPathFromRoot() throws {
        let json = """
        {
          "matchAll": false,
          "criteria": [{"attribute":"AXTitle","value":"Save"}],
          "selector": "AXButton",
          "path_from_root": [{"attribute":"role","value":"AXWindow","depth":2,"matchType":"exact"}],
          "descendantCriteria": {"AXRole":"AXButton"},
          "requireAction": "AXPress",
          "computedNameContains": "Save",
          "debugPathSearch": true
        }
        """.data(using: .utf8)!

        let locator = try JSONDecoder().decode(Locator.self, from: json)

        #expect(locator.matchAll == false)
        #expect(locator.criteria.count == 1)
        #expect(locator.selector == "AXButton")
        #expect(locator.rootElementPathHint?.count == 1)
        #expect(locator.rootElementPathHint?.first?.depth == 2)
        #expect(locator.descendantCriteria?["AXRole"] == "AXButton")
        #expect(locator.requireAction == "AXPress")
        #expect(locator.computedNameContains == "Save")
        #expect(locator.debugPathSearch == true)
    }

    @Test("JSONPathHintComponent resolves attribute aliases")
    func jsonPathHintComponentMapsAttributeNames() {
        let role = JSONPathHintComponent(attribute: "role", value: "AXWindow")
        let dom = JSONPathHintComponent(attribute: "DOMCLASS", value: "primary")
        let unknown = JSONPathHintComponent(attribute: "unknown", value: "value")

        #expect(role.axAttributeName == AXAttributeNames.kAXRoleAttribute)
        #expect(role.simpleCriteria?[AXAttributeNames.kAXRoleAttribute] == "AXWindow")
        #expect(dom.axAttributeName == AXAttributeNames.kAXDOMClassListAttribute)
        #expect(dom.descriptionForLog() == "\(AXAttributeNames.kAXDOMClassListAttribute):primary")
        #expect(unknown.axAttributeName == nil)
        #expect(unknown.simpleCriteria == nil)
    }

    @Test("CommandEnvelope decodes defaults for omitted fields")
    func commandEnvelopeDefaultsOmittedFields() throws {
        let json = """
        {
          "commandId": "cmd-1",
          "command": "query"
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(CommandEnvelope.self, from: json)

        #expect(envelope.commandId == "cmd-1")
        #expect(envelope.command == .query)
        #expect(envelope.debugLogging == false)
        #expect(envelope.application == nil)
        #expect(envelope.locator == nil)
    }

    @Test("CommandEnvelope round trips optional fields")
    func commandEnvelopeRoundTripsRichPayload() throws {
        let subcommand = CommandEnvelope(commandId: "child", command: .ping)
        let envelope = CommandEnvelope(
            commandId: "cmd-2",
            command: .performAction,
            application: "TextEdit",
            attributes: ["AXTitle"],
            payload: ["kind": "ping"],
            debugLogging: true,
            locator: Locator(criteria: [Criterion(attribute: "AXRole", value: "AXButton")]),
            pathHint: ["window"],
            maxElements: 5,
            maxDepth: 2,
            outputFormat: .json,
            actionName: "AXPress",
            actionValue: AnyCodable("click"),
            subCommands: [subcommand],
            point: CGPoint(x: 10, y: 20),
            pid: 123,
            notifications: ["AXFocusedUIElementChanged"],
            includeElementDetails: ["AXRole"],
            watchChildren: true,
            filterCriteria: ["AXRole": "AXButton"],
            includeChildrenBrief: true,
            includeChildrenInText: true,
            includeIgnoredElements: true)

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)

        #expect(decoded.commandId == envelope.commandId)
        #expect(decoded.command == .performAction)
        #expect(decoded.application == "TextEdit")
        #expect(decoded.attributes == ["AXTitle"])
        #expect(decoded.payload?["kind"] == "ping")
        #expect(decoded.debugLogging)
        #expect(decoded.pathHint == ["window"])
        #expect(decoded.maxElements == 5)
        #expect(decoded.maxDepth == 2)
        #expect(decoded.outputFormat == .json)
        #expect(decoded.actionName == "AXPress")
        #expect(decoded.actionValue == AnyCodable("click"))
        #expect(decoded.subCommands?.count == 1)
        #expect(decoded.point == CGPoint(x: 10, y: 20))
        #expect(decoded.pid == 123)
        #expect(decoded.notifications == ["AXFocusedUIElementChanged"])
        #expect(decoded.includeElementDetails == ["AXRole"])
        #expect(decoded.watchChildren == true)
        #expect(decoded.filterCriteria?["AXRole"] == "AXButton")
        #expect(decoded.includeChildrenBrief == true)
        #expect(decoded.includeChildrenInText == true)
        #expect(decoded.includeIgnoredElements == true)
    }

    @Test("HandlerResponse tracks success and failure helpers")
    func handlerResponseHelpers() {
        let success = HandlerResponse.success(data: AnyCodable(["ok": true]))
        let failure = HandlerResponse.failure(errorMessage: "nope")

        #expect(success.succeeded)
        #expect(success.failed == false)
        #expect(failure.failed)
        #expect(failure.succeeded == false)
    }

    @Test("HandlerResponse can be built from AXResponse")
    func handlerResponseFromAXResponse() {
        let success = HandlerResponse(from: .success(payload: AnyCodable("value"), logs: ["log"]))
        let failure = HandlerResponse(from: .error(message: "bad", code: .invalidCommand, logs: nil))

        #expect(success.data == AnyCodable("value"))
        #expect(success.error == nil)
        #expect(failure.data == nil)
        #expect(failure.error == "bad")
    }

    @Test("Response models expose derived values and encode correctly")
    func responseModelsWorkAsExpected() throws {
        let success = AXResponse.successResponse(payload: AnyCodable(["ok": true]), logs: ["done"])
        let failure = AXResponse.errorResponse(message: "bad", code: .timeout, logs: ["trace"])

        #expect(success.status == "success")
        #expect(success.payload == AnyCodable(["ok": true]))
        #expect(success.logs == ["done"])
        #expect(failure.status == "error")
        #expect(failure.error?.message == "bad")
        #expect(failure.error?.code == .timeout)
        #expect(failure.logs == ["trace"])

        let errorResponse = ErrorResponse(commandId: "cmd", error: "broken", debugLogs: ["trace"])
        let successResponse = SimpleSuccessResponse(
            commandId: "cmd",
            status: "ok",
            message: "pong",
            details: "detail",
            debugLogs: ["trace"])
        let batch = BatchResponse(
            commandId: "batch",
            success: false,
            results: [.success(data: AnyCodable(1)), .failure(errorMessage: "bad")],
            error: "batch failed",
            debugLogs: ["trace"])

        #expect(errorResponse.success == false)
        #expect(errorResponse.error == ErrorDetail(message: "broken"))
        #expect(successResponse.success == true)
        #expect(batch.results.count == 2)
        #expect(batch.error == "batch failed")

        let batchData = try JSONEncoder().encode(batch)
        let decodedBatch = try JSONDecoder().decode(BatchResponse.self, from: batchData)
        #expect(decodedBatch.commandId == "batch")
        #expect(decodedBatch.results.count == 2)
    }

    @Test("Query and collect-all responses transform payloads")
    func queryAndCollectAllResponses() throws {
        let element = AXElement(attributes: ["AXTitle": .string("Save")], path: ["window", "button"])
        let handler = HandlerResponse(data: AnyCodable(element), error: nil)
        let query = QueryResponse(
            commandId: "query",
            success: true,
            command: "query",
            handlerResponse: handler,
            debugLogs: ["trace"])

        #expect(query.data?.path == ["window", "button"])
        #expect(query.attributes?["AXTitle"] == .string("Save"))
        #expect(query.error == nil)

        let jsonString = try query.jsonString()
        #expect(jsonString.contains("\"commandId\""))

        let multi = MultiQueryResponse(
            commandId: "collect",
            elements: [["AXTitle": .string("One")], ["AXTitle": .string("Two")]],
            debugLogs: ["trace"])
        #expect(multi.count == 2)

        let output = CollectAllOutput(
            commandId: "collect",
            success: true,
            command: "collectAll",
            collectedElements: [
                AXElementData(briefDescription: "Button", role: "AXButton"),
            ],
            appIdentifier: "TextEdit",
            debugLogs: ["trace"],
            message: nil)

        let data = try JSONEncoder().encode(output)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"command_id\":\"collect\""))
        #expect(json.contains("\"app_identifier\":\"TextEdit\""))
    }
}
