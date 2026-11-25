cask "solvr" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/adeonir/solvr/releases/download/v#{version}/Solvr-#{version}.zip"
  name "Solvr"
  desc "Text calculator with saved, organized, and synced sheets"
  homepage "https://github.com/adeonir/solvr"

  depends_on macos: :tahoe

  app "Solvr.app"
end
