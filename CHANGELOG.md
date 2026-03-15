# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.4-beta.5] - 2026-03-15

### Added
- 改进更新检查按钮交互体验
- 根据更新通道跳转到对应的 GitHub Release 页面

## [Unreleased]

### Added
- Initial release

## [1.3.4-beta.4] - 2026-03-15

### Fixed
- 下拉菜单中连续翻译选项不显示勾选状态的问题
- 切换更新频道后无法立即生效的问题
- debug模式下检查更新通道选择器不生效的问题

## [1.3.4-beta.3] - 2026-03-15

### Added
- Add debug toggle for GitHub release channel selector in menu bar for testing

### Fixed
- Make update channel selector toggle work in real-time without restart
- Relax OCR selection and merge split lines in paragraph mode
- Size paragraph text from actual panel width
- Only show update channel options for GitHub releases
- Move debug OCR option and auto-disable on sentence translation
- Prevent panel from showing without screen recording permission
- Increase about page height for GitHub releases

## [1.3.4-beta.2] - 2026-03-14

### Fixed
- align Sparkle feeds and GitHub build versioning

## [1.3.4-beta.1] - 2026-03-14

### Fixed
- improve distribution channel detection and always init Sparkle
- correct sparkle:edPublicKey position in appcast files

## [1.3.4-beta.0] - 2026-03-14

### Added
- add update channel selector for GitHub releases

### Fixed
- correct distribution channel detection logic

## [1.3.3] - 2026-03-14

### Added
- integrate Sparkle for automatic in-app updates
- support different update channels for GitHub vs App Store

### Fixed
- correct App Store URL and ID for update check

## [1.3.2] - 2026-03-13

### Changed
- align release build with Xcode 26.3

### Fixed
- prevent audio playback after overlay dismissal

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
