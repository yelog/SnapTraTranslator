# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release

## [1.3.1] - 2026-03-13

### Added
- separate TTS providers for word and sentence pronunciation
- add separate pronunciation toggles for word and sentence
- improve DeepL translation with direct API and error tooltips
- add auto-dismiss countdown to error views

### Changed
- simplify version display by removing build number
- add .gitignore to exclude .agent directory
- delete useless file
- add GitHub Actions release workflow
- adjust window sizes for General and About tabs
- remove latency testing for offline-only dictionaries
- remove FreeDict and simplify pronunciation UI
- remove DeepL from sentence translation services
- rename Dictionary tab to Word and widen sidebar
- split pronunciation into separate Word and Sentence tabs
- reorganize settings tabs with sidebar navigation
- move sentence translation settings to Dictionary tab
- pass localization keys for dynamic translation

### Fixed
- use semantic versioning format for MARKETING_VERSION
- make paragraph translation errors respond to language changes
- stop speaking when overlay is closed

## [1.3.0] - 2026-03-13

### Added
- Initial release of SnapTra Translator
- OCR-based screen text recognition
- Multi-language translation support
- Menu bar quick access
- Offline dictionary support
- Text-to-speech functionality
- Customizable hotkeys
