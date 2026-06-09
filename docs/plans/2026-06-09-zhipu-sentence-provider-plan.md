# Zhipu Sentence Provider Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Zhipu as a sentence-translation LLM provider with domestic/global endpoint selection.

**Architecture:** Treat Zhipu as an OpenAI-compatible LLM provider so translation, streaming, prompt safety, and retry behavior reuse the existing Chat Completions transport. Store the selected Zhipu region in the provider configuration and let the region picker reset Base URL to the corresponding official endpoint.

**Tech Stack:** Swift, SwiftUI, Codable settings migration, URLSession streaming tests, XCTest.

---

### Task 1: Settings Model

**Files:**
- Modify: `SnapTra Translator/SettingsStore.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add `.zhipu` to `SentenceTranslationSource.SourceType`.
2. Add `ZhipuAPIRegion` with `domestic` and `international` cases.
3. Add optional `zhipuRegion` to `LLMProviderConfiguration`.
4. Default Zhipu to model `glm-4.7-flash`, domestic URL `https://open.bigmodel.cn/api/paas/v4`, and international URL `https://api.z.ai/api/paas/v4`.
5. Migrate missing Zhipu configuration into existing settings without changing enabled state for old providers.

### Task 2: Settings UI

**Files:**
- Modify: `SnapTra Translator/SentenceSettingsView.swift`

**Steps:**
1. Add icon, display name, and subtitle switch cases for Zhipu.
2. Show a region segmented picker only for Zhipu.
3. When the region changes, keep the current model and update Base URL to the selected region default.

### Task 3: Translation Routing

**Files:**
- Modify: `SnapTra Translator/SentenceTranslationService.swift`
- Modify: `SnapTra Translator/SentenceLatencyTester.swift`

**Steps:**
1. Route `.zhipu` through the OpenAI-compatible translation and streaming path.
2. Require API Key for Zhipu.
3. Send `thinking: { "type": "disabled" }` for Zhipu sentence translation.
4. Ensure latency testing includes Zhipu.

### Task 4: Verification

**Files:**
- Modify: `SnapTra TranslatorTests/SmokeTests.swift`
- Modify: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Test default Zhipu model, URL, and region.
2. Test migration appends Zhipu.
3. Test streaming Zhipu request uses the configured URL and disables thinking.
4. Run targeted tests, Debug build, and `git diff --check`.
