# osx-query

Install:

```bash
npm i -g osx-query
```

This package downloads the signed and notarized native `osx` CLI from the matching GitHub release for your macOS architecture.

Example:

```bash
osx query --app focused "AXWindow AXButton"
```

Supported platforms:

- macOS `arm64`
- macOS `x64`

