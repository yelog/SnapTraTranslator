# Baidu Image Translation Implementation Plan

**Goal:** Add an optional image translation display mode for sentence translation, with Baidu as the first configurable image translation provider.

**Requirement Analysis:** The existing sentence flow has two display modes: overlay panel and in-place text replacement. Both depend on local OCR text extraction and text translation providers. Baidu picture translation is a different service shape: it accepts image bytes, signs the original image hash, and can return translated summary text or paste images. It should therefore be modeled as an image translation provider instead of being mixed into the existing text sentence provider list.

**UI/UX Design:** Add `Image Translation` to `Sentence Display`. When selected, the double-tap sentence flow uses the captured paragraph or manual region image as the translation input and renders the provider-returned translated image back over the selected region, matching the intent of in-place translation instead of opening the sentence overlay. In Settings > Service > Sentence, add a compact `Image Translation` section below the existing sentence services. The section exposes a Baidu row with an enable toggle, App ID, Secret Key, and Endpoint. Secret Key is stored in Keychain; App ID and Endpoint are stored with other settings. Existing sentence service ordering, latency refresh, and text in-place modes remain unchanged.

**Implementation Plan:**

1. Add tests for the new display mode, image provider defaults, provider configuration migration, and Baidu request signing.
2. Add `ImageTranslationProvider`, `ImageTranslationSource`, `ImageTranslationProviderConfiguration`, persistent settings, migration helpers, and Keychain credential storage.
3. Add `ImageTranslationService` with Baidu multipart request construction, language mapping, md5 signing, and response parsing.
4. Extend sentence service settings UI with a new image translation provider section.
5. Route paragraph and manual-region sentence translation through image translation when `Sentence Display` is set to `Image Translation`, then display Baidu `pasteImg` in-place over the source region.
6. Add localized strings and run targeted tests, `jq empty` for the string catalog, `git diff --check`, and a Debug build.
