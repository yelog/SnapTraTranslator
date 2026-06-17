# App Store Private Dictionary Symbol Removal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for behavior changes.

**Goal:** Remove the private Dictionary Services symbols that caused App Store rejection while preserving the public system dictionary fallback.

**Architecture:** Keep `System Dictionary` as a local dictionary source, but restrict it to the public `DCSCopyTextDefinition(nil, ...)` lookup path. When the default system dictionary returns English-only content for Chinese targets, let the existing translation pipeline translate that default result instead of enumerating installed dictionaries.

**Tech Stack:** Swift, CoreServices Dictionary Services, Bash, xcodebuild

---

### Task 1: Capture The Failing Symbol Baseline

**Files:**
- Modify: none

**Steps:**
1. Build the Release app.
2. Run `nm -u` against `SnapTra Translator.app/Contents/MacOS/SnapTra Translator`.
3. Confirm `_DCSCopyAvailableDictionaries` is present before the fix.

### Task 2: Remove Private Dictionary Enumeration

**Files:**
- Modify: `SnapTra Translator/Snap_Translate-Bridging-Header.h`
- Modify: `SnapTra Translator/DictionaryService.swift`

**Steps:**
1. Remove manual declarations for `DCSCopyAvailableDictionaries` and `DCSDictionaryGetName`.
2. Remove the branch that enumerates installed dictionaries.
3. Keep parsing of the default `DCSCopyTextDefinition(nil, ...)` result.
4. Preserve fallback behavior where English-only definitions continue through the translation pipeline.

### Task 3: Add A Release Symbol Check

**Files:**
- Create: `scripts/build/check-app-store-symbols.sh`

**Steps:**
1. Accept either a `.app` path or executable path.
2. Scan undefined symbols with `nm -u`.
3. Fail if known App Store-risk Dictionary Services symbols are present.
4. Allow `_DCSCopyTextDefinition` because it is declared in the public Dictionary Services header and is not the rejected symbol.

### Task 4: Verify

**Commands:**

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release build
bash scripts/build/check-app-store-symbols.sh "/Users/yelog/Library/Developer/Xcode/DerivedData/SnapTra_Translator-breahagozdqrclcsibxrjnuamiff/Build/Products/Release/SnapTra Translator.app"
rg -n "DCSCopyAvailableDictionaries|DCSDictionaryGetName" "SnapTra Translator"
git diff --check
```

**Expected:** Release build succeeds, the symbol check passes, and no source reference to the private symbols remains.
