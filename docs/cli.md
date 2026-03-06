## CLI Reference

## Selector Query Mode

```bash
osq --app <target> --selector "<query>" [options]
```

Common options:

- `--max-depth <n>` limit traversal depth (`0` or omitted means unlimited)
- `--limit <n>` max rows shown (`0` means no cap)
- `--show-path` include generated path per result row
- `--show-name-source` include computed name source
- `--tree` render selector matches as a compact matched-only tree
- `--tree-full` render selector matches as a full tree with inferred unmatched ancestors
- `--no-color` disable ANSI output
- `--cache-session` route query through cache daemon and refresh snapshot
- `--use-cached` route query through cache daemon and require warm snapshot

Example:

```bash
osq --app TextEdit --selector "AXWindow AXButton" --limit 20 --show-path
```

## Interactive Selector Mode

```bash
osq --app <target> -i
# or
osq --app <target> --selector -i
```

Interactive mode opens a full-screen TUI for editing selectors, running queries, navigating results, and triggering inline actions.

## OXA Action Mode

Run OXA actions against cached references from a previous cache-daemon query.

```bash
# 1) Build/refresh snapshot and refs
osq --app TextEdit --selector "AXButton" --cache-session

# 2) Execute OXA program against ref ids from query output (ref=...)
osq --actions 'send click to 28e6a93cf;'
```

Notes:

- Action mode cannot be combined with selector flags or `--enable-ax`.
- If no warm snapshot exists, action mode fails with a cache-daemon error.

## AX Exposure Mode

```bash
osq --enable-ax com.apple.TextEdit
```

This temporarily focuses the app, applies `AXEnhancedUserInterface=true` and `AXManualAccessibility=true`, then restores previous focus.

## Logging And Help

```bash
osq --help
osq help
osq --app focused --selector "AXWindow" --debug
osq --app focused --selector "AXWindow" --verbose
```
