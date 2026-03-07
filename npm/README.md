# osx-query

`osx-query` installs the native `osx` CLI for querying and interacting with macOS Accessibility trees.

The npm package is a thin installer. During `npm i -g osx-query`, it downloads the signed and notarized binary that matches your Mac from the project's GitHub Releases.

## Install

```bash
npm i -g osx-query
```

After install:

```bash
osx --help
```

## What You Get

- CSS-like querying of Accessibility trees
- Actions against matched elements
- Interactive query mode for exploring app structure
- Signed and notarized binaries for:
  - macOS `arm64`
  - macOS `x64`

## Examples

Query the focused app:

```bash
osx query --app focused "AXWindow AXButton"
```

Query a specific app:

```bash
osx query --app TextEdit "AXTextArea,AXTextField"
```

Open the interactive selector UI:

```bash
osx interactive TextEdit
```

## Requirements

- macOS
- Accessibility permission for the process running `osx`

If queries return nothing useful, grant Accessibility access to your terminal app in:

`System Settings -> Privacy & Security -> Accessibility`

## Optional Codex Skill

On first run, `osx` can optionally prompt to run:

```bash
npx skills add Moulik-Budhiraja/OSX-Query
```

That step is optional and only appears once in an interactive terminal. If you skip it, you can still run it later yourself.

To suppress the prompt entirely:

```bash
OSX_QUERY_SKIP_SKILLS_PROMPT=1 osx --help
```
