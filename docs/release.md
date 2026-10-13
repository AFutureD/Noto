# Release

How a version of Noto ships. The build runs in a second repository,
[AFutureD/noto-releases](https://github.com/AFutureD/noto-releases), and that is where people download
from. This repository only starts it.

## The two repositories

| Repository | Holds | Secrets |
| --- | --- | --- |
| `AFutureD/Noto` | the source, and `.github/workflows/release.yml`, which dispatches a version | `RELEASES_REPO_TOKEN` |
| `AFutureD/noto-releases` | `.github/workflows/release.yml`, which builds, signs, notarises and publishes; `ExportOptions.plist`; `scripts/notarize.sh`; the Releases and the Sparkle feed | the seven signing secrets below |

The split keeps the signing secrets out of the source repository. The dispatcher needs one token. The
build repository needs everything else, and nothing in it can change the source.

## The version rule

One number names a release. The tag, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must agree, and
the workflow refuses a build where they do not. Version `0.1.0` is tagged `v0.1.0`, and both settings
read `0.1.0`. Sparkle compares `CURRENT_PROJECT_VERSION` (`CFBundleVersion`), so each release carries a
larger number than the one before.

## To cut a release

1. If MDTextKit changed, tag it in its repository and move Noto's pin to that tag.
2. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to the new version in both configurations.
3. In `CHANGELOG.md`, rename the `Unreleased` section to the version and the date, and add an empty
   `Unreleased` section above it.
4. Run the checks in [testing.md](testing.md#definition-of-done).
5. Commit and push `main`.
6. Tag and push the tag: `git tag v0.1.0 && git push origin v0.1.0`.
7. Watch <https://github.com/AFutureD/noto-releases/actions>. The release appears under
   [Releases](https://github.com/AFutureD/noto-releases/releases) after about 15 minutes.

## What the workflow does

The dispatcher sends the tag and the version to noto-releases as a `repository_dispatch` event. There,
one job on the `xcode-27` runner (only Xcode 27's `actool` compiles the Icon Composer icon):

1. Checks out Noto at the tag and validates the version rule.
2. Imports the Developer ID certificate into a temporary keychain, and installs the Developer ID
   provisioning profile "Noto Developer ID Application".
3. Archives the `Noto` scheme in Release and exports it with `ExportOptions.plist` (`developer-id`,
   manual signing, team `8GSN8K4KD9`, that profile for `app.huanan.noto`). `ARCHS` is `arm64`, so the
   app runs on Apple Silicon only.
4. Notarises and staples the app. Then packages `Noto-<version>.dmg`, and notarises and staples that.
5. Zips the stapled app as `Noto-<version>.zip`, the archive Sparkle installs.
6. Downloads the previous `appcast.xml` from the latest release and adds the new version with
   `generate_appcast`, signed with `SPARKLE_ED_PRIVATE_KEY`. The feed keeps at most five versions.
7. Writes the release notes from the commits since the previous tag.
8. Publishes the GitHub release `v<version>` with the dmg, the zip and `appcast.xml`.

An installed Noto reads `SUFeedURL`, which points at the latest release's `appcast.xml`. Each release
moves the feed.

## A dry run

Open the workflow in noto-releases, click Run workflow, give a ref and a version, and turn Publish
off. The run builds, signs and notarises, uploads the result as a workflow artifact, and publishes
nothing. Use it after a change to the workflow or the secrets. From a terminal:

```sh
gh workflow run release.yml -R AFutureD/noto-releases -f ref=main -f version=0.1.0 -f publish=false
```

## Secrets

On `AFutureD/noto-releases` (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `PROD_MACOS_CERTIFICATE_P12_BASE64` | the Developer ID Application certificate and its key, as `base64` of the `.p12` |
| `PROD_MACOS_CERTIFICATE_PASSWORD` | the password of that `.p12` |
| `APPSTORE_CONNECT_API_KEY_P8` | an App Store Connect API key (`.p8`) with the Developer role |
| `APPSTORE_CONNECT_KEY_ID` | the id of that key |
| `APPSTORE_CONNECT_ISSUER_ID` | the issuer id of the App Store Connect team |
| `SPARKLE_ED_PRIVATE_KEY` | the EdDSA private key from Sparkle's `generate_keys`; its public half is `SUPublicEDKey` in `Noto/Info.plist` |
| `DEVELOPER_ID_PROVISION_PROFILE_BASE64` | the Developer ID provisioning profile "Noto Developer ID Application", as `base64` of the `.provisionprofile` |

On `AFutureD/Noto`:

| Secret | Value |
| --- | --- |
| `RELEASES_REPO_TOKEN` | a fine-grained personal access token with Contents read and write on `AFutureD/noto-releases` only |

The iCloud entitlements in `Noto/Noto.entitlements` need the provisioning profile. Make it in the
Apple Developer portal: type Developer ID, the App ID `app.huanan.noto` with the iCloud capability
and the container `iCloud.app.huanan.noto`, and the Developer ID Application certificate of the
`.p12`. When the certificate, the container or an entitlement changes, make the profile again and
replace the secret.

A lost `SPARKLE_ED_PRIVATE_KEY` cannot be replaced. An installed Noto accepts only a feed signed with
the key that matches its `SUPublicEDKey`. Keep a copy outside GitHub.

## Sparkle

`Noto/Info.plist` carries `SUFeedURL`, `SUPublicEDKey` and `SUEnableAutomaticChecks`. The app side is
in [updates.md](features/updates.md). The Sparkle tools (`generate_keys`, `generate_appcast`,
`sign_update`) are in the resolved package after a build:
`build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/`.
