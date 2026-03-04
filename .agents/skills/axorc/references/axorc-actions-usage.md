# AXORC Actions Usage

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


## 2. Daily workflow (recommended)
1. Query with `--cache-session` to warm/update refs.
2. Run one short action program with those refs.
3. Re-query with `--cache-session` after any UI-changing action.
4. Use `--use-cached` only for back-to-back read-only follow-up queries.

Example:
```bash
# Warm refs on current UI
axorc --app net.imput.helium --selector 'AXTextField,AXWebArea' --cache-session

# Act
axorc --actions 'send text "https://en.wikipedia.org/wiki/Main_Page" to 063701191; send hotkey enter to 063701191;'

# UI changed => refresh refs
axorc --app net.imput.helium --selector 'AXWebArea,AXLink' --cache-session --limit 80

# No action in between => use cached for fast refinement
axorc --app net.imput.helium --selector 'AXLink[CPName*="In the news"]' --use-cached
```

## 3. `--actions` grammar reference

An actions program is a semicolon-terminated statement list.

Supported statements:
```txt
send text "..." to <ref>;
send text "..." as keys to <ref>;
send click to <ref>;
send right click to <ref>;
send drag <srcRef> to <dstRef>;
send hotkey <chord> to <ref>;
send scroll up|down|left|right to <ref>;
send scroll to <ref>;
read <attributeName> from <ref>;
sleep <milliseconds>;
open "AppNameOrBundleID";
close "AppNameOrBundleID";
```

Action statements used most often:
```bash
# App lifecycle
open "net.imput.helium";
close "com.microsoft.Word";

# Element actions
send click to <ref>;
send text "..." to <ref>;
send text "..." as keys to <ref>;
send hotkey cmd+a to <ref>;
send scroll down to <ref>;
send scroll to <ref>;
sleep 100;
```

Ref format:
- Exactly 9 hex chars (example: `063701895`).

Note:
- Clicks can sometimes miss, so it's a good idea to try again, maybe with a more precise selector before completely changing approach.

## 4. Hotkey spec (current)

Format:
```txt
send hotkey <modifiers+base> to <ref>;
```

Modifiers (optional, unique, first):
- `cmd`
- `ctrl`
- `alt`
- `shift`
- `fn`

Base key (required, last, exactly one):
- Single alphanumeric: `a-z`, `0-9`
- Function keys: `f1` to `f24`
- Named keys:
  - `enter`
  - `tab`
  - `space`
  - `escape`
  - `backspace`
  - `delete`
  - `home`
  - `end`
  - `page_up`
  - `page_down`
  - `up`
  - `down`
  - `left`
  - `right`

Examples:
```bash
send hotkey enter to 063701191;
send hotkey cmd+a to 063701895;
send hotkey cmd+down to 065701701;
send hotkey shift+tab to 063701895;
```

## 5. Text entry modes

`send text "..." to <ref>;`
- Good first attempt for standard text fields.
- Uses focus fallback + value-setting behavior.
- Can be unreliable in rich editors but should be the first attempt at typing.

`send text "..." as keys to <ref>;`
- Types like per-key input.
- Preferred for rich editors and punctuation-sensitive content.

## 6. Additional action modes

`send right click to <ref>;`
- Right-clicks the element center (context menu path).

`send scroll to <ref>;`
- Calls AX `AXScrollToVisible` on the target element.
- No visibility pre-check and no wheel-scroll fallback.
- If unavailable or it fails, action returns an explicit runtime error.

`read <attributeName> from <ref>;`
- Reads and prints the full attribute value (can be useful to grep from).
- Supports aliases including `CPName`.

## 7. Cache, refs, and phase boundaries

Best-practice policy:
1. Start a phase with `--cache-session`.
2. Use `--use-cached` for back-to-back read-only queries.
3. After any UI-changing action, run a fresh `--cache-session`.

This is the reliable loop:
```txt
query (--cache-session) -> action program -> query (--cache-session) -> ...
```

Validated behavior:
- `query+` then `action*` is strictly required for ref actions.
- Refs are ephemeral and can go stale quickly.
- `--use-cached` is ideal for non-interaction follow-up queries.
- After any interaction or expected UI change, refresh with `--cache-session`.

## 8. Timing strategy
- Start with `sleep 100` for intra-program waits.
- Avoid trailing sleeps by default.
- Increase above 100 only when behavior proves unstable.

## 9. Quoting and parser pitfalls
- `send text` string literals are double-quoted.
- Nested unescaped double quotes can break parsing.
- For embedded quoted phrases, either escape carefully or use single quotes in content.

Example:
```bash
axorc --actions "send text \"He stated deep concern for 'a significant number of children and civilians' ...\" as keys to 0637027b0;"
```

## 10. Failure modes and fixes
- `No cached query snapshot available`
  - Run a new query with `--cache-session`.
- `Unknown element reference`
  - Re-query to refresh refs.
- Action returns `ok` but UI did not change
  - Re-verify target, focus, and post-action state with query/screenshot.
- Text missing in editor
  - Switch from `send text ... to` to `send text ... as keys to`.
- `AXScrollToVisible is not supported for <ref>`
  - Target element does not expose that AX action.
- `AXScrollToVisible failed for <ref>: ...`
  - AX action failed at runtime; re-query and validate the ref and UI state.

## 11. End-to-end starter template
```bash
# 1) Warm refs from current UI
axorc --app net.imput.helium \
  --selector 'AXTextField[AXDescription*="Address and search bar"],AXWebArea' \
  --cache-session --limit 20

# 2) Navigate
axorc --actions 'send text "https://en.wikipedia.org/wiki/Main_Page" to 063701191; send hotkey enter to 063701191;'

# 3) Re-query after UI change
axorc --app net.imput.helium \
  --selector 'AXHeading[CPName="In the news"],AXLink' \
  --cache-session --limit 200

# 4) Click target link
axorc --actions 'send click to 072701121;'

# 5) Continue with query/action loop
axorc --app net.imput.helium --selector 'AXWebArea,AXHeading' --cache-session --limit 60
```
