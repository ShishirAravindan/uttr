# Releasing Guide

This guide covers how to create a new release of uttr.

## Version Numbering

We use [Semantic Versioning](https://semver.org/): **MAJOR.MINOR.PATCH**

## Release Checklist

### 1. Prepare the Release

- [ ] Update version in Xcode project (General → Version)
- [ ] Update `CHANGELOG.md` with changes since last release
- [ ] Commit: `git commit -m "chore: prepare v1.x.x release"`

### 2. Build the App

```bash
./build.sh -c Release
```

Or in Xcode: **Product → Archive**, then **Distribute App → Copy App**.

### 3. Create ZIP and Hash

```bash
cd /path/to/exported
zip -r uttr.zip uttr.app
shasum -a 256 uttr.zip
```

Save the SHA256 hash — you'll need it for the Homebrew cask.

### 4. Create Git Tag

```bash
git tag -a v1.x.x -m "Release v1.x.x"
git push origin v1.x.x
```

### 5. Create GitHub Release

1. Go to [GitHub Releases](https://github.com/Rakk301/homebrew-uttr/releases)
2. Draft a new release against the tag
3. Attach `uttr.zip`
4. Publish

### 6. Update Homebrew Cask

In the tap repository (`Casks/uttr.rb`):

```ruby
version "1.x.x"
sha256 "YOUR_SHA256_HASH_HERE"
```

```bash
git commit -am "Update to v1.x.x"
git push
```

Users can then upgrade via:

```bash
brew upgrade --cask uttr
```

## Code Signing & Notarization (recommended)

The build currently ships **ad-hoc signed** (`CODE_SIGN_IDENTITY="-"`). That has
two user-facing costs:

1. **Gatekeeper friction** — every user has to do the "Open Anyway" dance on
   first launch.
2. **Permissions don't stick** — macOS ties the Accessibility (TCC) grant to the
   app's code-signing identity. With an unstable ad-hoc identity, a grant made to
   the running app can be ignored until relaunch, and breaks again after each
   update — the single biggest source of "I approved it but it didn't work."

Signing with a **Developer ID Application** certificate and notarizing the zip
fixes both. Outline:

```bash
# 1. Sign with a stable Developer ID identity (hardened runtime, keep entitlements)
codesign --deep --force --options runtime \
  --entitlements uttr.entitlements \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  /path/to/uttr.app

# 2. Notarize the zip and staple the ticket
ditto -c -k --keepParent /path/to/uttr.app uttr.zip
xcrun notarytool submit uttr.zip \
  --apple-id "you@example.com" --team-id "TEAMID" \
  --password "app-specific-password" --wait
xcrun stapler staple /path/to/uttr.app

# 3. Re-zip the stapled app for distribution
ditto -c -k --keepParent /path/to/uttr.app uttr.zip
```

Once releases are notarized, drop the "Open Anyway" `caveats` note from the
Homebrew cask (see [homebrew-tap.md](homebrew-tap.md)).

## Troubleshooting Releases

### Archive fails to build

- Check all Swift files compile without errors
- Ensure signing is set to "Sign to Run Locally"

### Users report "damaged" app

```bash
xattr -cr /Applications/uttr.app
```

### Homebrew formula doesn't update

```bash
brew update && brew upgrade --cask uttr
```
