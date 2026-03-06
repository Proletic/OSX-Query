import Foundation

enum SelectorQueryOutputFormatter {
    static func format(report: SelectorQueryExecutionReport) -> String {
        var lines: [String] = []
        lines.append(self.statsLine(for: report))

        guard !report.results.isEmpty else {
            lines.append("No matching elements.")
            return lines.joined(separator: "\n")
        }

        let colorizer = RoleColorizer(enabled: report.request.colorEnabled)

        if report.request.treeMode != .none {
            lines.append(contentsOf: self.treeLines(for: report, colorizer: colorizer))
            return lines.joined(separator: "\n")
        }

        for element in report.results {
            lines.append(self.resultRow(
                element,
                colorizer: colorizer,
                showNameSource: report.request.showNameSource))

            if report.request.showPath, let path = element.path {
                lines.append("    path: \(self.sanitize(path, maxLength: 200))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func treeLines(
        for report: SelectorQueryExecutionReport,
        colorizer: RoleColorizer) -> [String]
    {
        switch report.request.treeMode {
        case .none:
            return []
        case .compact:
            return self.compactTreeLines(for: report, colorizer: colorizer)
        case .full:
            return self.fullTreeLines(for: report, colorizer: colorizer)
        }
    }

    private static func fullTreeLines(
        for report: SelectorQueryExecutionReport,
        colorizer: RoleColorizer) -> [String]
    {
        var roots: [TreeRenderNode] = []
        var rootByReference: [String: TreeRenderNode] = [:]

        for (index, result) in report.results.enumerated() {
            let ancestry = self.displayAncestry(for: result)
            guard !ancestry.isEmpty else {
                linesForFallback(result: result, index: index + 1, report: report, colorizer: colorizer, roots: &roots, rootByReference: &rootByReference)
                continue
            }

            guard let matchedReference = self.detailValue(result.reference)?.lowercased() else {
                linesForFallback(result: result, index: index + 1, report: report, colorizer: colorizer, roots: &roots, rootByReference: &rootByReference)
                continue
            }

            var currentNode: TreeRenderNode?

            for ancestor in ancestry {
                let reference = ancestor.reference.lowercased()
                let isMatchedNode = reference == matchedReference
                let label = isMatchedNode
                    ? self.resultRow(
                        result,
                        colorizer: colorizer,
                        showNameSource: report.request.showNameSource)
                    : self.treeLabel(for: ancestor, colorizer: colorizer)
                let pathLine = isMatchedNode && report.request.showPath ? result.path : nil

                if let existingNode = currentNode {
                    currentNode = existingNode.upsertChild(
                        reference: reference,
                        label: label,
                        isMatched: isMatchedNode,
                        pathLine: pathLine)
                } else if let existingRoot = rootByReference[reference] {
                    if isMatchedNode {
                        existingRoot.label = label
                        existingRoot.pathLine = pathLine ?? existingRoot.pathLine
                    }
                    currentNode = existingRoot
                } else {
                    let root = TreeRenderNode(reference: reference, label: label, pathLine: pathLine)
                    roots.append(root)
                    rootByReference[reference] = root
                    currentNode = root
                }
            }
        }

        var lines: [String] = []
        for root in roots {
            lines.append(root.label)
            if let pathLine = root.pathLine {
                lines.append("    path: \(self.sanitize(pathLine, maxLength: 200))")
            }
            lines.append(contentsOf: self.renderChildren(root.children, prefix: ""))
        }
        return lines
    }

    private static func compactTreeLines(
        for report: SelectorQueryExecutionReport,
        colorizer: RoleColorizer) -> [String]
    {
        let matchedByReference = Dictionary(
            uniqueKeysWithValues: report.results.compactMap { result in
                self.detailValue(result.reference).map { ($0.lowercased(), result) }
            })

        var roots: [CompactTreeNode] = []
        var nodesByReference: [String: CompactTreeNode] = [:]
        var rootReferenceSet = Set<String>()

        for result in report.results {
            guard let reference = self.detailValue(result.reference)?.lowercased() else {
                continue
            }

            let node: CompactTreeNode
            if let existing = nodesByReference[reference] {
                node = existing
            } else {
                node = CompactTreeNode(
                    reference: reference,
                    label: self.resultRow(
                        result,
                        colorizer: colorizer,
                        showNameSource: report.request.showNameSource),
                    pathLine: report.request.showPath ? result.path : nil)
                nodesByReference[reference] = node
            }

            if node.pathLine == nil, report.request.showPath {
                node.pathLine = result.path
            }

            let ancestry = self.displayAncestry(for: result)
            let ancestorReferences = ancestry.dropLast().compactMap { ancestor in
                self.detailValue(ancestor.reference)?.lowercased()
            }

            var matchedAncestorReference: String?
            var skippedIntermediates = false

            for ancestorReference in ancestorReferences.reversed() {
                if matchedByReference[ancestorReference] != nil {
                    matchedAncestorReference = ancestorReference
                    break
                }
                skippedIntermediates = true
            }

            if let matchedAncestorReference,
               let parentNode = nodesByReference[matchedAncestorReference]
            {
                parentNode.upsertChild(node, style: skippedIntermediates ? .skipped : .direct)
            } else if rootReferenceSet.insert(reference).inserted {
                roots.append(node)
            }
        }

        var lines: [String] = []
        for root in roots {
            lines.append(root.label)
            if let pathLine = root.pathLine {
                lines.append("    path: \(self.sanitize(pathLine, maxLength: 200))")
            }
            lines.append(contentsOf: self.renderCompactChildren(root.children, prefix: ""))
        }
        return lines
    }

    private static func linesForFallback(
        result: SelectorMatchSummary,
        index: Int,
        report: SelectorQueryExecutionReport,
        colorizer: RoleColorizer,
        roots: inout [TreeRenderNode],
        rootByReference: inout [String: TreeRenderNode])
    {
        let syntheticReference = "synthetic-\(index)"
        let root = TreeRenderNode(
            reference: syntheticReference,
            label: self.resultRow(
                result,
                colorizer: colorizer,
                showNameSource: report.request.showNameSource),
            pathLine: report.request.showPath ? result.path : nil)
        roots.append(root)
        rootByReference[syntheticReference] = root
    }

    private static func renderChildren(_ children: [TreeRenderNode], prefix: String) -> [String] {
        var lines: [String] = []

        for (index, child) in children.enumerated() {
            let isLast = index == children.count - 1
            let branch = isLast ? "└── " : "├── "
            lines.append(prefix + branch + child.label)

            if let pathLine = child.pathLine {
                let pathPrefix = prefix + (isLast ? "    " : "│   ")
                lines.append(pathPrefix + "path: \(self.sanitize(pathLine, maxLength: 200))")
            }

            let nextPrefix = prefix + (isLast ? "    " : "│   ")
            lines.append(contentsOf: self.renderChildren(child.children, prefix: nextPrefix))
        }

        return lines
    }

    private static func renderCompactChildren(_ children: [CompactTreeChild], prefix: String) -> [String] {
        var lines: [String] = []

        for (index, child) in children.enumerated() {
            let isLast = index == children.count - 1
            let branch = self.compactBranch(isLast: isLast, style: child.style)
            lines.append(prefix + branch + child.node.label)

            if let pathLine = child.node.pathLine {
                let pathPrefix = prefix + (isLast ? "    " : "│   ")
                lines.append(pathPrefix + "path: \(self.sanitize(pathLine, maxLength: 200))")
            }

            let nextPrefix = prefix + (isLast ? "    " : "│   ")
            lines.append(contentsOf: self.renderCompactChildren(child.node.children, prefix: nextPrefix))
        }

        return lines
    }

    private static func compactBranch(isLast: Bool, style: CompactEdgeStyle) -> String {
        switch style {
        case .direct:
            return isLast ? "└── " : "├── "
        case .skipped:
            return isLast ? "└●─ " : "├●─ "
        }
    }

    private static func treeLabel(for node: SelectorTreeNodeSummary, colorizer: RoleColorizer) -> String {
        let displayLabel = node.displayLabel
        guard displayLabel.hasPrefix(node.role) else {
            return displayLabel
        }

        let roleLabel = colorizer.colorizeRole(node.role)
        let suffix = displayLabel.dropFirst(node.role.count)
        return roleLabel + suffix
    }

    private static func resultRow(
        _ element: SelectorMatchSummary,
        colorizer: RoleColorizer,
        showNameSource: Bool) -> String
    {
        let roleLabel = colorizer.colorizeRole(element.role)
        var detailParts: [String] = []

        if let reference = self.detailValue(element.reference) {
            detailParts.append("ref=\(self.sanitize(reference))")
        }

        if let computedName = self.detailValue(element.resultDisplayName) {
            detailParts.append("name=\"\(self.sanitize(computedName))\"")
            if showNameSource, let computedNameSource = self.detailValue(element.resultDisplayNameSource) {
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
        return "\(roleLabel)\(detailSuffix)"
    }

    private static func displayAncestry(for result: SelectorMatchSummary) -> [SelectorTreeNodeSummary] {
        guard !result.ancestry.isEmpty else {
            return []
        }

        if result.ancestry.count > 1, result.ancestry.first?.role == "AXApplication" {
            return Array(result.ancestry.dropFirst())
        }

        return result.ancestry
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

private final class TreeRenderNode {
    let reference: String
    var label: String
    var pathLine: String?
    var children: [TreeRenderNode] = []

    private var childByReference: [String: TreeRenderNode] = [:]

    init(reference: String, label: String, pathLine: String?) {
        self.reference = reference
        self.label = label
        self.pathLine = pathLine
    }

    func upsertChild(reference: String, label: String, isMatched: Bool, pathLine: String?) -> TreeRenderNode {
        if let existing = self.childByReference[reference] {
            if isMatched {
                existing.label = label
                existing.pathLine = pathLine ?? existing.pathLine
            }
            return existing
        }

        let child = TreeRenderNode(reference: reference, label: label, pathLine: pathLine)
        self.childByReference[reference] = child
        self.children.append(child)
        return child
    }
}

private enum CompactEdgeStyle {
    case direct
    case skipped
}

private struct CompactTreeChild {
    let node: CompactTreeNode
    let style: CompactEdgeStyle
}

private final class CompactTreeNode {
    let reference: String
    let label: String
    var pathLine: String?
    var children: [CompactTreeChild] = []

    private var childIndexByReference: [String: Int] = [:]

    init(reference: String, label: String, pathLine: String?) {
        self.reference = reference
        self.label = label
        self.pathLine = pathLine
    }

    func upsertChild(_ child: CompactTreeNode, style: CompactEdgeStyle) {
        if let existingIndex = self.childIndexByReference[child.reference] {
            self.children[existingIndex] = CompactTreeChild(node: child, style: style)
            return
        }

        self.childIndexByReference[child.reference] = self.children.count
        self.children.append(CompactTreeChild(node: child, style: style))
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
