import Foundation
import Testing
@testable import axorc

@Suite("Selector Query Output Formatter")
struct SelectorQueryOutputFormatterTests {
    @Test("Stringify handles NSNull and attributed strings")
    func stringifyHandlesNullAndAttributedStrings() {
        #expect(SelectorMatchSummary.stringify(NSNull()) == nil)
        #expect(SelectorMatchSummary.stringify(NSAttributedString(string: "Moulik")) == "Moulik")
    }

    @Test("Formats stats and element rows without ANSI")
    func formatsWithoutColor() {
        let request = SelectorQueryRequest(
            appIdentifier: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: 10,
            limit: 10,
            colorEnabled: false,
            showPath: false)

        let report = SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: 12.345,
            traversedCount: 37,
            matchedCount: 2,
            shownCount: 2,
            results: [
                SelectorMatchSummary(
                    role: "AXButton",
                    computedName: "Save",
                    computedNameSource: "AXTitle",
                    roleDescription: "button",
                    isEnabled: false,
                    isFocused: true,
                    childCount: 3,
                    title: "Save",
                    value: nil,
                    identifier: "save-button",
                    descriptionText: "Save current document",
                    path: "AXApplication -> AXWindow -> AXButton"),
                SelectorMatchSummary(
                    role: "AXTextField",
                    computedName: "Query",
                    computedNameSource: "AXPlaceholderValue",
                    roleDescription: "text field",
                    isEnabled: true,
                    isFocused: false,
                    childCount: 0,
                    title: nil,
                    value: "line1\nline2",
                    identifier: nil,
                    descriptionText: nil,
                    path: nil),
            ])

        let output = SelectorQueryOutputFormatter.format(report: report)
        let lines = output.split(separator: "\n").map(String.init)

        #expect(lines.count == 3)
        #expect(lines[0].contains("stats app=com.apple.TextEdit"))
        #expect(lines[0].contains("selector=\"AXButton\""))
        #expect(lines[0].contains("elapsed_ms=12.35"))
        #expect(lines[0].contains("traversed=37"))
        #expect(lines[0].contains("matched=2"))
        #expect(lines[0].contains("shown=2"))

        #expect(lines[1].contains("[1] AXButton"))
        #expect(lines[1].contains("name=\"Save\""))
        #expect(lines[1].contains("name_source=\"AXTitle\""))
        #expect(lines[1].contains("role_desc=\"button\""))
        #expect(!lines[1].contains("title=\"Save\""))
        #expect(lines[1].contains("id=\"save-button\""))
        #expect(lines[1].contains("desc=\"Save current document\""))
        #expect(lines[1].contains("focused"))
        #expect(lines[1].contains("disabled"))
        #expect(lines[1].contains("children=3"))

        #expect(lines[2].contains("[2] AXTextField"))
        #expect(lines[2].contains("name=\"Query\""))
        #expect(lines[2].contains("name_source=\"AXPlaceholderValue\""))
        #expect(lines[2].contains("role_desc=\"text field\""))
        #expect(lines[2].contains("value=\"line1 line2\""))
        #expect(!lines[2].contains("focused"))
        #expect(!lines[2].contains("disabled"))
        #expect(!lines[2].contains("children="))
        #expect(!output.contains("\n    path: "))
    }

    @Test("Emits no-match message")
    func formatsNoMatches() {
        let request = SelectorQueryRequest(
            appIdentifier: "com.apple.TextEdit",
            selector: "AXUnknownRole",
            maxDepth: 10,
            limit: 10,
            colorEnabled: false,
            showPath: false)

        let report = SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: 1.2,
            traversedCount: 12,
            matchedCount: 0,
            shownCount: 0,
            results: [])

        let output = SelectorQueryOutputFormatter.format(report: report)

        #expect(output.contains("traversed=12"))
        #expect(output.contains("matched=0"))
        #expect(output.contains("shown=0"))
        #expect(output.contains("No matching elements."))
    }

    @Test("Applies ANSI colors per role when enabled")
    func appliesColorsWhenEnabled() {
        let request = SelectorQueryRequest(
            appIdentifier: "com.apple.TextEdit",
            selector: "AXButton, AXTextField",
            maxDepth: 10,
            limit: 10,
            colorEnabled: true,
            showPath: false)

        let report = SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: 2,
            traversedCount: 20,
            matchedCount: 3,
            shownCount: 3,
            results: [
                SelectorMatchSummary(role: "AXButton", computedName: nil, title: nil, value: nil, identifier: nil, descriptionText: nil, path: nil),
                SelectorMatchSummary(role: "AXTextField", computedName: nil, title: nil, value: nil, identifier: nil, descriptionText: nil, path: nil),
                SelectorMatchSummary(role: "AXButton", computedName: nil, title: nil, value: nil, identifier: nil, descriptionText: nil, path: nil),
            ])

        let output = SelectorQueryOutputFormatter.format(report: report)
        let lines = output.split(separator: "\n").map(String.init)

        #expect(lines[1].contains("\u{001B}["))
        #expect(lines[2].contains("\u{001B}["))
        #expect(lines[3].contains("\u{001B}["))

        let firstColor = self.leadingColorCode(in: lines[1])
        let secondColor = self.leadingColorCode(in: lines[2])
        let thirdColor = self.leadingColorCode(in: lines[3])

        #expect(firstColor != nil)
        #expect(secondColor != nil)
        #expect(thirdColor != nil)
        #expect(firstColor == thirdColor)
        #expect(firstColor != secondColor)
    }

    @Test("Clips very long selector in stats line")
    func clipsLongStatsSelector() {
        let selector = String(repeating: "AXButton ", count: 30)
        let request = SelectorQueryRequest(
            appIdentifier: "com.apple.TextEdit",
            selector: selector,
            maxDepth: 10,
            limit: 10,
            colorEnabled: false,
            showPath: false)

        let report = SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: 2,
            traversedCount: 44,
            matchedCount: 0,
            shownCount: 0,
            results: [])

        let output = SelectorQueryOutputFormatter.format(report: report)
        let firstLine = output.split(separator: "\n", maxSplits: 1).map(String.init).first ?? ""

        #expect(firstLine.contains("selector=\""))
        #expect(firstLine.contains("...\""))
    }

    @Test("Shows paths only when enabled")
    func showsPathsOnlyWhenEnabled() {
        let request = SelectorQueryRequest(
            appIdentifier: "com.apple.TextEdit",
            selector: "AXButton",
            maxDepth: 10,
            limit: 10,
            colorEnabled: false,
            showPath: true)

        let report = SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: 2,
            traversedCount: 14,
            matchedCount: 1,
            shownCount: 1,
            results: [
                SelectorMatchSummary(
                    role: "AXButton",
                    computedName: "Save",
                    computedNameSource: "AXTitle",
                    roleDescription: "button",
                    isEnabled: true,
                    isFocused: false,
                    childCount: 1,
                    title: "Save",
                    value: nil,
                    identifier: nil,
                    descriptionText: nil,
                    path: "AXApplication -> AXWindow -> AXButton"),
            ])

        let output = SelectorQueryOutputFormatter.format(report: report)
        #expect(output.contains("\n    path: AXApplication -> AXWindow -> AXButton"))
    }

    private func leadingColorCode(in line: String) -> String? {
        guard let escRange = line.range(of: "\u{001B}[") else {
            return nil
        }

        guard let end = line[escRange.lowerBound...].firstIndex(of: "m") else {
            return nil
        }

        return String(line[escRange.lowerBound...end])
    }
}
