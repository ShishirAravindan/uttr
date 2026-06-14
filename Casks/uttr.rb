# Homebrew Cask formula for uttr
#
# This file is the recipe that lives in your single tap repo
# (ShishirAravindan/homebrew-tap, under Casks/uttr.rb). One tap repo can hold all
# your casks/formulae. See docs/homebrew-tap.md for the full setup and release flow.
#
# Install:
#   brew install --cask ShishirAravindan/tap/uttr
#
# On each release, update:
#   - version: match the GitHub release tag (without the 'v' prefix)
#   - sha256:  `shasum -a 256 uttr.zip` on the released artifact

cask "uttr" do
  version "0.1.0"
  sha256 "63ad3382781467923dd25c64a8a4a4cca914608b203f5f27b27baaea15410e08"

  url "https://github.com/ShishirAravindan/uttr/releases/download/v#{version}/uttr.zip"
  name "uttr"
  desc "macOS speech-to-text utility powered by Parakeet on the Neural Engine"
  homepage "https://github.com/ShishirAravindan/uttr"

  depends_on macos: ">= :sonoma"

  app "uttr.app"

  caveats <<~EOS
    On first launch, you may need to allow the app in:
      System Settings → Privacy & Security → Open Anyway

    Grant these permissions when prompted:
      - Microphone access (for speech recording)
      - Accessibility access (for the global hotkey and paste-at-cursor)
  EOS

  zap trash: [
    "~/Library/Application Support/uttr",
    "~/Library/Logs/uttr",
  ]
end
