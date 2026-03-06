class Osx < Formula
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
           "--product", "osx", "-Xswiftc", "-Onone"
    bin.install ".build/release/osx"
  end

  test do
    assert_match "OSX CLI", shell_output("#{bin}/osx --help")
  end
end
