import Testing
@testable import axorc

@Suite("OXA Parser")
struct OXAParserTests {
    @Test("Parses supported statements")
    func parsesSupportedStatements() throws {
        let program = try OXAParser.parse(
            """
            send text "hello" to 28e6a93cf;
            send text "typed" as keys to 28e6a93cf;
            send click to 89d32b48a;
            send drag 89d32b48a to 28e6a93cf;
            send hotkey cmd+shift+a to 28e6a93cf;
            send hotkey arrow_down to 984cb20ff;
            send scroll down to 984cb20ff;
            sleep 400;
            open "Helium";
            close "Safari";
            """
        )

        #expect(program.statements.count == 10)
    }

    @Test("Parses send text as keys statement")
    func parsesSendTextAsKeysStatement() throws {
        let program = try OXAParser.parse("send text \"hello world\" as keys to 28e6a93cf;")
        #expect(program.statements.count == 1)
        #expect(program.statements[0] == .sendTextAsKeys(text: "hello world", targetRef: "28e6a93cf"))
    }

    @Test("Rejects element references that are not 9 hex characters")
    func rejectsInvalidElementReferenceLength() {
        do {
            _ = try OXAParser.parse("send click to 1234abcd;")
            Issue.record("Expected parser failure")
        } catch let error as OXAActionError {
            switch error {
            case .parse:
                break
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects hotkey when base key is not last")
    func rejectsHotkeyBaseKeyNotLast() {
        do {
            _ = try OXAParser.parse("send hotkey a+cmd to 28e6a93cf;")
            Issue.record("Expected parser failure")
        } catch let error as OXAActionError {
            switch error {
            case .parse:
                break
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rejects hotkey with multiple base keys")
    func rejectsHotkeyMultipleBaseKeys() {
        do {
            _ = try OXAParser.parse("send hotkey cmd+a+b to 28e6a93cf;")
            Issue.record("Expected parser failure")
        } catch let error as OXAActionError {
            switch error {
            case .parse:
                break
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Allows hotkey with only base key")
    func allowsSingleBaseKeyHotkey() throws {
        let program = try OXAParser.parse("send hotkey enter to 28e6a93cf;")
        #expect(program.statements.count == 1)
    }

    @MainActor
    @Test("Executor requires snapshot for element-targeted actions")
    func executorRequiresSnapshotForElementActions() {
        selectorQueryInvalidateCaches()

        do {
            _ = try OXAExecutor.execute(programSource: "send click to 28e6a93cf;")
            Issue.record("Expected runtime failure")
        } catch let error as OXAActionError {
            switch error {
            case .noSnapshot:
                break
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
