# Paragraph Overlay Pin and Copy Buttons Design

Date: 2026-04-01

## Summary

Add two features to the sentence translation panel:
1. **Pin Button**: Replace close button with pin button when panel is non-persistent (double-tap hotkey long-press, or long-press hotkey for selected text). Clicking pin makes the panel persistent, and it won't auto-close on hotkey release. Once pinned, show close button which unpins and closes the panel.
2. **Copy Buttons**: Add copy buttons for both original text and translated text, allowing users to copy content to clipboard.

## Design

### Architecture

Follow existing architecture pattern: state management in `AppModel`, UI presentation in `OverlayView`.

### State Management (AppModel.swift)

Add temporary pin state:
```swift
@Published var isParagraphOverlayPinned: Bool = false
```

State lifecycle:
- **Created**: When user clicks pin button
- **Cleared**: When panel closes, user clicks close button, or next translation trigger

Methods:
- `toggleParagraphOverlayPin()`: Toggle pin state
- `handleHotkeyRelease()`: Check pin state, don't close if pinned
- `hideOverlay()`: Clear pin state

### UI Components (OverlayView.swift)

#### Pin/Close Button Toggle

New computed property:
```swift
private var showsParagraphOverlayPinButton: Bool {
    isParagraphOverlayMode && !model.isParagraphOverlayPinned
}
```

Modified `paragraphTopBar()`:
- If `showsParagraphOverlayPinButton` is true → show pin button
- Otherwise → show close button

Button styles:
- Pin: `pin` icon, circular background, help text "Pin"
- Close: `xmark` icon, circular background, help text "Close"

#### Copy Buttons

Reuse existing `CopyButton` component.

Layout:
- **Original text**: Copy button aligned to right of text content
- **Native translation**: Copy button aligned to right of section title
- **Third-party services**: Copy button aligned to right of service title

Implementation locations:
- `paragraphResultView()`: Add copy button for original text and native translation
- `paragraphServiceResultCard()`: Add copy button for third-party service results

## Implementation Details

### Files Modified

| File | Changes | Lines |
|------|---------|-------|
| AppModel.swift | Add state, methods, modify release handler | ~15 |
| OverlayView.swift | Add button toggle, copy buttons | ~50 |

### Testing Checklist

1. **Pin Feature**
   - Double-tap hotkey → long-press → release → panel closes (default)
   - Double-tap hotkey → long-press → click pin → release → panel stays open
   - Click close button → panel closes → pin state cleared
   - Next trigger → default non-persistent mode

2. **Copy Feature**
   - Click original text copy button → text copied to clipboard
   - Click translation copy button → text copied to clipboard
   - Copy success → checkmark animation displayed
   - Third-party service results → copy works

## User Experience

### Pin Behavior

- Default: Panel auto-closes on hotkey release (non-persistent)
- After pin: Panel stays open on hotkey release (persistent)
- After close: Panel closes, pin state cleared, next trigger defaults to non-persistent

### Copy Behavior

- Small icon button style (matches existing CopyButton)
- Click → copy to clipboard → show success animation
- Positioned at right side of content areas

## Constraints

- Pin state is session-only (not persisted in SettingsStore)
- Copy buttons use existing component (no new implementation)
- No changes to window controller or settings