import Foundation
@preconcurrency import Commander

enum AXORCCLIEntrypoint {
    static func run(arguments: [String]) async -> Int32 {
        if AXORCHelpRequestDetector.isHelpRequest(arguments: arguments) {
            print(AXORCHelpFormatter.render())
            return ExitCode.success.rawValue
        }

        do {
            let parsedValues = try AXORCCommand.parseCommandLineArguments(arguments: arguments)
            var command = AXORCCommand()
            try command.apply(parsedValues: parsedValues)
            try await command.run()
            return ExitCode.success.rawValue
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
        fputs("Run `axorc --help` for usage.\n", stderr)
        fflush(stderr)
    }
}

private enum AXORCHelpRequestDetector {
    static func isHelpRequest(arguments: [String]) -> Bool {
        if arguments.contains("--help") || arguments.contains("-h") {
            return true
        }

        if let first = arguments.first, first == "help" {
            return true
        }

        return false
    }
}
