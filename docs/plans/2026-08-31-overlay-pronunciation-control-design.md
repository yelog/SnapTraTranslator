# Overlay Pronunciation Control Design

## Background

SnapTra Translator can automatically pronounce a detected word or sentence, and already persists separate word and sentence auto-play settings. The translation overlays do not expose those settings, do not offer manual replay, and cannot show whether speech is loading, playing, complete, or failed. `SpeechService` currently starts and stops speech but does not publish a complete playback lifecycle for SwiftUI.

## Goals

- Show a pronunciation control in both word and sentence overlays.
- Let users play or restart pronunciation directly from the overlay.
- Show loading, playing, and failed states clearly.
- Show and toggle the existing word or sentence auto-play preference.
- Keep manual pronunciation available when auto-play is disabled.
- Keep the control compact, immediately understandable, keyboard accessible, and consistent with the current macOS overlay style.

## Non-Goals

- Do not add pause and resume behavior.
- Do not add a global mute setting.
- Do not add separate pronunciation controls for translated sentence output.
- Do not change the existing TTS provider or accent settings.
- Do not change the defaults: word auto-play remains enabled and sentence auto-play remains disabled.

## Recommended Control

Use a compact two-zone capsule:

`[ pronunciation | auto on/off ]`

- The left zone controls playback. It displays a speaker in the idle state, a progress indicator while online audio is loading, an emphasized waveform or speaker while playing, and a temporary failure indicator when playback fails.
- Clicking the left zone plays the current word or sentence source text.
- Clicking while audio is playing cancels the current request and restarts it from the beginning.
- The right zone toggles only automatic playback for that content type. It uses the short label `Auto` plus a filled or hollow state indicator, so state is not communicated by color alone.
- Disabling auto-play does not disable manual playback and does not interrupt audio that has already started.
- Enabling auto-play saves the preference but does not unexpectedly start the current text.

The two zones remain separate accessibility elements and keyboard targets even though they share one visual capsule.

## Placement

### Word Overlay

Place the control in the word header control group, before the existing copy and close controls. The pronunciation belongs visually to the displayed word and remains available as dictionary results load incrementally.

### Sentence Overlay

Place the control in the sentence top toolbar. It always pronounces the source text, including when the original-text region is hidden. The control remains visible in both temporary and pinned sentence presentations when source text is available.

## Playback State

Expose a single observable speech state from `SpeechService`:

- `idle`: no active request or playback.
- `loading`: online audio is being fetched or prepared.
- `playing`: Apple or online audio has started.
- `failed`: the active request could not be played, including fallback failure.

The state must identify the active speech request or content context. Completion and failure callbacks from superseded requests must not overwrite a newer state.

Apple speech and online playback must both report start and natural completion. Explicit stop, cancellation, replacement, and failure must reset or update the state consistently. Delegate callbacks are required; playback duration must not be estimated with timers.

## Data Flow

- `AppModel` owns the overlay pronunciation actions and derives the current text, source language, provider, and accent from the active word or sentence content.
- Existing automatic pronunciation paths and new manual actions call the same speech entry point.
- Word controls bind to `playWordPronunciation`; sentence controls bind to `playSentencePronunciation`. Existing settings and menu-bar UI therefore stay synchronized through `SettingsStore`.
- The view displays a non-idle speech state only when it belongs to the current overlay content. A stale request must not make a newly displayed panel appear active.
- Dismissing an overlay, replacing its content, changing lookup mode, or starting another pronunciation invalidates and stops the previous request.

## Interaction Details

- Idle left-zone tooltip: `Play pronunciation`.
- Playing left-zone tooltip: `Playing - click to restart`.
- Failed left-zone tooltip: `Pronunciation failed - click to retry`.
- Auto zone tooltip and accessibility value explicitly state whether word or sentence auto-play is enabled.
- Empty or whitespace-only source text disables playback but leaves the auto-play toggle available.
- If a source language cannot be resolved, preserve the existing TTS default-voice behavior.
- Online fetches are cancellable. Repeated clicks replace rather than queue requests.

## Error Handling

- A failed online provider may continue to use the existing Apple speech fallback.
- The UI enters `failed` only when no playback path starts successfully.
- Failure is shown locally in the compact control without a modal or persistent error row.
- A failure remains retryable through the left zone and resets when content changes or a new request starts.
- Late start, completion, and failure callbacks are ignored unless their request generation is still current.

## Accessibility

- Expose two buttons rather than one ambiguous compound action.
- Provide state-specific labels for play, restart, and retry.
- Announce word and sentence auto-play states explicitly.
- Preserve operation with Space and Return.
- Keep each hit target at least approximately 22 by 22 points.
- Use icon shape, text, and filled/hollow indicators in addition to color.

## Validation

- Both overlays show the compact two-zone pronunciation control.
- Manual play works whether auto-play is enabled or disabled.
- Clicking during playback restarts from the beginning.
- Loading, playing, completion, stop, and failure states render correctly for Apple and online providers.
- Word and sentence auto-play toggles remain independent and synchronize with existing settings and menu items.
- Disabling auto-play affects only future lookups and does not stop current playback.
- Enabling auto-play does not immediately pronounce the current content.
- Closing or replacing an overlay stops audio and prevents stale state updates.
- Sentence pronunciation always uses source text.
- Light mode, dark mode, keyboard navigation, tooltips, and accessibility labels remain usable.
