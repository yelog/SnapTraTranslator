# Native Core Placeholder

This directory is reserved for future shared native code that is proven worth extracting.

Intended scope:
- Dictionary storage helpers
- Text normalization
- OCR post-processing helpers
- Configuration parsing or other pure logic

Non-goals for the first phase:
- UI
- Window management
- Hotkeys
- Permissions
- Screen capture shells

Current rule:
- The macOS App Store target should continue using the existing Apple-first implementation path unless there is a clear, reviewed reason to link shared native code.
