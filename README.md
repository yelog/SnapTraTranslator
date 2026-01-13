# Snap Translate

[简体中文](README.zh-CN.md)

A lightweight macOS SwiftUI app that translates text at your cursor via screen capture and OCR. Press the hotkey, hover anywhere, and get a floating bubble with translation, phonetics, and optional pronunciation.

## Features
- Instant overlay bubble near your cursor with translation results
- OCR capture around the cursor; selects the word closest to the pointer
- Optional phonetics and text-to-speech playback for source language
- Configurable source/target languages and single-key hotkey
- Debug OCR region overlay for troubleshooting word selection

## Requirements
- macOS 14+ (translation bridge requires macOS 15 for system translation APIs)
- Screen Recording and Accessibility/Input Monitoring permissions enabled for the app

## Build & Run
- Xcode: open `Snap Translate.xcodeproj`, scheme **Snap Translate**, run in Debug.
- CLI build: `xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" -configuration Debug build`
- Clean: `xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" clean`

## Usage
1) Launch the app and grant Screen Recording and Accessibility/Input Monitoring permissions when prompted.
2) Set the single-key hotkey and language pair in Settings.
3) Hold the hotkey and hover over text; a bubble appears near the cursor with translation and phonetics. Release the hotkey to dismiss.
4) Enable “Debug OCR Region” in Settings if you need to visualize the capture area and detected words.

## Troubleshooting
- If no bubble appears, re-check Screen Recording permission and ensure the hotkey is active.
- For missing translations on macOS 15, install required language packs in **System Settings > General > Language & Region > Translation**.
- If the bubble is clipped near screen edges, enable Debug OCR Region to confirm capture area and adjust hover location.

## License
Not specified. If you intend to distribute, add a license file.
