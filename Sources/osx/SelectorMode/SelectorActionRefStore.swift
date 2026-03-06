import OSXQuery
import Foundation

@MainActor
enum SelectorActionRefStore {
    private(set) static var hasSnapshot = false
    private(set) static var snapshotAppPID: pid_t?
    private static var elementsByReference: [String: Element] = [:]
    private static var frameByReference: [String: CGRect] = [:]
    private static var parentReferenceByReference: [String: String] = [:]
    private static var roleByReference: [String: String] = [:]

    static func replace(
        with elementsByReference: [String: Element],
        appPID: pid_t?,
        frameByReference: [String: CGRect] = [:],
        parentReferenceByReference: [String: String] = [:],
        roleByReference: [String: String] = [:])
    {
        self.elementsByReference = Dictionary(
            uniqueKeysWithValues: elementsByReference.map { ($0.key.lowercased(), $0.value) })
        self.snapshotAppPID = appPID
        self.frameByReference = Dictionary(uniqueKeysWithValues: frameByReference.map { ($0.key.lowercased(), $0.value) })
        self.parentReferenceByReference = Dictionary(
            uniqueKeysWithValues: parentReferenceByReference.map { ($0.key.lowercased(), $0.value.lowercased()) })
        self.roleByReference = Dictionary(uniqueKeysWithValues: roleByReference.map { ($0.key.lowercased(), $0.value) })
        self.hasSnapshot = true
    }

    static func clear() {
        self.elementsByReference = [:]
        self.snapshotAppPID = nil
        self.frameByReference = [:]
        self.parentReferenceByReference = [:]
        self.roleByReference = [:]
        self.hasSnapshot = false
    }

    static func element(for reference: String) -> Element? {
        self.elementsByReference[reference.lowercased()]
    }

    static func frame(for reference: String) -> CGRect? {
        self.frameByReference[reference.lowercased()]
    }

    static func parentReference(for reference: String) -> String? {
        self.parentReferenceByReference[reference.lowercased()]
    }

    static func role(for reference: String) -> String? {
        self.roleByReference[reference.lowercased()]
    }
}
