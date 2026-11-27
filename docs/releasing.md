# Releasing Guide

Releases are built by [release.yml](../.github/workflows/release.yml).
The app lives in [ShishirAravindan/uttr](https://github.com/ShishirAravindan/uttr);
the Homebrew cask lives in the separate
[ShishirAravindan/homebrew-tap](https://github.com/ShishirAravindan/homebrew-tap).

## Cutting a Release

Releases are started by hand. Merging to `main` never publishes anything, so
several PRs can land before the next release. Run the Release workflow from
[Actions](https://github.com/ShishirAravindan/uttr/actions/workflows/release.yml)
→ **Run workflow** on `main`, or from a terminal:

```bash
gh workflow run release.yml --repo ShishirAravindan/uttr -f bump=minor
```

| Input | Use |
|---|---|
| `bump` | `patch` (default), `minor`, or `major`, applied to the latest `vX.Y.Z` tag |
| `version` | An exact `X.Y.Z` instead of the bump. It must be newer than the latest tag. |
| `title` | Release title. Defaults to the latest merged PR's title without its conventional-commit prefix. |

Use a patch for fixes, a minor version for new features, and a major version for
breaking changes to settings or stored data. The workflow refuses to run from any
other branch, and refuses a version whose tag already exists.

## Automated Pipeline

1. **Version:** choose the next version from the inputs and name the release
   `uttr vX.Y.Z: <title>`.
2. **Build:** the macOS 26 runner selects Xcode 26.4.1 and builds the Release scheme
   with signing disabled into a temporary derived-data directory. The version is
   stamped into the app as `MARKETING_VERSION`, with the workflow run number as
   `CURRENT_PROJECT_VERSION`, and checked in the built `Info.plist`.
3. **Package:** zip `uttr.app` as `uttr.zip` and compute its SHA256.
4. **Tag:** push the `vX.Y.Z` tag. This happens only after the build succeeds.
5. **Publish:** create a [GitHub Release](https://github.com/ShishirAravindan/uttr/releases)
   with the release name, the ZIP, installation instructions, and hash.
6. **Update the tap:** check out `ShishirAravindan/homebrew-tap`, update
   `Casks/uttr.rb` with the version/hash, and open a `bump/uttr-v…` PR there,
   titled with the release name.

Runs share a release concurrency group and are not cancelled by another run.
Local and Debug builds keep the project's placeholder version. There is no
required `CHANGELOG.md` in this repository.

## Maintainer Review

Before merging an app change, review its PR build and the manual checks relevant
to the changed behavior. Merge with **Rebase and merge** so each commit lands on
`main` as written. After running a release:

- Inspect the Release run in [Actions](https://github.com/ShishirAravindan/uttr/actions).
- Verify the published ZIP, tag, SHA256, and the version in Settings → About.
- Review and merge the generated cask PR in the tap. Publishing the app release
  does not itself make the Homebrew update available.

The app repository's `GITHUB_TOKEN` has `contents: write` for tags and releases
and `pull-requests: read` for the default title. The separate
`HOMEBREW_TAP_TOKEN` secret is used to check out the tap and open its cask PR. A
tap-step failure can occur after the app release is already published; check
which steps completed before rerunning. Once the tag is pushed, a rerun picks
the next version after it, so finish a partly completed release by hand instead.

Users install or upgrade through:

```bash
brew tap ShishirAravindan/tap
brew install --cask uttr
# After the cask update is merged:
brew update
brew upgrade --cask uttr
```

## Local Packaging

For an isolated unsigned build, use the verification command in
[Development](development.md#building-for-distribution). Its Release product is
under the chosen derived-data directory's `Build/Products/Release/`.

```bash
cd /path/to/derived-data/Build/Products/Release
zip -r /tmp/uttr.zip uttr.app
shasum -a 256 /tmp/uttr.zip
```

`./build.sh -c Release` also builds locally, but replaces `/Applications/uttr.app`.
Local packaging does not publish a release or update the tap. The distributed
app is unsigned and not notarized; follow
[Getting Started](getting-started.md#allowing-the-app-gatekeeper) for first-launch
Gatekeeper handling.

## Troubleshooting

- **Build fails:** inspect the Xcode step and Swift Package Manager resolution.
- **Tag collision:** inspect remote tags before retrying; the workflow refuses to
  overwrite an existing tag.
- **Tap update fails:** check `HOMEBREW_TAP_TOKEN` access and whether a release
  already exists, then repair the cask update in the tap repository.
- **Homebrew still shows the old version:** confirm the cask PR was merged, then
  run `brew update` before upgrading.
