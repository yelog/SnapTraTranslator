# Tap Keeps Word Overlay Design

Date: 2026-06-11

## Summary

Issue #18 asks for an optional mode where the translation bubble can stay visible after the trigger key is released, then dismiss when the mouse moves. This is valuable because it separates two common workflows:

1. Hold the hotkey and move the mouse for continuous translation.
2. Tap once, read a single lookup result, then move on.

## Design

Add a new setting, `keepWordOverlayAfterTap`, defaulting to on so the word lookup behavior matches the existing double-tap persistent overlay semantics. When enabled, a short tap release keeps a word lookup overlay alive and interactive instead of cancelling it. Long press release keeps the current auto-dismiss behavior.

The kept overlay dismisses on meaningful mouse movement. Movement into the overlay frame is protected so users can still click copy or close without instantly dismissing the bubble. The existing close button and `dismissOverlay()` path remain the explicit dismissal route.

## Architecture

- `HotkeyManager` keeps the existing gesture state machine and adds a separate callback for short-tap release.
- `AppModel` decides whether a tap release should keep the current word overlay based on settings and active lookup mode.
- `WordOverlayPersistencePolicy` holds pure dismissal rules for unit tests.
- `SettingsStore` persists the new setting through `UserDefaults`.
- Settings UI and README files describe the new mode without changing continuous translation semantics.

## UX Rules

- Tap-keep is enabled by default and can be turned off in Settings.
- Continuous translation remains hold-and-hover.
- Tap-keep applies only to short tap release.
- A kept overlay becomes interactive and shows copy/close controls.
- Moving outside the protected overlay area by more than the threshold dismisses it.
- Starting a new lookup clears the kept state.

## Testing

- Unit-test the tap-release callback behavior in `HotkeyGestureStateMachine`.
- Unit-test the pure persistence policy for setting gating and mouse movement dismissal.
- Unit-test `SettingsStore` default and persisted values.
- Run focused tests, then a Debug build.
