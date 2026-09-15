# AwaySwitch

AwaySwitch is a Swift macOS menu-bar app that quits selected applications while the user is away and restores only applications it successfully closed.

## Development

- Make changes on a dedicated branch from `main`; keep unrelated features separate.
- Run `scripts/run-tests`, then `scripts/build-app release` and verify the resulting app signature.
- Keep scratch files in `work/`, final deliverables in `outputs/`, and generated build products in the existing ignored `.build/` directory.
- Ask the user whether the fix is finished before squashing and publishing to `main`.

## Presence and recovery

- Runtime state survives power loss. Reconcile saved away reasons against the current macOS session before requesting app termination.
- The session lock field can be absent when unlocked. Distinguish that from an unavailable or incomplete session snapshot.
- Use CoreGraphics constants for documented session keys, including `kCGSessionOnConsoleKey`.
- Preserve independent lock, display-sleep, session-inactive, and system-sleep reasons. Never infer unlock from screen wake alone.
- Preserve restoration queues and pending terminations during startup reconciliation. Never force-quit automatically.
- Live tests must preserve app data and sign-in state. Do not send messages or drain the battery as a test.
