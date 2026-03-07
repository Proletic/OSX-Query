# OSXQuery

OSXQuery is a macOS UI query language and CLI for inspecting and interacting with Accessibility trees.

## What This Does

OSXQuery gives you a selector-driven way to:

- Query a running app's Accessibility tree with CSS-like selectors.
- Filter by role, attributes, and structure (child/descendant relationships).
- Use pseudo-classes like `:has(...)` and `:not(...)`.
- Run interactions on matched results (`click`, `press`, `focus`, `set-value`, submit flows).
- Explore results interactively in a full-screen terminal TUI.
- Warm and reuse prefetched snapshots for faster repeated queries.
- Force-enable `AXEnhancedUserInterface` and `AXManualAccessibility` on a running app when needed.

## Why We Made It

The current architecture is optimized around three practical goals:

1. Faster, clearer UI targeting
   OSXQuery replaces verbose locator-style matching with a compact selector language (`OXQParser`, `OXQSelectorEngine`).

2. Better human workflow
   There is a dedicated interactive selector mode (`-i`) with query editing, result navigation, search, and inline interactions.

3. Lower latency for repeated automation
   Selector execution prefetches attributes in batches and supports daemon-backed warm snapshots (`--cache-session`, `--use-cached`).

## Requirements

- macOS 14+
- Swift 6.2 toolchain
- Accessibility permissions for the process running `osx`

## Installation

### Homebrew

This repo includes a formula at `Formula/osx.rb`.

Quick install:

```bash
brew tap moulik-budhiraja/osx-query https://github.com/Moulik-Budhiraja/OSX-Query
brew install --HEAD moulik-budhiraja/osx-query/osx
```

Install from a local checkout:

```bash
brew tap moulik-budhiraja/osx-query /absolute/path/to/OSXQuery
brew install --HEAD moulik-budhiraja/osx-query/osx
```

Note: because there are currently no git tags, the formula is head-only and tracks `main`.

## Build And Run

```bash
# Build
swift build

# Show help
swift run osx --help

# Query example
swift run osx query --app focused "AXWindow AXButton" --limit 20
```

## Accessibility Permissions

Without Accessibility permission, queries/interactions may fail or return no useful data.

The library includes helpers (`AXPermissionHelpers`) to:

- check current permission (`hasAccessibilityPermissions()`)
- request prompt (`askForAccessibilityIfNeeded()` / `requestPermissions()`)
- watch permission changes (`permissionChanges(...)`)

## CLI Overview

Primary commands:

1. Query

```bash
osx query --app <target> "<query>" [options]
```

2. Interactive

```bash
osx interactive <app> [options]
```

3. Action

```bash
osx action '<program>'
```

4. AX exposure

```bash
osx enable-ax <bundle-id>
```

### App Target Resolution

`query --app` and `interactive <app>` accept:

- bundle id (`com.apple.TextEdit`)
- exact running app name (case-insensitive match)
- PID
- `focused` (frontmost app)

### Option Reference (Public CLI)

- `query --app <target> <query>`: run a selector query.
- `interactive <app>`: open the full-screen TUI query workflow.
- `action <program>`: execute an OXA action program against cached refs.
- `--max-depth <n>`: maximum selector traversal depth. Default is unlimited.
- `--limit <n>`: max rows to print. Default `50`; `0` means no cap.
- `--show-path`: include generated path for each shown match.
- `--show-name-source`: include computed name source (for example `AXTitle`).
- `--no-color`: disable ANSI role/status colors.
- `--cache-session`: query through cache daemon and refresh warm snapshot.
- `--use-cached`: query through cache daemon using existing warm snapshot only.
- `enable-ax <bundle-id>`: run AX exposure flow.
- `--debug`, `--verbose`: enable normal/verbose diagnostic logging.
- `-h`, `--help` or `help`: print CLI usage.

For full CLI documentation, see [docs/cli.md](docs/cli.md).

## Selector Syntax

View the full syntax reference at [docs/selector-syntax.md](docs/selector-syntax.md).

Quick examples:

```bash
# All buttons under any window
osx query --app TextEdit "AXWindow AXButton"

# Parent that has a direct child text field
osx query --app TextEdit "AXGroup:has(> AXTextField)"

# Disjunction
osx query --app TextEdit "AXTextArea, AXTextField, AXComboBox"
```

Selector mode output format:

- `stats ...` line (app, selector, elapsed, traversed, matched, shown)
- result rows (`AXButton ...`)
- optional `ref=...` tokens per row when refs are available (for OXA actions)
- optional full path lines with `--show-path`
- compact tree rendering with `--tree` to show matched nodes only
- full inferred-ancestor tree rendering with `--tree-full`

Use:

- `--show-name-source` to include where computed name came from (for example `AXTitle`)
- `--no-color` to disable ANSI output
- `--tree` to render selector matches with compact matched-only branches (`└●─` marks collapsed unmatched intermediates)
- `--tree-full` to render the full inferred ancestor chain

## Library Usage (Swift)

The query app integration (`~/dev/osxqueryapp`) uses:

- `OXQParser` for syntax parsing
- `OXQSelectorEngine` for selector evaluation
- `OXQQueryMemoizationContext` for cached reads during evaluation

Minimal parser example:

```swift
import OSXQuery

let ast = try OXQParser().parse("AXGroup:has(> AXTextField) AXButton")
print(ast.selectors.count)
```

Selector evaluation example:

```swift
import OSXQuery

@MainActor
func runSelectorQuery() throws {
    guard let root = Element.focusedApplication() else { return }

    let children: (Element) -> [Element] = { element in
        element.children(strict: false, includeApplicationExtras: element == root) ?? []
    }
    let role: (Element) -> String? = { element in
        element.role()
    }
    let attributeValue: (Element, String) -> String? = { element, attributeName in
        let canonical = PathUtils.attributeKeyMappings[attributeName.lowercased()] ?? attributeName

        if canonical == AXAttributeNames.kAXRoleAttribute {
            return element.role()
        }
        if let string: String = element.attribute(Attribute<String>(canonical)) {
            return string
        }
        if let bool: Bool = element.attribute(Attribute<Bool>(canonical)) {
            return bool ? "true" : "false"
        }
        if let number: NSNumber = element.attribute(Attribute<NSNumber>(canonical)) {
            return number.stringValue
        }
        return nil
    }

    let selectorEngine = OXQSelectorEngine<Element>(
        children: children,
        role: role,
        attributeValue: attributeValue)

    let memoizationContext = OXQQueryMemoizationContext<Element>(
        childrenProvider: children,
        roleProvider: role,
        attributeValueProvider: attributeValue)

    let evaluation = try selectorEngine.findAllWithMetrics(
        matching: "AXWindow AXButton[AXTitle*=\"Save\"]",
        from: root,
        maxDepth: 20,
        memoizationContext: memoizationContext)

    print("matched:", evaluation.matches.count)
    print("traversed:", evaluation.traversedNodeCount)
}
```

The command-envelope API (`OSXQuery.shared.runCommand(...)`) remains available, but selector mode and the query app both use the selector engine path above.
