# Windows Native Shell Placeholder

This directory is reserved for the future native Windows shell.

Planned scope:
- WinUI 3 for settings and standard app surfaces
- Win32 integration for tray icon, global hotkeys, and message loop
- Windows screen capture and OCR where available
- Shared dictionary assets and text-processing contracts from the main repository

Rules for future work:
- Do not add unfinished project files until the service boundaries in the macOS codebase are stable.
- Keep platform shell code out of the existing macOS Xcode target.
- Reuse shared data formats and contracts before introducing new cross-platform dependencies.
