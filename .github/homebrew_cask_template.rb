cask "nexo" do
  version "VERSION"

  on_macos do
    arch arm: "arm64", intel: "amd64"

    sha256 arm:   "ARM_SHA256",
           intel: "AMD_SHA256"

    url "https://github.com/Shahen777/nexo-app/releases/download/v#{version}/Nexo-#{version}-macos-#{arch}.dmg"
  end

  name "Nexo"
  desc "Client app for the Nexo VPN service"
  homepage "https://github.com/Shahen777/nexo-app"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  app "Nexo.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-rd", "com.apple.quarantine", "{{appdir}}/Nexo.app"],
        writable_paths: ["Nexo.app"],
        writable_base:  :appdir
  end

  uninstall quit: "app.nexo.vpn"

  zap trash: [
    "~/Library/Application Support/app.nexo.vpn",
    "~/Library/Caches/app.nexo.vpn",
    "~/Library/Preferences/app.nexo.vpn.plist",
    "~/Library/Saved Application State/app.nexo.vpn.savedState",
  ]
end
