# Homebrew Tap Setup

This guide explains how to publish and maintain **uttr** as a Homebrew cask under
your own GitHub profile (`ShishirAravindan`), so anyone can install it with:

```bash
brew install --cask ShishirAravindan/uttr/uttr
```

…or the shorter two-step form:

```bash
brew tap ShishirAravindan/uttr
brew install --cask uttr
```

## How a tap works

A Homebrew "tap" is just a GitHub repository named `homebrew-<name>` that
contains cask/formula files. The mapping is:

| You type                       | Homebrew looks for                                  |
|--------------------------------|-----------------------------------------------------|
| `brew tap ShishirAravindan/uttr` | github.com/**ShishirAravindan/homebrew-uttr**       |
| `brew install --cask uttr`     | `Casks/uttr.rb` inside that repo                     |

The tap name (`uttr`) is the part **after** the `homebrew-` prefix, and the cask
name (`uttr`) is the filename (`uttr.rb`) inside `Casks/`. Tap and repo names are
case-insensitive on the command line.

You have two options for where the cask lives:

- **Option A — dedicated tap repo (recommended).** Create a separate
  `homebrew-uttr` repo that holds only the cask. This is the standard Homebrew
  layout and keeps the app source and the distribution metadata cleanly
  separated.
- **Option B — single repo.** Keep everything in this `uttr` repo. This works,
  but `brew tap` still expects a repo literally named `homebrew-uttr`, so you'd
  have to rename this repo (which changes the app source URL too). Option A is
  simpler.

The rest of this guide uses **Option A**.

## One-time setup

### 1. Create the tap repository

Create a new **public** GitHub repo under your profile named exactly:

```
homebrew-uttr
```

Clone it locally:

```bash
git clone https://github.com/ShishirAravindan/homebrew-uttr.git
cd homebrew-uttr
mkdir -p Casks
```

### 2. Add the cask file

Copy [`Casks/uttr.rb`](../Casks/uttr.rb) from this repo into `Casks/uttr.rb` in
the tap repo. The canonical content is:

```ruby
cask "uttr" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/ShishirAravindan/uttr/releases/download/v#{version}/uttr.zip"
  name "uttr"
  desc "macOS speech-to-text utility powered by Parakeet on the Neural Engine"
  homepage "https://github.com/ShishirAravindan/uttr"

  depends_on macos: ">= :sonoma"

  app "uttr.app"

  caveats <<~EOS
    uttr is not notarized yet. On first launch:
      System Settings → Privacy & Security → Open Anyway

    Then grant, when prompted:
      - Microphone   (speech recording)
      - Accessibility (global hotkey + paste-at-cursor)
  EOS

  zap trash: [
    "~/Library/Application Support/uttr",
    "~/Library/Logs/uttr",
  ]
end
```

> The `url` points at **this** app repo's GitHub Releases (`ShishirAravindan/uttr`),
> while the cask itself lives in `ShishirAravindan/homebrew-uttr`. Releases stay
> next to the source; the tap only carries the recipe.

Commit and push:

```bash
git add Casks/uttr.rb
git commit -m "Add uttr cask"
git push
```

## Cutting a release

Each new version is a GitHub Release on **this** repo plus a one-line bump in the
tap. The [Release workflow](../.github/workflows/release.yml) automates the build:
pushing a `v*` tag builds `uttr.app`, zips it, and attaches `uttr.zip` to the
release (the run also prints the SHA256 in its logs).

1. **Tag and push** from this repo:

   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```

2. **Grab the SHA256.** Either read it from the Release workflow logs, or compute
   it from the published artifact:

   ```bash
   curl -sL https://github.com/ShishirAravindan/uttr/releases/download/v0.1.0/uttr.zip -o uttr.zip
   shasum -a 256 uttr.zip
   ```

3. **Bump the cask** in the `homebrew-uttr` repo:

   ```ruby
   version "0.1.0"
   sha256 "PASTE_THE_HASH_HERE"
   ```

   ```bash
   git commit -am "uttr 0.1.0"
   git push
   ```

Users then upgrade with `brew upgrade --cask uttr`.

## Testing the tap locally

Before announcing a release, verify the cask end-to-end:

```bash
# Lint the recipe (style + common mistakes)
brew style ShishirAravindan/uttr
brew audit --cask --online uttr

# Install straight from your tap
brew tap ShishirAravindan/uttr
brew install --cask uttr

# Confirm it resolves to your tap and the right version
brew info --cask uttr

# Clean reinstall while iterating
brew reinstall --cask uttr
brew uninstall --cask uttr
```

If `sha256` doesn't match the artifact, `brew install` fails with a checksum
mismatch — re-run step 2 above and bump the hash.

## Notarization (recommended, fixes the "damaged app" friction)

The cask currently ships an **ad-hoc-signed** app, so macOS Gatekeeper blocks it
on first launch (the "Open Anyway" dance) and — more importantly — the
Accessibility grant is tied to an unstable code-signing identity, which is why
permissions sometimes don't "stick" across updates. Signing with a **Developer
ID** certificate and notarizing the zip removes both problems. Once you notarize,
delete the `caveats` "Open Anyway" note from the cask. See
[releasing.md](releasing.md) for the signing pipeline.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Error: Cask 'uttr' is unavailable` | The tap repo must be named `homebrew-uttr` and be public. Run `brew tap ShishirAravindan/uttr` first. |
| `SHA256 mismatch` | The `sha256` in the cask doesn't match the uploaded `uttr.zip`. Recompute and bump it. |
| `brew install` 404s on the URL | The `url` version/tag doesn't match a published Release on `ShishirAravindan/uttr`. |
| Old version keeps installing | `brew update && brew upgrade --cask uttr`. Homebrew caches taps under `$(brew --repository)/Library/Taps`. |
