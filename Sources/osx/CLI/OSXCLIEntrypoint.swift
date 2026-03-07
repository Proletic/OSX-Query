import Foundation
@preconcurrency import Commander

enum OSXCLIEntrypoint {
    static func run(arguments: [String]) async -> Int32 {
        if let first = arguments.first, first.hasPrefix("-"), !OSXHelpRequestDetector.isHelpToken(first) {
            Self.printError(message: "Unknown option \(first)")
            return ExitCode.failure.rawValue
        }

        if OSXHelpRequestDetector.isHelpRequest(arguments: arguments) {
            print(OSXHelpFormatter.render(arguments: arguments))
            return ExitCode.success.rawValue
        }

        do {
            let invocation = try OSXCLICommandRegistry.program.resolve(argv: ["osx"] + arguments)
            try await OSXCLICommandRegistry.run(invocation: invocation)
            return ExitCode.success.rawValue
        } catch let error as CommanderProgramError {
            Self.printError(message: error.description)
            return ExitCode.failure.rawValue
        } catch let error as CommanderError {
            Self.printError(message: error.description)
            return ExitCode.failure.rawValue
        } catch let validation as ValidationError {
            Self.printError(message: validation.description)
            return ExitCode.failure.rawValue
        } catch let exitCode as ExitCode {
            return exitCode.rawValue
        } catch {
            Self.printError(message: "\(error)")
            return ExitCode.failure.rawValue
        }
    }

    private static func printError(message: String) {
        fputs("error: \(message)\n", stderr)
        fputs("Run `osx --help` for usage.\n", stderr)
        fflush(stderr)
    }
}

enum OSXCLICommandRegistry {
    static let program = Program(descriptors: [descriptor(for: OSXRootCommand.self)])

    static func run(invocation: CommandInvocation) async throws {
        switch invocation.path {
        case ["osx", "query"]:
            var command = OSXQueryCommand()
            try command.apply(parsedValues: invocation.parsedValues)
            try await command.run()
        case ["osx", "interactive"]:
            var command = OSXInteractiveCommand()
            try command.apply(parsedValues: invocation.parsedValues)
            try await command.run()
        case ["osx", "action"]:
            var command = OSXActionCommand()
            try command.apply(parsedValues: invocation.parsedValues)
            try await command.run()
        case ["osx", "enable-ax"]:
            var command = OSXEnableAXCommand()
            try command.apply(parsedValues: invocation.parsedValues)
            try await command.run()
        case ["osx", "selector-cache-daemon"]:
            var command = OSXSelectorCacheDaemonCommand()
            try command.apply(parsedValues: invocation.parsedValues)
            try await command.run()
        default:
            throw ValidationError("Unknown command path: \(invocation.path.joined(separator: " "))")
        }
    }

    private static func descriptor(for type: any ParsableCommand.Type) -> CommandDescriptor {
        let description = type.commandDescription
        let signature = CommandSignature.describe(type.init()).flattened()
        let subcommands = description.subcommands.map { descriptor(for: $0) }
        return CommandDescriptor(
            name: description.commandName ?? String(describing: type),
            abstract: description.abstract,
            discussion: description.discussion,
            signature: signature,
            subcommands: subcommands,
            defaultSubcommandName: description.defaultSubcommand?.commandDescription.commandName)
    }
}

enum OSXHelpRequestDetector {
    static func isHelpRequest(arguments: [String]) -> Bool {
        if arguments.isEmpty {
            return false
        }

        if let first = arguments.first, first == "help" {
            return true
        }

        return arguments.contains(where: isHelpToken)
    }

    static func requestedCommandPath(arguments: [String]) -> [String] {
        if arguments.first == "help" {
            return Array(arguments.dropFirst().prefix { !$0.hasPrefix("-") })
        }

        return arguments.prefix { !isHelpToken($0) && !$0.hasPrefix("-") }
    }

    static func isHelpToken(_ argument: String) -> Bool {
        argument == "--help" || argument == "-h"
    }
}
