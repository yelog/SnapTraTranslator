# Layered Permission Readiness Design

**Goal:** Make permission status understandable by showing capability readiness in layers, so users know whether OCR word translation works, whether selected-text sentence translation works, and what is still missing.

## Problem

- The app now requires two different privacy permissions for two different capabilities:
  - screen recording for OCR word lookup
  - accessibility for selected-text sentence translation
- The current UI exposes the raw permission rows, but it does not clearly explain which feature each permission unlocks.
- The general settings flow still treats screen recording as the only meaningful readiness signal, which is now misleading.
- Users can end up in a state where word lookup works but sentence lookup does not, without any clear explanation in the app.

## Product Decision

Use layered readiness instead of a single "all permissions granted" concept.

- `OCR word translation` is available when screen recording is granted.
- `Selected-text sentence translation` is available when accessibility is granted.
- Full capability is available only when both permissions are granted.
- The UI should explain this directly instead of expecting the user to infer it from raw permission toggles.

## Scope

- Update the settings UI to clearly communicate layered readiness.
- Keep the existing permission actions:
  - request/open screen recording settings
  - request/open accessibility settings
- Unify readiness logic across settings surfaces so the app does not show conflicting states.

## Non-Goals

- Do not change the hotkey or lookup pipeline in this change.
- Do not add runtime diagnostics for missing accessibility entries in System Settings.
- Do not redesign unrelated settings sections.

## Recommended Approach

### 1. Add Capability-Level Permission State

Extend `PermissionManager` with computed capability helpers derived from `PermissionStatus`.

Recommended outputs:

- `canLookupWordByOCR`
- `canTranslateSentenceSelection`
- `isFullyReady`
- `capabilitySummary`

This keeps readiness rules in one place and prevents duplicated boolean logic in SwiftUI views.

### 2. Show a Readiness Summary Above Raw Permissions

In the permissions card, add a short summary block above the permission rows.

Recommended states:

- neither permission granted: `未启用翻译能力`
- only screen recording granted: `已启用单词翻译，句子翻译未启用`
- only accessibility granted: `已启用句子翻译，单词翻译未启用`
- both granted: `完整翻译能力已启用`

This summary should answer the user question directly: "What can I use right now?"

### 3. Annotate Each Permission With Its Purpose

Keep the two permission rows, but add clear purpose text:

- `Screen Recording`: used for OCR word lookup under the pointer
- `Accessibility`: used for reading selected text and translating sentences

This makes the relationship between permission and feature explicit.

### 4. Unify Settings Readiness Logic

`SettingsView` and `SettingsWindowView` should both rely on the same capability model from `PermissionManager`.

This avoids the current inconsistency where one surface shows two permissions while another still treats screen recording as the sole readiness gate.

## UI Structure

### Permissions Card

Recommended order:

1. readiness summary
2. `OCR 单词翻译` capability row or summary line
3. `选中文本句子翻译` capability row or summary line
4. screen recording permission row
5. accessibility permission row
6. refresh status action

The card should remain compact and avoid introducing a second modal or blocking banner.

### General Readiness

Where the general settings page currently computes "all permissions granted", switch to layered readiness:

- word feature readiness should depend on screen recording
- sentence feature readiness should depend on accessibility
- full readiness should depend on both

If the UI only needs to decide whether the app is "partially usable", it should consider either capability sufficient. If it needs "all translation features available", it should require both permissions.

## Error Handling

- If the app is missing from System Settings > Accessibility, continue showing the accessibility permission as not granted.
- The existing button should still open the correct System Settings pane.
- Do not attempt path-level or bundle-registration diagnostics in this change.

## Testing Strategy

### Automated

- Add tests for the derived capability state:
  - neither permission granted
  - only screen recording granted
  - only accessibility granted
  - both permissions granted
- Add UI-adjacent tests where practical for readiness summary text mapping.

### Manual

- Launch the app with no permissions and verify the summary says no translation capability is enabled.
- Grant only screen recording and verify the UI says word translation is available but sentence translation is not.
- Grant only accessibility and verify the UI says sentence translation is available but OCR word translation is not.
- Grant both and verify the UI says full capability is enabled.
- Confirm both settings surfaces show consistent readiness messaging.

## Risks

- If capability logic remains duplicated, the UI will drift again and confuse users.
- If summary wording is too abstract, users still will not know which feature is blocked.
- Accessibility permission visibility in System Settings can still confuse users if the app has not been properly prompted yet, so the wording should stay concrete and feature-oriented.

## Recommended Rollout

1. Add capability helpers in `PermissionManager`
2. Update permission summary UI in `SettingsView`
3. Update general readiness logic in `SettingsWindowView`
4. Add tests for capability state mapping
5. Manually verify the four permission combinations
