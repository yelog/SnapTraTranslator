# LLM Delimiter Response Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent request-specific `SNAPTRA_TRANSLATION_TEXT` delimiters echoed by LLMs from appearing in final or streaming translation results.

**Architecture:** Keep the exact begin and end delimiters on each `LLMTranslationPrompt` and pass them to a shared response filter. The filter removes only those exact delimiters at response boundaries, buffers possible delimiter prefixes during streaming, and leaves unrelated or inline text unchanged.

**Tech Stack:** Swift, Foundation, XCTest, URLProtocol-backed SSE fixtures

---

### Task 1: Add delimiter echo regression tests

**Files:**
- Modify: `SnapTra TranslatorTests/SmokeTests.swift`

**Steps:**
1. Add an OpenAI-compatible streaming test whose response echoes the request delimiter across multiple SSE chunks.
2. Capture the generated delimiter from the request body so the fixture uses the request-specific value.
3. Assert that partial results and the final result contain only translated text.
4. Add assertions that a different delimiter ID and inline delimiter-like text are preserved.
5. Run the focused test and confirm it fails before implementation.

### Task 2: Preserve request delimiters and add the shared filter

**Files:**
- Modify: `SnapTra Translator/SentenceTranslationService.swift:383-1022`

**Steps:**
1. Add `beginDelimiter` and `endDelimiter` to `LLMTranslationPrompt`.
2. Return those values from `makeLLMTranslationPrompt`.
3. Add a small `LLMTranslationResponseFilter` that accepts accumulated response text.
4. Strip only the exact begin delimiter at the leading response boundary and exact end delimiter at the trailing response boundary.
5. During streaming, withhold text that may still become a delimiter prefix; release it if later input proves it is ordinary text.
6. Keep whitespace trimming behavior at finalization.

### Task 3: Integrate all LLM provider paths

**Files:**
- Modify: `SnapTra Translator/SentenceTranslationService.swift:383-861`

**Steps:**
1. Apply finalized filtering to OpenAI-compatible, Anthropic, and Gemini non-streaming responses.
2. Apply incremental filtering before every `onPartialResult` call in all three streaming implementations.
3. Return the same filtered value used for the last UI update.
4. Preserve retry behavior and reset filter state with accumulated output on retries.

### Task 4: Verify behavior

**Files:**
- Test: `SnapTra TranslatorTests/SmokeTests.swift`

**Steps:**
1. Run the focused `SentenceTranslationServiceStreamingTests` suite.
2. Run all tests for the project scheme.
3. Run a Debug build.
4. Review the diff to ensure no provider settings or prompt-injection protections changed.
