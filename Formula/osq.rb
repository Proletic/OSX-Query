class Osq < Formula
  desc "OSXQuery CLI for querying and interacting with macOS Accessibility trees"
  homepage "https://github.com/Moulik-Budhiraja/OSX-Query"
  license "MIT"
  head "https://github.com/Moulik-Budhiraja/OSX-Query.git", branch: "main"

  depends_on macos: :sonoma
  uses_from_macos "swift" => :build

  def install
    # `-O` currently triggers a Swift compiler crash in this package, so keep
    # release layout while disabling optimization for reliable installs.
    system "swift", "build", "--disable-sandbox", "--configuration", "release",
           "--product", "osq", "-Xswiftc", "-Onone"
    bin.install ".build/release/osq"
  end

  test do
    assert_match "OSQ CLI", shell_output("#{bin}/osq --help")
  end
end
