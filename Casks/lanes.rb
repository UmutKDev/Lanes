# Homebrew cask for Lanes. This repository doubles as its tap:
#
#   brew tap umutkdev/lanes https://github.com/UmutKDev/Lanes
#   brew install --cask lanes
#
# Every release carries a copy of its DMG named Lanes.dmg, so the latest
# release is always at the same address and this file never needs a version
# bump. Lanes updates itself with Sparkle, hence `auto_updates`: `brew upgrade`
# leaves it alone and the in-app updater does the work. The DMG is signed with
# Developer ID and notarized, which Gatekeeper checks when Lanes first opens.
cask "lanes" do
  version :latest
  sha256 :no_check

  url "https://github.com/UmutKDev/Lanes/releases/latest/download/Lanes.dmg"
  name "Lanes"
  desc "Run several Claude desktop accounts side by side"
  homepage "https://github.com/UmutKDev/Lanes"

  auto_updates true
  depends_on macos: :tahoe

  app "Lanes.app"

  uninstall quit: "com.umutkdev.Lanes"

  # `brew uninstall --zap` also removes the accounts Lanes made, with their
  # sign-ins and Claude data. A plain uninstall keeps them.
  zap trash: [
    "~/Library/Application Support/Lanes",
    "~/Library/Caches/com.umutkdev.Lanes",
    "~/Library/Group Containers/TN6A8RCVKP.com.umutkdev.Lanes",
    "~/Library/HTTPStorages/com.umutkdev.Lanes",
    "~/Library/Preferences/com.umutkdev.Lanes.plist",
    "~/Library/Saved Application State/com.umutkdev.Lanes.savedState",
  ]
end
