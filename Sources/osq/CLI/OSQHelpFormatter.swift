import Foundation
@preconcurrency import Commander

enum OSQHelpFormatter {
    static func render() -> String {
        let description = OSQCommand.commandDescription
        let command = OSQCommand()
        let signature = CommandSignature.describe(command).flattened()

        var lines: [String] = []
        lines.append("osq")
        if !description.abstract.isEmpty {
            lines.append(description.abstract)
        }
        lines.append("")
        lines.append("USAGE")
        lines.append("  osq --app <target> --selector <query> [options]")
        lines.append("  osq --app <target> --selector -i [options]")
        lines.append("  osq --enable-ax <bundle-id> [options]")
        lines.append("  osq --help")
        lines.append("  osq help")

        if !description.usageExamples.isEmpty {
            lines.append("")
            lines.append("EXAMPLES")
            for example in description.usageExamples {
                lines.append("  \(example.command)")
                if !example.description.isEmpty {
                    lines.append("    \(example.description)")
                }
            }
        }

        let optionRows = buildOptionRows(signature: signature)
        if !optionRows.isEmpty {
            lines.append("")
            lines.append("OPTIONS")
            lines.append("  -h, --help  Show help information")
            for row in optionRows {
                lines.append(row)
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func buildOptionRows(signature: CommandSignature) -> [String] {
        var rows: [(left: String, right: String)] = []

        for option in signature.options {
            let names = canonicalNames(from: option.names)
            guard !names.isEmpty else { continue }
            if self.isInternalOnly(names: names) { continue }
            let placeholder: String
            switch option.parsing {
            case .singleValue:
                placeholder = " <value>"
            case .upToNextOption:
                placeholder = " <value...>"
            case .remaining:
                placeholder = " <arguments...>"
            }
            let left = names.joined(separator: ", ") + placeholder
            rows.append((left, option.help ?? ""))
        }

        for flag in signature.flags {
            let names = canonicalNames(from: flag.names)
            guard !names.isEmpty else { continue }
            if self.isInternalOnly(names: names) { continue }
            let left = names.joined(separator: ", ")
            rows.append((left, flag.help ?? ""))
        }

        guard let width = rows.map(\.left.count).max() else { return [] }
        return rows.map { row in
            if row.right.isEmpty {
                return "  \(row.left)"
            }
            let padding = String(repeating: " ", count: max(2, width - row.left.count + 2))
            return "  \(row.left)\(padding)\(row.right)"
        }
    }

    private static func canonicalNames(from names: [CommanderName]) -> [String] {
        let canonical = names.filter { !$0.isAlias }
        let source = canonical.isEmpty ? names : canonical
        return source.map { name in
            switch name {
            case let .short(value), let .aliasShort(value):
                return "-\(value)"
            case let .long(value), let .aliasLong(value):
                return "--\(value)"
            }
        }
    }

    private static func isInternalOnly(names: [String]) -> Bool {
        names.contains("--selector-cache-daemon") || names.contains("--selector-cache-daemon-socket")
    }
}
