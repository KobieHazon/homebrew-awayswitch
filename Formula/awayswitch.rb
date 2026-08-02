class Awayswitch < Formula
  desc "Disconnect selected Mac apps while you are away"
  homepage "https://github.com/KobieHazon/homebrew-awayswitch"
  url "https://github.com/KobieHazon/homebrew-awayswitch.git", tag: "v0.1.0"
  license "MIT"
  head "https://github.com/KobieHazon/homebrew-awayswitch.git", branch: "feature/awayswitch-v1"

  depends_on macos: :ventura

  def install
    system "./scripts/build-app", "release"
    prefix.install ".build/AwaySwitch.app"
    bin.install_symlink prefix/"AwaySwitch.app/Contents/MacOS/AwaySwitch" => "awayswitch"
  end

  service do
    run [opt_prefix/"AwaySwitch.app/Contents/MacOS/AwaySwitch"]
    environment_variables AWAYSWITCH_SERVICE: "1"
    process_type :interactive
    log_path var/"log/awayswitch.log"
    error_log_path var/"log/awayswitch.log"
  end

  test do
    assert_match "AwaySwitch 0.1.0", shell_output("#{bin}/awayswitch --version")
    assert_match "configuration is valid", shell_output("#{bin}/awayswitch --check-config")
  end
end
