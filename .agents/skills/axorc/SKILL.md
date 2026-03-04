---
name: axorc
description: Use as a computer-use tool when an agent must interact with desktop UIs, web apps, or browser workflows via AXORC. Apply for querying UI element trees, resolving stable references, and executing actions with verification; also use in automated tests where UI interaction is required to validate other systems or end-to-end behavior.
---

# AXORC

## Purpose

Use AXORC as a computer-use tool when an agent must interact with desktop UIs, browser/web workflows, or UI-driven test flows used to validate other systems.
When browser interaction is required, use the user's default browser unless the user explicitly asks for a specific browser.

## Mandatory Pre-Read (Do Not Skip)

Read both documents in full before executing any `axorc` command:
- [AXORC Query Usage](references/axorc-query-usage.md)
- [AXORC Actions Usage](references/axorc-actions-usage.md)

If either file is missing at these relative paths, stop and locate them first. Do not execute `axorc` until both are read completely.
Treat those two usage docs as the source of truth for all command syntax, workflow sequencing, and troubleshooting details.

## Screenshot Validation Policy (Required)

Use AXORC together with screenshots whenever state is expected to change meaningfully.

Capture screenshots in these cases:
- Navigating to a new page or app state that could differ from expectation.
- Executing non-undoable or high-impact actions.
- Performing destructive actions (delete, submit, close, overwrite, send).
- Resolving ambiguity when multiple matching elements look similar.

Screenshot file handling:
- Save screenshots to temporary directories by default (for example, under `/tmp`).
- Clean up screenshot files after verification is complete.
- Keep screenshots only when the user explicitly asks to retain them.

Before any non-undoable action, capture clear evidence of the intended target and resulting state with screenshots. If the result is unexpected, stop and reassess before continuing.
