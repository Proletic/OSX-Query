# OSXQuery Query Usage

This guide is for readers with no prior chat context.
It documents both APIs:
- OXQ query API (`--app ... --selector ...`)
- OXA actions API (`--actions '...'`)

This file also captures practical defaults that worked repeatedly in live usage.

## 1. Current architecture
- Query mode discovers elements and emits refs.
- Actions mode runs programs against daemon-cached refs.
- Required lifecycle is `query+` then `action*`.
- Ref actions do not execute against raw query stdout.
- One global daemon is reused across calls.
- Treat action success as transport-level only; always verify with a query or screenshot.

## 2. OXQ query grammar (supported)

Supported selector features:
- Type selectors: role (`AXButton`) and wildcard (`*`)
- Combinators: descendant (` `), child (`>`)
- Attribute operators: `=`, `*=`, `^=`, `$=`
- Pseudos: `:has(...)`, `:not(...)`
- Selector lists: comma-separated OR

Practical grammar constraints:
- Attribute values must be quoted strings.
  - Invalid: `AXButton[enabled=true]`
  - Valid: `AXButton[enabled="true"]`
- One attribute group per compound.
  - Invalid: `AXButton[CPName="x"][enabled="true"]`
  - Valid: `AXButton[CPName="x",enabled="true"]`
- Unknown pseudos are rejected.

## 3. OXQ aliases and matching behavior

Useful aliases for matching:
- `CPName` (or `ComputedName`) is the most reliable text field.
- Also useful: `role`, `title`, `value`, `description`, `identifier`, `enabled`, `focused`.

Matching reminders:
- String matching is case-sensitive for `=`, `^=`, and `$=`.
- Fuzzy contains matching (`*=`) is case-insensitive.
- `*=""` matches any element where that attribute is present.
- Result de-duplication is by underlying AX element identity, not visible text.
- Distinct elements can share similar names and still behave differently.

## 4. Query command shape and options

Core shape:
```bash
osq --app <target> --selector "<query>" [options]
```

Actions-first quick shape:
```bash
osq --app <target> --selector "<query>" [--cache-session|--use-cached] [--limit N]
osq --actions '<statement>; <statement>; ...'
```

Most useful query options:
- `--limit <n>`: reduce noise while exploring.
- `--cache-session`: refresh/warm daemon snapshot from live UI.
- `--use-cached`: run query against warm snapshot (no refresh).
- `--show-path`: include full path for disambiguation.
- `--show-name-source`: show computed-name source.
- `--tree`: compact matched-only tree view. Prefer this when you need structural context.
- `--tree-full`: full inferred-ancestor tree view. Use this only when `--tree` is not enough and you are stuck on missing containment context.
- `--max-depth <n>`: optional traversal cap, use sparingly.

Targeting tips:
- Prefer bundle IDs for stable app targeting.
- Prefer bundle IDs for app activation too, for example: `open "net.imput.helium"`, `open "com.microsoft.Word"`.
- `focused` can be convenient for ad-hoc local checks.

## 5. High-leverage query patterns

Pattern 0: broad discovery pass
```bash
osq --app <target> --selector 'AXTextField,AXTextArea,AXComboBox' --limit 80
osq --app <target> --selector '*[CPName*="<keyword>"]' --limit 80
```

Pattern A: refine then verify
```bash
osq --app net.imput.helium \
  --selector '*[CPName="In the news"]:not(AXStaticText)' \
  --limit 20 --show-path
```

Pattern B: contextual targeting with `:has(...)`
```bash
osq --app net.imput.helium \
  --selector 'AXGroup:has(AXHeading[CPName="In the news"]) AXLink' \
  --limit 120
```

Pattern C: exclusion hygiene with `:not(...)`
```bash
osq --app net.imput.helium \
  --selector 'AXLink[CPName*="Diddy Blud"]:not([CPName*="Go to channel"])'
```

Pattern D: role-first, text-second
```bash
AXButton[CPName^="Play"]:not([enabled="false"])
```

Pattern E: stable browser address bar
```bash
AXTextField[AXDescription*="Address and search bar"]
```

Pattern F: contextual narrowing defaults
```bash
AXGroup:has(AXHeading[CPName='In the news']) AXLink
AXLink[CPName*="<target>"]:not([CPName*="Go to channel"])
```

## 6. Using `:has(...)` effectively

When to use it:
- Parent-level targeting: find containers/windows with a descendant marker.
- Context disambiguation: same label appears in multiple regions.
- Relative structure matching: enforce direct-child shape with `>`.

Core forms:
```bash
# Parent has any matching descendant
AXWindow:has(AXTextArea[CPName*="Ask anything"])

# Parent has direct child
AXGroup:has(> AXTextArea[CPName*="Ask anything"])

# Contextual result matching
AXGroup:has(AXLink[CPName*="<context>"]) AXLink[CPName*="<target>"]
```

Tips:
- Keep the inner selector specific (role + text/attribute).
- If too broad, add another constraint or a `:not(...)`.

## 7. Query workflow playbook
1. Start with broad discovery (`AXTextField,AXTextArea,AXComboBox` or `*[CPName*="..."]`).
2. Narrow with role + `CPName` + `:not(...)`.
3. Add context with `:has(...)` when ambiguity remains.
4. Verify candidate set (`--limit`, then `--show-path`).
5. Warm refs with `--cache-session` before action phase.
6. Use `--use-cached` for non-interaction follow-up queries only.

Query posture:
- Start broad, then narrow with role + `CPName` + context.
- Verify candidate sets before acting (`--limit`, then `--show-path` if needed).
- Keep using `--use-cached` until an action or UI change occurs.
- Prefer `--tree` over `--tree-full` when you want hierarchy. Compact matched-only output is usually enough and avoids unrelated wrapper nodes.
- Escalate to `--tree-full` only if compact output still leaves the parent/descendant relationship ambiguous enough that you cannot proceed confidently.
