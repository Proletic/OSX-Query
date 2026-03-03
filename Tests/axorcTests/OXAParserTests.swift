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
            send right click to 89d32b48a;
            send drag 89d32b48a to 28e6a93cf;
            send hotkey cmd+shift+a to 28e6a93cf;
            send hotkey down to 984cb20ff;
            send scroll down to 984cb20ff;
            send scroll to 984cb20ff;
            read CPName from 28e6a93cf;
            sleep 400;
            open "Helium";
            close "Safari";
            """
        )

        #expect(program.statements.count == 13)
    }

    @Test("Parses send text as keys statement")
    func parsesSendTextAsKeysStatement() throws {
        let program = try OXAParser.parse("send text \"hello world\" as keys to 28e6a93cf;")
        #expect(program.statements.count == 1)
        #expect(program.statements[0] == .sendTextAsKeys(text: "hello world", targetRef: "28e6a93cf"))
    }

    @Test("Parses send right click statement")
    func parsesSendRightClickStatement() throws {
        let program = try OXAParser.parse("send right click to 28e6a93cf;")
        #expect(program.statements.count == 1)
        #expect(program.statements[0] == .sendRightClick(targetRef: "28e6a93cf"))
    }

    @Test("Parses send scroll into view statement")
    func parsesSendScrollIntoViewStatement() throws {
        let program = try OXAParser.parse("send scroll to 28e6a93cf;")
        #expect(program.statements.count == 1)
        #expect(program.statements[0] == .sendScrollIntoView(targetRef: "28e6a93cf"))
    }

    @Test("Parses read attribute statement")
    func parsesReadAttributeStatement() throws {
        let program = try OXAParser.parse("read CPName from 28e6a93cf;")
        #expect(program.statements.count == 1)
        #expect(program.statements[0] == .readAttribute(attributeName: "CPName", targetRef: "28e6a93cf"))
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

    @Test("Rejects legacy arrow underscore hotkey names")
    func rejectsLegacyArrowUnderscoreNames() {
        do {
            _ = try OXAParser.parse("send hotkey arrow_down to 28e6a93cf;")
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

        do {
            _ = try OXAExecutor.execute(programSource: "read CPName from 28e6a93cf;")
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
