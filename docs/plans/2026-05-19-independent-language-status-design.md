# Independent Language Status Design

## Requirement

In Settings > General, `Translate from` and `Translate to` must each show an independent language-pack availability icon for the selected language itself. If Simplified Chinese is downloaded and German is not, Simplified Chinese should show a checkmark even when the German/Simplified Chinese translation pair is unavailable.

## Current Behavior

- `GeneralTranslationLanguageRow` originally computed availability only from required translation pairs.
- Directional pair status cannot identify which language pack in the pair is missing.
- For example, if German is missing and Simplified Chinese is installed, both `de -> zh-Hans` and `zh-Hans -> de` can report unavailable because the German pack is required by both directions.
- Mapping those pair statuses directly to picker rows makes both rows show red, even though one selected language is already downloaded.

## UI/UX Design

- Keep the existing two-row layout and picker sizes.
- Render an independent compact status indicator before each picker at all times.
- Treat each row as a selected-language indicator, not a selected-pair indicator.
- Infer whether a language pack is installed by checking cached statuses for probe pairs involving that language and the app's common languages.
- If any probe pair involving the language is installed, show a green checkmark for that language.
- If no installed probe exists but supported or unsupported statuses exist, show a red unavailable marker.
- During a probe refresh, show only loading indicators for both rows until the whole refresh finishes.
- Preserve the existing click behavior: clicking an unavailable indicator rechecks availability and can show the download/settings alert.

## Implementation Plan

- Replace the global `statusIcon` placement with `languageStatusIcon(for:)` calls in both rows.
- Add a small `LanguageRole` enum to avoid passing raw booleans.
- Add `languageStatusProbePairs` for UI-only status checks, containing both directions between each selected language and the app's common languages.
- Keep `requiredLanguagePairs` for actual translation readiness and alert priority.
- Derive each row icon from the selected language's aggregate probe statuses.
- Refresh probe pairs so both row icons can resolve cached language-level status independently of bidirectional translation settings.
- Track a row-level refresh state for the full probe pass instead of binding icons directly to `LanguagePackManager.isChecking`, which toggles for each individual pair and can cause flicker.
- Keep user-facing alerts limited to actual `requiredLanguagePairs` so unrelated probe-pair failures do not trigger alerts.

## Validation

- Build the Debug scheme.
- Manually inspect Settings > General with German missing and Simplified Chinese installed.
- Expected: German shows a red marker, Simplified Chinese shows a green checkmark.
