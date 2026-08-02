# AwaySwitch

AwaySwitch is a small macOS menu-bar utility that disconnects selected desktop apps while you are away. It is designed for the case where Codex, OpenClaw, Amphetamine, or another process keeps the Mac awake, but an active WhatsApp desktop session prevents notifications from returning to your phone.

When your Mac locks, its screens sleep, the user session becomes inactive, or the system begins sleeping, AwaySwitch normally quits the apps you selected. When you return, it reopens only the apps it successfully closed.

AwaySwitch does not depend on Amphetamine and does not care which process supplies the keep-awake assertion. It also does not keep the Mac awake itself, change `pmset`, install a privileged helper, override lid-close behavior, collect telemetry, or make network requests.

## Install

AwaySwitch supports macOS 13 Ventura and newer on Apple Silicon and Intel Macs.

```bash
brew install KobieHazon/awayswitch/awayswitch
brew services start KobieHazon/awayswitch/awayswitch
```

Homebrew also places **AwaySwitch.app** in your user Applications folder, so you can find and launch it from Spotlight or Launchpad like any other Mac app. Launching the app opens its settings. The second command starts AwaySwitch immediately and registers it as a per-user LaunchAgent, so it returns at login. Look for **AS** in the menu bar.

To update:

```bash
brew update
brew upgrade KobieHazon/awayswitch/awayswitch
brew services restart KobieHazon/awayswitch/awayswitch
```

## Use

WhatsApp is managed by default. Open the AwaySwitch menu to:

- pause or resume protection;
- see whether the Mac is present or away;
- see whether each managed app is running, disconnecting, disconnected, or needs attention;
- choose **Manage Apps…** to add or remove applications;
- control whether previously running apps reopen after unlock;
- explicitly force quit an app if its normal quit request has not completed after 10 seconds.

AwaySwitch never force quits automatically. A managed app added while the Mac is already away is disconnected but is not added to the restoration queue.

Configuration and recovery state are stored as readable JSON in:

```text
~/Library/Application Support/AwaySwitch/config.json
~/Library/Application Support/AwaySwitch/state.json
```

Useful health checks:

```bash
awayswitch --status
awayswitch --check-config
awayswitch --show-settings
```

## Keep-awake setup

No special setup is needed when Codex, OpenClaw, or another app already keeps the Mac awake by itself. AwaySwitch works independently from that assertion.

If you use Amphetamine, keep power management there and presence management in AwaySwitch:

1. In Amphetamine, create an app/process Trigger for Codex, OpenClaw, or the background process that must continue.
2. Allow display sleep and screen locking for that Trigger.
3. If OpenClaw is not visible in Amphetamine, enable Amphetamine's Process Discovery script and select the OpenClaw gateway process.
4. Leave Closed-Display Mode and Power Protect entirely under Amphetamine's control. AwaySwitch does not install, enable, or modify either feature.

On an ordinary undocked MacBook, macOS may still sleep when the lid closes. AwaySwitch supports lock, screen-off, system sleep/wake, fast-user-switching, and whatever closed-display session Amphetamine already maintains; it does not bypass Apple's lid policy.

## How it behaves

- Each away reason is tracked independently. A screen wake does not restore apps if the session remains locked.
- Duplicate macOS notifications are harmless.
- Normal termination is requested through `NSRunningApplication`; the app remains listed as needing attention if it refuses to quit.
- Apps are restored by their saved bundle URL, with Launch Services bundle-ID discovery as a fallback if an app moved.
- Restoration and pending termination state are written atomically so a restart does not lose which apps AwaySwitch closed.
- Apps manually launched while away are asked to quit again.

WhatsApp controls notification routing, so phone notifications may take a few seconds to resume after its Mac app exits. Verify the behavior with a real incoming message before relying on it.

## Uninstall

```bash
brew services stop KobieHazon/awayswitch/awayswitch
awayswitch --remove-app
brew uninstall KobieHazon/awayswitch/awayswitch
brew untap KobieHazon/awayswitch
```

The commands leave your JSON settings in place. Remove `~/Library/Application Support/AwaySwitch` manually only if you also want to discard the configuration.

## Development

```bash
scripts/run-tests
scripts/build-app release
.build/AwaySwitch.app/Contents/MacOS/AwaySwitch --version
```

The `scripts/swiftpm` wrapper normally delegates directly to SwiftPM. It also detects and locally works around a mismatched `PackageDescription` interface shipped by some macOS 26 Command Line Tools builds; it never modifies the installed toolchain.

AwaySwitch is available under the [MIT License](LICENSE).
