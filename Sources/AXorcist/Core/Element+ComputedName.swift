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
        let elementDescription = briefDescription(option: .raw)

        func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        let candidates: [(source: String, provider: () -> String?)] = [
            ("AXTitle", { nonEmpty(self.title()) }),
            ("AXValue", {
                guard let rawValue = self.value() as? String, !rawValue.isEmpty else { return nil }
                return String(rawValue.prefix(50))
            }),
            ("AXIdentifier", { nonEmpty(self.identifier()) }),
            ("AXDescription", { nonEmpty(self.descriptionText()) }),
            ("AXHelp", { nonEmpty(self.help()) }),
            ("AXPlaceholderValue", {
                let placeholder = self.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute))
                return nonEmpty(placeholder)
            }),
        ]

        for candidate in candidates {
            if let value = candidate.provider() {
                let resolved = self.logComputedName(
                    source: candidate.source,
                    value: value,
                    elementDescription: elementDescription)
                return ComputedNameDetails(value: resolved, source: candidate.source)
            }
        }

        if let roleName = nonEmpty(role()) {
            let cleanRole = roleName.replacingOccurrences(of: "AX", with: "")
            let resolved = self.logComputedName(
                source: "AXRole",
                value: cleanRole,
                elementDescription: elementDescription)
            return ComputedNameDetails(value: resolved, source: "AXRole")
        }

        self.logMissingComputedName(elementDescription: elementDescription)
        return nil
    }

    private func logComputedName(source: String, value: String, elementDescription: String) -> String {
        let message = [
            "ComputedName: Using \(source)",
            "'\(value)' for \(elementDescription)",
        ].joined(separator: " ")
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: message))
        return value
    }

    private func logMissingComputedName(elementDescription: String) {
        let message = [
            "ComputedName: No suitable attribute found for",
            "\(elementDescription). Returning nil.",
        ].joined(separator: " ")
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: message))
    }
}
