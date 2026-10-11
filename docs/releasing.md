# Releasing Guide

Releases are automated by [release.yml](../.github/workflows/release.yml).
The app lives in [ShishirAravindan/uttr](https://github.com/ShishirAravindan/uttr);
the Homebrew cask lives in the separate
[ShishirAravindan/homebrew-tap](https://github.com/ShishirAravindan/homebrew-tap).

## What Starts a Release

A push to `main` starts the release workflow when it changes any of these inputs:

- `Swift/**`
- `Assets.xcassets/**`
- `uttr.xcodeproj/**` (including resolved packages and the shared scheme)
- `uttr-Info.plist` or `uttr.entitlements`
- `build.sh`

Documentation, diagram, agent-guidance, test-only, and workflow-only changes do
not start a release. A mixed change containing an app/build input does. Keep the
workflow's path list in sync when introducing a new build input. PR builds still
run independently of this release filter and accept any PR base branch.

## Automated Pipeline

1. **Build:** the macOS 14 runner selects Xcode 16.1 and builds the Release scheme
   with signing disabled into a temporary derived-data directory.
2. **Package:** zip `uttr.app` as `uttr.zip` and compute its SHA256.
3. **Tag:** read the latest `vMAJOR.MINOR.PATCH` tag, increment its patch component,
   and push the new tag. With no matching tags, the starting value is `v0.0.0`.
   The workflow refuses an existing next tag. Runs share a release concurrency
   group and are not cancelled when another push arrives.
4. **Publish:** create a [GitHub Release](https://github.com/ShishirAravindan/uttr/releases)
   containing the ZIP, installation instructions, and hash.
5. **Update the tap:** check out `ShishirAravindan/homebrew-tap`, update
   `Casks/uttr.rb` with the version/hash, and open a `bump/uttr-v…` PR there.

The workflow creates the patch tag; do not pre-create that tag for a normal
release. Xcode's marketing/build version is separate app metadata and is not
rewritten by this workflow. Update it deliberately when needed. There is no
required `CHANGELOG.md` in this repository.

## Maintainer Review

Before merging an app change, review its PR build and the manual checks relevant
to the changed behavior. After merging:

- Inspect the Release run in [Actions](https://github.com/ShishirAravindan/uttr/actions).
- Verify the published ZIP, tag, and SHA256.
- Review and merge the generated cask PR in the tap. Publishing the app release
  does not itself make the Homebrew update available.

The app repository's `GITHUB_TOKEN` has `contents: write` for tags and releases.
The separate `HOMEBREW_TAP_TOKEN` secret is used to check out the tap and open its
cask PR. A tap-step failure can occur after the app release is already published;
check which steps completed before rerunning a failed workflow, since a rerun
can compute another patch tag.

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
