## CLI Reference

## Selector Query Mode

```bash
osx query --app <target> "<query>" [options]
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
osx query --app TextEdit "AXWindow AXButton" --limit 20 --show-path
```

## Interactive Selector Mode

```bash
osx interactive <app> [options]
```

Interactive mode opens a full-screen TUI for editing selectors, running queries, navigating results, and triggering inline actions.

## OXA Action Mode

Run OXA actions against cached references from a previous cache-daemon query.

```bash
# 1) Build/refresh snapshot and refs
osx query --app TextEdit "AXButton" --cache-session

# 2) Execute OXA program against ref ids from query output (ref=...)
osx action 'send click to 28e6a93cf;'
```

Notes:

- If no warm snapshot exists, action mode fails with a cache-daemon error.

## AX Exposure Mode

```bash
osx enable-ax com.apple.TextEdit
```

This temporarily focuses the app, applies `AXEnhancedUserInterface=true` and `AXManualAccessibility=true`, then restores previous focus.

## Logging And Help

```bash
osx --help
osx help
osx query --app focused "AXWindow" --debug
osx query --app focused "AXWindow" --verbose
```
