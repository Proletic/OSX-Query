import Foundation

// GlobalAXLogger is assumed available

extension Element {
    public struct ComputedNameDetails: Equatable, Sendable {
        public let value: String
        public let source: String

        public init(value: String, source: String) {
            self.value = value
            self.source = source
        }
    }

    /// Computes a human-readable name for the element based on various attributes.
    /// This is useful for logging and debugging, and can be part of the `collectAll` output.
    @MainActor
    public func computedName() -> String? {
        self.computedNameDetails()?.value
    }

    /// Computes a human-readable name and reports the source attribute used.
    @MainActor
    public func computedNameDetails() -> ComputedNameDetails? {
        let roleName = self.role()
        lazy var valueCandidate = self.valueCandidateForComputedName()

        func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        let candidates: [(source: String, provider: () -> String?)]
        if self.isTextLikeRole(roleName) {
            candidates = [
                (valueCandidate?.source ?? AXAttributeNames.kAXValueAttribute, {
                    nonEmpty(valueCandidate?.value)
                }),
                ("AXTitle", { nonEmpty(self.title()) }),
                ("AXIdentifier", { nonEmpty(self.identifier()) }),
                ("AXDescription", { nonEmpty(self.descriptionText()) }),
                ("AXHelp", { nonEmpty(self.help()) }),
                ("AXPlaceholderValue", {
                    let placeholder = self.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute))
                    return nonEmpty(placeholder)
                }),
            ]
        } else {
            candidates = [
                ("AXTitle", { nonEmpty(self.title()) }),
                (valueCandidate?.source ?? AXAttributeNames.kAXValueAttribute, {
                    nonEmpty(valueCandidate?.value)
                }),
                ("AXIdentifier", { nonEmpty(self.identifier()) }),
                ("AXDescription", { nonEmpty(self.descriptionText()) }),
                ("AXHelp", { nonEmpty(self.help()) }),
                ("AXPlaceholderValue", {
                    let placeholder = self.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute))
                    return nonEmpty(placeholder)
                }),
            ]
        }

        for candidate in candidates {
            if let value = candidate.provider() {
                let resolved = self.logComputedName(
                    source: candidate.source,
                    value: value,
                    elementDescription: self.briefDescription(option: .raw))
                return ComputedNameDetails(value: resolved, source: candidate.source)
            }
        }

        if let roleName = nonEmpty(roleName) {
            let cleanRole = roleName.replacingOccurrences(of: "AX", with: "")
            let resolved = self.logComputedName(
                source: "AXRole",
                value: cleanRole,
                elementDescription: self.briefDescription(option: .raw))
            return ComputedNameDetails(value: resolved, source: "AXRole")
        }

        self.logMissingComputedName(elementDescription: self.briefDescription(option: .raw))
        return nil
    }

    private func logComputedName(source: String, value: String, elementDescription: @autoclosure () -> String) -> String {
        guard self.shouldEmitComputedNameDebugLogs else { return value }
        let message = [
            "ComputedName: Using \(source)",
            "'\(value)' for \(elementDescription())",
        ].joined(separator: " ")
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: message))
        return value
    }

    private func logMissingComputedName(elementDescription: @autoclosure () -> String) {
        guard self.shouldEmitComputedNameDebugLogs else { return }
        let message = [
            "ComputedName: No suitable attribute found for",
            "\(elementDescription()). Returning nil.",
        ].joined(separator: " ")
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: message))
    }

    private var shouldEmitComputedNameDebugLogs: Bool {
        GlobalAXLogger.shared.isLoggingEnabled && GlobalAXLogger.shared.detailLevel == .verbose
    }

    private func isTextLikeRole(_ role: String?) -> Bool {
        guard let role else { return false }
        switch role {
        case AXRoleNames.kAXStaticTextRole,
            AXRoleNames.kAXTextFieldRole,
            AXRoleNames.kAXTextAreaRole,
            AXRoleNames.kAXComboBoxRole:
            return true
        default:
            return false
        }
    }

    @MainActor
    private func valueCandidateForComputedName() -> ComputedNameDetails? {
        if let directValue = self.nonEmptyValueString(
            self.attribute(Attribute<String>(AXAttributeNames.kAXValueAttribute)))
        {
            let truncated = String(directValue.prefix(200))
            return ComputedNameDetails(value: truncated, source: AXAttributeNames.kAXValueAttribute)
        }

        if let normalizedValue = self.nonEmptyValueString(self.stringifyValue(self.value())) {
            let truncated = String(normalizedValue.prefix(200))
            return ComputedNameDetails(value: truncated, source: AXAttributeNames.kAXValueAttribute)
        }

        if let selectedText = self.nonEmptyValueString(self.selectedText()) {
            let truncated = String(selectedText.prefix(200))
            return ComputedNameDetails(value: truncated, source: AXAttributeNames.kAXSelectedTextAttribute)
        }

        return nil
    }

    private func nonEmptyValueString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let lowered = value.lowercased()
        if lowered == "nil" || lowered == "null" || lowered == "(null)" || lowered == "<null>" || lowered == "optional(nil)" {
            return nil
        }
        return value
    }

    private func stringifyValue(_ rawValue: Any?) -> String? {
        guard let rawValue else { return nil }
        if let string = rawValue as? String {
            return string
        }
        if let attributed = rawValue as? NSAttributedString {
            return attributed.string
        }
        if let number = rawValue as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let bool = rawValue as? Bool {
            return bool ? "true" : "false"
        }
        if let strings = rawValue as? [String] {
            return strings.joined(separator: ", ")
        }
        if let values = rawValue as? [Any] {
            let flattened = values.compactMap(self.stringifyValue)
            return flattened.isEmpty ? nil : flattened.joined(separator: ", ")
        }
        return nil
    }
}
