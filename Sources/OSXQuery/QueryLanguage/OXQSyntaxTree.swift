import Foundation

public struct OXQSyntaxTree: Equatable, Hashable, Sendable {
    public init(selectors: [OXQSelector]) {
        self.selectors = selectors
    }

    public let selectors: [OXQSelector]
}

public struct OXQSelector: Equatable, Hashable, Sendable {
    public init(leading: OXQCompound, links: [OXQSelectorLink]) {
        self.leading = leading
        self.links = links
    }

    public let leading: OXQCompound
    public let links: [OXQSelectorLink]
}

public struct OXQSelectorLink: Equatable, Hashable, Sendable {
    public init(combinator: OXQCombinator, compound: OXQCompound) {
        self.combinator = combinator
        self.compound = compound
    }

    public let combinator: OXQCombinator
    public let compound: OXQCompound
}

public enum OXQCombinator: String, Equatable, Hashable, Sendable {
    case child = ">"
    case descendant = " "
}

public struct OXQCompound: Equatable, Hashable, Sendable {
    public init(typeSelector: OXQTypeSelector?, attributes: [OXQAttributeMatch], pseudos: [OXQPseudoClass]) {
        self.typeSelector = typeSelector
        self.attributes = attributes
        self.pseudos = pseudos
    }

    public let typeSelector: OXQTypeSelector?
    public let attributes: [OXQAttributeMatch]
    public let pseudos: [OXQPseudoClass]
}

public enum OXQTypeSelector: Equatable, Hashable, Sendable {
    case wildcard
    case role(String)
}

public struct OXQAttributeMatch: Equatable, Hashable, Sendable {
    public init(name: String, op: OXQAttributeOperator, value: String) {
        self.name = name
        self.op = op
        self.value = value
    }

    public let name: String
    public let op: OXQAttributeOperator
    public let value: String
}

public enum OXQAttributeOperator: String, Equatable, Hashable, Sendable {
    case equals = "="
    case contains = "*="
    case startsWith = "^="
    case endsWith = "$="
}

public enum OXQPseudoClass: Equatable, Hashable, Sendable {
    case has(argument: OXQHasArgument)
    case not(selectors: [OXQSelector])
}

public enum OXQHasArgument: Equatable, Hashable, Sendable {
    case selectors([OXQSelector])
    case relativeSelectors([OXQRelativeSelector])
}

public struct OXQRelativeSelector: Equatable, Hashable, Sendable {
    public init(leadingCombinator: OXQCombinator?, selector: OXQSelector) {
        self.leadingCombinator = leadingCombinator
        self.selector = selector
    }

    public let leadingCombinator: OXQCombinator?
    public let selector: OXQSelector
}
