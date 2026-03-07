import Foundation
@preconcurrency import Commander

enum OSXHelpFormatter {
    static func render(arguments: [String] = []) -> String {
        let requestedPath = OSXHelpRequestDetector.requestedCommandPath(arguments: arguments)
        switch requestedPath {
        case ["query"]:
            return renderCommand(
                title: "osx query",
                abstract: "Run a selector query against a target app.",
                usage: [
                    "osx query --app <target> <selector> [options]",
                ],
                command: OSXQueryCommand())
        case ["interactive"]:
            return renderCommand(
                title: "osx interactive",
                abstract: "Open the interactive selector query TUI.",
                usage: [
                    "osx interactive <app> [options]",
                ],
                command: OSXInteractiveCommand())
        case ["action"]:
            return renderCommand(
                title: "osx action",
                abstract: "Execute an OXA action program against cached refs.",
                usage: [
                    "osx action <program> [options]",
                ],
                command: OSXActionCommand())
        case ["enable-ax"]:
            return renderCommand(
                title: "osx enable-ax",
                abstract: "Enable AXEnhancedUserInterface and AXManualAccessibility for a running app.",
                usage: [
                    "osx enable-ax <bundle-id> [options]",
                ],
                command: OSXEnableAXCommand())
        default:
            return renderRoot()
        }
    }

    private static func renderRoot() -> String {
        let description = OSXRootCommand.commandDescription
        let commands: [(name: String, abstract: String)] = [
            ("query", OSXQueryCommand.commandDescription.abstract),
            ("interactive", OSXInteractiveCommand.commandDescription.abstract),
            ("action", OSXActionCommand.commandDescription.abstract),
            ("enable-ax", OSXEnableAXCommand.commandDescription.abstract),
        ]

        var lines: [String] = []
        lines.append("osx")
        if !description.abstract.isEmpty {
            lines.append(description.abstract)
        }
        lines.append("")
        lines.append("USAGE")
        lines.append("  osx <command>")
        lines.append("  osx help [command]")
        lines.append("  osx --help")
        lines.append("")
        lines.append("COMMANDS")
        for command in commands {
            let padding = String(repeating: " ", count: max(2, 13 - command.name.count))
            lines.append("  \(command.name)\(padding)\(command.abstract)")
        }

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

        return lines.joined(separator: "\n")
    }

    private static func renderCommand(title: String, abstract: String, usage: [String], command: some ParsableCommand) -> String {
        let signature = CommandSignature.describe(command).flattened()

        var lines: [String] = []
        lines.append(title)
        if !abstract.isEmpty {
            lines.append(abstract)
        }
        lines.append("")
        lines.append("USAGE")
        for line in usage {
            lines.append("  \(line)")
        }

        let argumentRows = buildArgumentRows(signature: signature)
        if !argumentRows.isEmpty {
            lines.append("")
            lines.append("ARGUMENTS")
            for row in argumentRows {
                lines.append(row)
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

    private static func buildArgumentRows(signature: CommandSignature) -> [String] {
        signature.arguments.map { argument in
            let label = argument.isOptional ? "[\(argument.label)]" : "<\(argument.label)>"
            if let help = argument.help, !help.isEmpty {
                return "  \(label)  \(help)"
            }
            return "  \(label)"
        }
    }

    private static func buildOptionRows(signature: CommandSignature) -> [String] {
        var rows: [(left: String, right: String)] = []

        for option in signature.options {
            let names = canonicalNames(from: option.names)
            guard !names.isEmpty else { continue }
            let placeholder: String
            switch option.parsing {
            case .singleValue:
                placeholder = " <value>"
            case .upToNextOption:
                placeholder = " <value...>"
            case .remaining:
                placeholder = " <arguments...>"
            }
            rows.append((names.joined(separator: ", ") + placeholder, option.help ?? ""))
        }

        for flag in signature.flags {
            let names = canonicalNames(from: flag.names)
            guard !names.isEmpty else { continue }
            rows.append((names.joined(separator: ", "), flag.help ?? ""))
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
}
