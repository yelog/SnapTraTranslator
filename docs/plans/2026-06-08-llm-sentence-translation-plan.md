# LLM Sentence Translation Implementation Plan

**Goal:** Add OpenAI, Anthropic, Gemini, DeepSeek, Ollama, and oMLX as configurable sentence translation providers.

**Architecture:** Extend the existing sentence translation source list instead of creating a parallel provider system. Cloud providers use default model and base URL presets plus a Keychain-stored API key; local providers default to OpenAI-compatible localhost endpoints. Translation prompts isolate user text with a per-request delimiter and instruct the model to treat that text as untrusted data.

**Tech Stack:** SwiftUI, URLSession, UserDefaults-backed settings, Keychain, existing paragraph overlay service result flow.

---

### Task 1: Provider Model And Defaults

**Files:**
- Modify: `SnapTra Translator/SettingsStore.swift`
- Modify: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add LLM source cases to `SentenceTranslationSource.SourceType`.
2. Add default display name, subtitle, model, base URL, and API key requirement helpers.
3. Add `LLMProviderConfiguration` persisted separately from source ordering.
4. Migrate existing saved source arrays by appending new providers disabled.
5. Add migration tests for source preservation and LLM configuration defaults.

### Task 2: LLM Translation Requests

**Files:**
- Modify: `SnapTra Translator/SentenceTranslationService.swift`

**Steps:**
1. Add a Keychain helper for provider API keys.
2. Add secure prompt construction with random delimiters and explicit untrusted-text instructions.
3. Implement OpenAI-compatible chat completions for OpenAI, DeepSeek, Ollama, and oMLX.
4. Implement Anthropic Messages API.
5. Implement Gemini generateContent API.
6. Add streaming request paths for LLM providers so paragraph service results can update while tokens arrive.
7. Return provider-specific missing configuration and HTTP error messages.

### Task 3: UI And Runtime Flow

**Files:**
- Modify: `SnapTra Translator/SentenceSettingsView.swift`
- Modify: `SnapTra Translator/DictionarySettingsView.swift`
- Modify: `SnapTra Translator/SentenceLatencyTester.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Steps:**
1. Show LLM providers in the existing reorderable sentence services list.
2. When an LLM provider is enabled, show compact model/base URL/API key fields inline.
3. Store API keys in Keychain and non-secret model/base URL values in UserDefaults.
4. Pass the selected provider configuration into paragraph translation requests.
5. Update LLM paragraph service results with partial streaming text.
6. Update latency testing to include enabled/configured LLM providers.

### Task 4: Verification

**Commands:**
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" test`
- `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build`

**Expected:** Tests pass and the app target builds without warnings introduced by the new provider code.
