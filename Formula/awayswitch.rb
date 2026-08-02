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

  def post_install
    applications = Pathname(Dir.home)/"Applications"
    applications.mkpath
    app_link = applications/"AwaySwitch.app"

    if app_link.symlink?
      app_link.unlink
    elsif app_link.exist?
      opoo "#{app_link} already exists; the Homebrew app shortcut was not installed."
      return
    end

    app_link.make_symlink(opt_prefix/"AwaySwitch.app")
    system "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
           "-f", app_link
    system "/usr/bin/mdimport", app_link
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
