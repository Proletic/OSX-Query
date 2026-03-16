import ApplicationServices
import CoreGraphics
import Testing
@testable import OSXQuery

@Suite("AX Command Models")
struct AXCommandModelTests {
    @Test("AXCommand reports expected type strings")
    func axCommandTypeStrings() {
        let locator = Locator(criteria: [Criterion(attribute: "AXRole", value: "AXButton")])
        let commands: [(AXCommand, String)] = [
            (.query(QueryCommand(appIdentifier: "App", locator: locator)), "query"),
            (.performAction(PerformActionCommand(appIdentifier: "App", locator: locator, action: "AXPress")), "performAction"),
            (.getAttributes(GetAttributesCommand(appIdentifier: "App", locator: locator, attributes: ["AXTitle"])), "getAttributes"),
            (.describeElement(DescribeElementCommand(appIdentifier: "App", locator: locator)), "describeElement"),
            (.extractText(ExtractTextCommand(appIdentifier: "App", locator: locator)), "extractText"),
            (.batch(AXBatchCommand(commands: [.init(commandID: "1", command: .query(QueryCommand(appIdentifier: nil, locator: locator)))])), "batch"),
            (.setFocusedValue(SetFocusedValueCommand(appIdentifier: "App", locator: locator, value: "Hello")), "setFocusedValue"),
            (.getElementAtPoint(GetElementAtPointCommand(point: CGPoint(x: 1, y: 2))), "getElementAtPoint"),
            (.getFocusedElement(GetFocusedElementCommand(appIdentifier: "App")), "getFocusedElement"),
            (.observe(ObserveCommand(
                appIdentifier: "App",
                locator: locator,
                notifications: ["AXValueChanged"],
                includeDetails: true,
                watchChildren: false,
                notificationName: .valueChanged,
                includeElementDetails: ["AXTitle"])), "observe"),
            (.collectAll(CollectAllCommand(appIdentifier: "App")), "collectAll"),
        ]

        for (command, expectedType) in commands {
            #expect(command.type == expectedType)
        }
    }

    @Test("AX command envelopes preserve their identifiers")
    func axCommandEnvelopeStoresValues() {
        let locator = Locator(criteria: [Criterion(attribute: "AXRole", value: "AXButton")])
        let envelope = AXCommandEnvelope(
            commandID: "search",
            command: .query(QueryCommand(appIdentifier: "TextEdit", locator: locator)))

        #expect(envelope.commandID == "search")
        #expect(envelope.command.type == "query")
    }

    @Test("Individual command initializers preserve payload")
    func individualCommandInitializers() {
        let locator = Locator(
            matchAll: false,
            criteria: [Criterion(attribute: "AXTitle", value: "Save")],
            selector: "AXButton")

        let query = QueryCommand(
            appIdentifier: "TextEdit",
            locator: locator,
            attributesToReturn: ["AXTitle"],
            maxDepthForSearch: 12,
            includeChildrenBrief: true)
        #expect(query.appIdentifier == "TextEdit")
        #expect(query.locator.selector == "AXButton")
        #expect(query.attributesToReturn == ["AXTitle"])
        #expect(query.maxDepthForSearch == 12)
        #expect(query.includeChildrenBrief == true)

        let action = PerformActionCommand(
            appIdentifier: "TextEdit",
            locator: locator,
            action: "AXPress",
            value: AnyCodable("click"),
            maxDepthForSearch: 3)
        #expect(action.action == "AXPress")
        #expect(action.value == AnyCodable("click"))
        #expect(action.maxDepthForSearch == 3)

        let describe = DescribeElementCommand(
            appIdentifier: "TextEdit",
            locator: locator,
            formatOption: .raw,
            maxDepthForSearch: 4,
            depth: 5,
            includeIgnored: true,
            maxSearchDepth: 7)
        #expect(describe.formatOption == .raw)
        #expect(describe.depth == 5)
        #expect(describe.includeIgnored)
        #expect(describe.maxSearchDepth == 7)

        let extract = ExtractTextCommand(
            appIdentifier: "TextEdit",
            locator: locator,
            maxDepthForSearch: 2,
            includeChildren: true,
            maxDepth: 9)
        #expect(extract.includeChildren == true)
        #expect(extract.maxDepth == 9)

        let setFocused = SetFocusedValueCommand(
            appIdentifier: "TextEdit",
            locator: locator,
            value: "Updated",
            maxDepthForSearch: 6)
        #expect(setFocused.value == "Updated")
        #expect(setFocused.maxDepthForSearch == 6)

        let focused = GetFocusedElementCommand(
            appIdentifier: "TextEdit",
            attributesToReturn: ["AXRole"],
            includeChildrenBrief: false)
        #expect(focused.attributesToReturn == ["AXRole"])
        #expect(focused.includeChildrenBrief == false)

        let collect = CollectAllCommand(
            appIdentifier: "TextEdit",
            attributesToReturn: ["AXTitle"],
            maxDepth: 8,
            filterCriteria: ["AXRole": "AXButton"],
            valueFormatOption: .stringified)
        #expect(collect.appIdentifier == "TextEdit")
        #expect(collect.attributesToReturn == ["AXTitle"])
        #expect(collect.maxDepth == 8)
        #expect(collect.filterCriteria?["AXRole"] == "AXButton")
        #expect(collect.valueFormatOption == .stringified)
    }

