# Homebrew Tap Setup

This guide sets up **one** Homebrew tap repo under your profile that holds **all**
your casks and formulae — uttr today, anything else later — so users install with:

```bash
brew install --cask ShishirAravindan/tap/uttr
```

…or the two-step form:

```bash
brew tap ShishirAravindan/tap
brew install --cask uttr
```

## Can I use one repo for everything (and skip the `homebrew-` name)?

**One repo for all your packages: yes — that's the standard pattern.** A single
tap repo can contain any number of casks (`Casks/*.rb`) and formulae
(`Formula/*.rb`). This is exactly how the big projects ship:

| Project | Tap repo | Install command |
|---|---|---|
| Terraform / Vault / Consul… | `hashicorp/homebrew-tap` (24 formulae, 2 casks) | `brew install hashicorp/tap/terraform` |
| opencode | `sst/homebrew-tap` | `brew install sst/tap/opencode` |

Both keep **every** tool in a single `homebrew-tap` repo.

**Dropping the `homebrew-` prefix: not for the clean UX.** Homebrew's docs are
explicit: *"On GitHub, your repository must be named `homebrew-something` to use
the one-argument form of `brew tap`."* The prefix is **not optional** — but it's
invisible to users. Nobody ever types "homebrew": they run
`brew install hashicorp/tap/terraform`, and Homebrew expands `hashicorp/tap` →
`github.com/hashicorp/homebrew-tap` for them. So name the repo `homebrew-tap` and
your users only ever see `ShishirAravindan/tap`.

> **The escape hatch (not recommended).** The two-argument form
> `brew tap <user>/<name> <URL>` clones an arbitrary URL, so the repo can be named
> anything (no `homebrew-` prefix). The cost: users must run that full
> `brew tap ShishirAravindan/tap https://github.com/ShishirAravindan/some-repo`
> command — they can't just `brew install ShishirAravindan/tap/uttr` cold. That's
> worse UX for a cosmetic win, which is why HashiCorp/sst don't do it. Stick with
> `homebrew-tap`.

**Recommendation:** create one repo named **`homebrew-tap`** under your profile.
The rest of this guide uses that.

## How the names map

```bash
brew install --cask ShishirAravindan/tap/uttr
#                    └────┬───────┘ └┬┘ └─┬─┘
#                        │          │    └── cask file: Casks/uttr.rb
#                        │          └─────── tap:  github.com/ShishirAravindan/homebrew-tap
#                        └────────────────── your GitHub user
```

Tap and cask names are case-insensitive on the command line.

## One-time setup

### 1. Create the tap repository

Create a new **public** GitHub repo under your profile named exactly:

```
homebrew-tap
```

Clone it and add a `Casks/` directory (use `Formula/` for CLI formulae):

```bash
git clone https://github.com/ShishirAravindan/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks
```

### 2. Add the cask file

Create `Casks/uttr.rb` in the tap repo (`ShishirAravindan/homebrew-tap`) with the
canonical content below. (The cask lives only in the tap repo — it is intentionally
not kept in the app source repo.)

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
> while the cask itself lives in `ShishirAravindan/homebrew-tap`. Releases stay
> next to the source; the tap only carries the recipe.

Commit and push:

```bash
git add Casks/uttr.rb
git commit -m "Add uttr cask"
git push
```

### Adding more packages later

Drop another file into the same repo — `Casks/myapp.rb` or `Formula/mytool.rb` —
commit, and it's instantly installable as `ShishirAravindan/tap/myapp`. No new
repo, no new tap command.

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

3. **Bump the cask** in the `homebrew-tap` repo:

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
brew style ShishirAravindan/tap
brew audit --cask --online uttr

# Install straight from your tap
brew tap ShishirAravindan/tap
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
| `Error: Cask 'uttr' is unavailable` | The tap repo must be named `homebrew-tap` and be public. Run `brew tap ShishirAravindan/tap` first. |
| `SHA256 mismatch` | The `sha256` in the cask doesn't match the uploaded `uttr.zip`. Recompute and bump it. |
| `brew install` 404s on the URL | The `url` version/tag doesn't match a published Release on `ShishirAravindan/uttr`. |
| Old version keeps installing | `brew update && brew upgrade --cask uttr`. Homebrew caches taps under `$(brew --repository)/Library/Taps`. |

## Sources

- [Homebrew Docs — Taps](https://docs.brew.sh/Taps)
- [hashicorp/homebrew-tap](https://github.com/hashicorp/homebrew-tap)
- [sst/homebrew-tap](https://github.com/sst/homebrew-tap)
