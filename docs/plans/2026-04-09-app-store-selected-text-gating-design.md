# App Store Selected Text Gating Design

**Goal:** Hide selected-text translation controls in the Mac App Store channel and prevent the runtime from attempting cross-app selected-text lookup there.

## Problem

The app currently exposes selected-text translation as soon as Accessibility permission is granted. That assumption is too optimistic for the App Store distribution channel:

- the App Store target runs sandboxed
- the selected-text flow depends on cross-app Accessibility reads
- runtime lookup silently falls back to OCR word translation when the selection snapshot cannot be resolved

This creates a misleading product surface: the settings UI suggests the capability is available, but the shipped App Store build effectively behaves like word-only OCR lookup for single-press translation.

## Product Decision

For the App Store channel:

- hide the `Accessibility` permission row in General settings
- hide the `Translate Selected Text` toggle in General settings
- remove selected-text translation from readiness calculations
- never attempt selected-text lookup at runtime

For the Direct channel:

- preserve the current selected-text translation behavior
- preserve the stored user preference for `selectedTextTranslationEnabled`

## Why This Approach

### Option 1: Hide UI only

Rejected. The App Store and Direct builds share the same bundle identifier, so an older stored `selectedTextTranslationEnabled` value could still cause the App Store build to attempt selected-text lookup.

### Option 2: Force-write the setting to `false` in App Store builds

Rejected. This would disable the feature across channels and erase the user's Direct-channel preference.

### Option 3: Channel capability gating

Chosen. Introduce a channel-scoped capability flag and make both UI and runtime depend on it.

This keeps behavior accurate in the App Store channel without mutating persisted settings that still matter in the Direct channel.

## Architecture

Add a shared capability check derived from the existing distribution channel model:

- `DistributionChannel.appStore` -> selected-text translation unsupported
- `DistributionChannel.github` -> selected-text translation supported

Use that capability in two places:

1. Settings UI
   - conditionally render the Accessibility permission row
   - conditionally render the selected-text translation toggle
   - compute readiness from OCR capability only when selected-text translation is unsupported

2. Lookup routing
   - short-circuit single-press lookup to `.ocrWord` when the channel does not support selected-text translation
   - avoid calling `SelectedTextService` in unsupported channels

## Data Flow

### Direct Channel

1. User presses the hotkey.
2. The app checks whether selected-text translation is enabled and supported.
3. If allowed, the app queries `SelectedTextService`.
4. If a selection snapshot is available, route to selected-text sentence translation.
5. Otherwise, fall back to OCR word translation.

### App Store Channel

1. User presses the hotkey.
2. The app checks whether selected-text translation is supported.
3. The answer is always no, so it routes directly to OCR word translation.
4. `SelectedTextService` is never consulted.

## UI Behavior

### App Store

- show `Screen Recording`
- hide `Accessibility`
- show `Double-tap OCR Sentence Translation`
- hide `Translate Selected Text`
- keep the existing OCR-based controls and status

### Direct

- current behavior remains unchanged

## Persistence

Keep storing `selectedTextTranslationEnabled` in `SettingsStore`.

The App Store build must ignore that value at runtime and in settings presentation, but must not overwrite it. This preserves user preference continuity when switching back to the Direct build.

## Testing

### Automated

- extend lookup routing tests to cover the unsupported-channel case
- verify existing selected-text routing tests still pass when capability support is enabled

### Manual

- App Store build:
  - Accessibility row hidden
  - selected-text toggle hidden
  - single-press lookup never attempts selected-text translation
- Direct build:
  - Accessibility row visible
  - selected-text toggle visible
  - selected-text translation behavior unchanged

## Risks

- If future App Store features also require Accessibility, hiding the full Accessibility row may become too broad. For now, selected-text translation is the only Accessibility-driven feature in the app.
- If capability checks are duplicated instead of centralized, UI and runtime can drift again.

## Success Criteria

- The App Store build no longer advertises selected-text translation.
- The App Store build no longer attempts selected-text lookup during single-press translation.
- The Direct build retains the existing selected-text translation feature and stored preference.