    @Test("GetElementAtPoint stores point and coordinate variants")
    func getElementAtPointInitializers() {
        let pointBased = GetElementAtPointCommand(
            point: CGPoint(x: 10, y: 20),
            appIdentifier: "TextEdit",
            pid: 111,
            attributesToReturn: ["AXRole"],
            includeChildrenBrief: true)

        #expect(pointBased.point == CGPoint(x: 10, y: 20))
        #expect(pointBased.xCoordinate == 10)
        #expect(pointBased.yCoordinate == 20)
        #expect(pointBased.pid == 111)
        #expect(pointBased.attributesToReturn == ["AXRole"])
        #expect(pointBased.includeChildrenBrief == true)

        let coordinateBased = GetElementAtPointCommand(
            appIdentifier: "TextEdit",
            x: 5,
            y: 7,
            attributesToReturn: ["AXTitle"],
            includeChildrenBrief: false)

        #expect(coordinateBased.point == CGPoint(x: 5, y: 7))
        #expect(coordinateBased.xCoordinate == 5)
        #expect(coordinateBased.yCoordinate == 7)
        #expect(coordinateBased.pid == nil)
        #expect(coordinateBased.includeChildrenBrief == false)
    }

    @Test("Observe and batch commands keep nested values")
    func observeAndBatchCommandsStoreValues() {
        let locator = Locator(criteria: [Criterion(attribute: "AXRole", value: "AXWindow")])
        let observe = ObserveCommand(
            appIdentifier: "TextEdit",
            locator: locator,
            notifications: ["AXMoved", "AXResized"],
            includeDetails: false,
            watchChildren: true,
            notificationName: .moved,
            includeElementDetails: ["AXTitle"],
            maxDepthForSearch: 4)

        #expect(observe.appIdentifier == "TextEdit")
        #expect(observe.notifications == ["AXMoved", "AXResized"])
        #expect(observe.includeDetails == false)
        #expect(observe.watchChildren == true)
        #expect(observe.notificationName == .moved)
        #expect(observe.includeElementDetails == ["AXTitle"])
        #expect(observe.maxDepthForSearch == 4)

        let batch = AXBatchCommand(commands: [
            .init(commandID: "first", command: .getFocusedElement(GetFocusedElementCommand(appIdentifier: nil))),
            .init(commandID: "second", command: .collectAll(CollectAllCommand(appIdentifier: "TextEdit"))),
        ])

        #expect(batch.commands.count == 2)
        #expect(batch.commands[0].commandID == "first")
        #expect(batch.commands[0].command.type == "getFocusedElement")
        #expect(batch.commands[1].commandID == "second")
        #expect(batch.commands[1].command.type == "collectAll")
    }
}
