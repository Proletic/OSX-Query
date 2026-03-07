# Releasing

This project ships a native macOS CLI binary. The release flow is:

1. build `osx` for `arm64` and `x86_64`
2. sign each binary with `Developer ID Application`
3. package each signed binary as a `.zip`
4. notarize each archive with `notarytool`
5. attach release assets to a GitHub release
6. publish the npm wrapper package

## Local Prerequisites

- Apple Developer membership with `Developer ID Application`
- The signing certificate installed in your login keychain
- Xcode command line tools with `codesign` and `notarytool`

## Environment Variables

The scripts support these variables:

- `DEVELOPER_ID_APPLICATION`
  - Optional explicit signing identity. If omitted, the first local `Developer ID Application` identity is used.
- `NOTARIZE=1`
  - Notarize archives after building and signing.
- `NOTARY_PROFILE`
  - Optional `notarytool` keychain profile name. Default: `osx-query-notary`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

If `NOTARY_PROFILE` is missing from the keychain, `scripts/notarize.sh` can create it from `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.

## Local Usage

Build and sign both release archives:

```bash
scripts/release-macos.sh v0.1.0
```

Build, sign, and notarize:

```bash
NOTARIZE=1 \
APPLE_ID="your-apple-id@example.com" \
APPLE_APP_SPECIFIC_PASSWORD="app-specific-password" \
APPLE_TEAM_ID="TEAMID1234" \
scripts/release-macos.sh v0.1.0
```

Artifacts are written to `dist/<version>/`.

## GitHub Actions Secrets

The release workflow expects these secrets:

- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`
- `MACOS_CERTIFICATE_P12`
  - Base64-encoded `.p12` containing your `Developer ID Application` certificate
- `MACOS_CERTIFICATE_PASSWORD`
  - Password for the `.p12`
- `DEVELOPER_ID_APPLICATION`
  - Optional explicit identity name

## Notes

- The notarized artifact here is a `.zip`, which is suitable for binary distribution and later npm-based download flows.
- For direct installer distribution, add a signed `.pkg` or `.dmg` later.

## npm Publishing

The npm wrapper package lives in `npm/` and installs the native CLI from GitHub Releases.

Publish flow:

1. confirm the GitHub release exists for the same version
2. sync the source and npm version metadata
3. publish from `npm/`

```bash
./scripts/set-version.sh v0.1.2
cd npm
npm publish --access public
```

Users then install with:

```bash
npm i -g osx-query
```
