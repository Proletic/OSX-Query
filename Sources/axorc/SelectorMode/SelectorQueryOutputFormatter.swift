import Foundation

enum SelectorQueryOutputFormatter {
    static func format(report: SelectorQueryExecutionReport) -> String {
        var lines: [String] = []
        lines.append(self.statsLine(for: report))
        if let interaction = report.interaction {
            var interactionParts = [
                "interaction",
                "index=\(interaction.resultIndex)",
                "action=\(interaction.action)",
                "status=success",
                "role=\(interaction.role)",
            ]
            if let computedName = self.detailValue(interaction.computedName) {
                interactionParts.append("name=\"\(self.sanitize(computedName))\"")
            }
            lines.append(interactionParts.joined(separator: " "))
        }

        guard !report.results.isEmpty else {
            lines.append("No matching elements.")
            return lines.joined(separator: "\n")
        }

        let colorizer = RoleColorizer(enabled: report.request.colorEnabled)

        for (index, element) in report.results.enumerated() {
            let roleLabel = colorizer.colorizeRole(element.role)
            var detailParts: [String] = []

            if let computedName = self.detailValue(element.resultDisplayName) {
                detailParts.append("name=\"\(self.sanitize(computedName))\"")
                if report.request.showNameSource, let computedNameSource = self.detailValue(element.resultDisplayNameSource) {
                    detailParts.append("name_source=\"\(self.sanitize(computedNameSource))\"")
                }
            }

            if let title = self.detailValue(element.title) {
                let isStaticTextValueName = element.role == "AXStaticText" &&
                    self.detailValue(element.value) != nil
                if !isStaticTextValueName && title != element.resultDisplayName {
                    detailParts.append("title=\"\(self.sanitize(title))\"")
                }
            }

            if let value = self.detailValue(element.resultDisplayValue) {
                detailParts.append("value=\"\(self.sanitize(value))\"")
            }

            if let identifier = self.detailValue(element.identifier) {
                detailParts.append("id=\"\(self.sanitize(identifier))\"")
            }

            if let descriptionText = self.detailValue(element.descriptionText) {
                detailParts.append("desc=\"\(self.sanitize(descriptionText))\"")
            }

            if element.isFocused == true {
                detailParts.append("focused")
            }

            if element.isEnabled == false {
                detailParts.append("disabled")
            }

            let detailSuffix = detailParts.isEmpty ? "" : " " + detailParts.joined(separator: " ")
            lines.append("[\(index + 1)] \(roleLabel)\(detailSuffix)")

            if report.request.showPath, let path = element.path {
                lines.append("    path: \(self.sanitize(path, maxLength: 200))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func statsLine(for report: SelectorQueryExecutionReport) -> String {
        let elapsed = String(format: "%.2f", report.elapsedMilliseconds)
        return "stats app=\(report.request.appIdentifier) selector=\"\(self.sanitize(report.request.selector, maxLength: 120))\" elapsed_ms=\(elapsed) traversed=\(report.traversedCount) matched=\(report.matchedCount) shown=\(report.shownCount)"
    }

    private static func sanitize(_ value: String, maxLength: Int = 120) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsedWhitespace.count > maxLength else {
            return collapsedWhitespace
        }

        let clipped = collapsedWhitespace.prefix(maxLength)
        return "\(clipped)..."
    }

    private static func detailValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let lowered = trimmed.lowercased()
        if lowered == "nil" || lowered == "null" || lowered == "(null)" || lowered == "<null>" || lowered == "optional(nil)" {
            return nil
        }
        return trimmed
    }
}

private struct RoleColorizer {
    private static let colors = [
        ANSI.red,
        ANSI.green,
        ANSI.yellow,
        ANSI.blue,
        ANSI.magenta,
        ANSI.cyan,
        ANSI.brightRed,
        ANSI.brightGreen,
        ANSI.brightYellow,
        ANSI.brightBlue,
        ANSI.brightMagenta,
        ANSI.brightCyan,
    ]

    let enabled: Bool

    func colorizeRole(_ role: String) -> String {
        guard self.enabled else { return role }

        let color = Self.colors[self.colorIndex(for: role)]
        return color + role + ANSI.reset
    }

    private func colorIndex(for role: String) -> Int {
        let stableHash = role.utf8.reduce(UInt64(5381)) { partial, byte in
            ((partial << 5) &+ partial) &+ UInt64(byte)
        }

        return Int(stableHash % UInt64(Self.colors.count))
    }
}

private enum ANSI {
    static let reset = "\u{001B}[0m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let brightRed = "\u{001B}[91m"
    static let brightGreen = "\u{001B}[92m"
    static let brightYellow = "\u{001B}[93m"
    static let brightBlue = "\u{001B}[94m"
    static let brightMagenta = "\u{001B}[95m"
    static let brightCyan = "\u{001B}[96m"
}
