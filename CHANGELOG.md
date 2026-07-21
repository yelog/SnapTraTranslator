# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.11-beta.0] - 2026-07-21

### Fixed
- dismiss persistent panels on app switch
- dismiss persistent sentence panels outside

## [1.3.10] - 2026-07-20

### Changed
- add 1.3.10-beta.2 release entry [skip ci]

## [1.3.10-beta.2] - 2026-07-16

### Changed
- record hotkey lookup P0 validation
- optimize hotkey word lookup pipeline
- instrument word lookup stages
- add correlated lookup traces
- plan hotkey lookup P0 optimization
- Fix translation overlay across Spaces
- optimize Learning page for large record sets
- add 1.3.10-beta.1 release entry [skip ci]

## [1.3.10-beta.1] - 2026-07-03

### Added
- add in-place translation overlay
- support text selection and copy in in-place overlay
- align in-place overlay text to source
- style in-place overlay from capture
- estimate in-place overlay colors
- add animated loading beam for image translation
- add Baidu image translation
- support Baidu image translation v2
- add Cmd+C clipboard fallback for apps without accessibility support
- add double-tap sentence range mode

### Fixed
- show correct provider title for selected text in image translation mode
- reduce in-place minimum rect thresholds from 120x24 to 40x14
- refine clipboard fallback with bounds validation and source tracking
- make clipboard fallback async to fix double-tap hotkey
- make in-place overlay opaque
- clarify sentence translation labels
- accept initial manual region click
- avoid activating app for manual region selection
- honor system translation toggle
- stabilize word header phonetic layout

## [1.3.10-beta.0] - 2026-06-29

### Added
- add manual region selection
- keep selected text bubble after tap
- keep word bubble after tap
- default bidirectional translation and hide original text to enabled
- generalize bidirectional detection and show provider language support
- show language pack download status in language pickers
- add plain text word export
- add Zhipu LLM provider
- add streaming LLM translation
- add outside dismissal and hide original option
- track word source languages

### Changed
- improve paragraph highlight resize interaction
- default sentence pronunciation to off
- reduce LLM reasoning latency

### Fixed
- show highlight for manual OCR regions
- keep original text visible after manual input submit
- keep manual input visible after typing when OCR finds no text
- remove private dictionary services symbols
- improve Chinese word lookup segmentation
- dismiss kept word overlay with escape
- stabilize OCR region resize drag
- allow selecting kept word text
- keep tap-kept bubble reachable below cursor
- enable tap-kept word bubble by default
- keep primary word translation stable
- strip inline pinyin annotations from system dictionary translations
- prefer bilingual content and suppress redundant English for en→zh lookups
- prevent window jitter on language direction toggle
- preserve English content in ECDICT definitions and translations
- relax selected text bounds routing
- normalize LLM OCR line breaks
- refine hidden original sentence overlay
- translate non-English text lines
- stabilize language pack status indicators
- recover skipped mixed-text words

## [1.3.9] - 2026-06-15

### Added
- keep selected text bubble after tap for quick re-reference
- add outside tap dismissal and hide original text option for overlays
- add resizable OCR sentence regions with drag handles
- edit pinned sentence source text directly
- add paragraph target language selector in sentence view
- add streaming LLM translation for faster response
- add Zhipu LLM provider for sentence translation
- add plain text word export for learning lists
- track word source languages in learning data
- export words for Anki flashcards
- add menu bar icon style setting
- show language pack download status in language pickers
- default bidirectional translation and hide original text to enabled

### Changed
- improve paragraph highlight resize interaction
- refine sentence overlay visuals
- default sentence pronunciation to off
- generalize bidirectional detection and show provider language support
- reduce LLM reasoning latency

### Fixed
- stabilize OCR region resize drag
- allow selecting kept word text
- keep tap-kept bubble reachable below cursor
- keep primary word translation stable during updates
- strip inline pinyin annotations from system dictionary translations
- prefer bilingual content and suppress redundant English for en→zh lookups
- prevent window jitter on language direction toggle
- preserve English content in ECDICT definitions and translations
- relax selected text bounds routing for better word selection
- normalize LLM OCR line breaks
- refine hidden original sentence overlay behavior
- translate non-English text lines correctly
- stabilize language pack status indicators
- recover skipped mixed-text words during OCR
- focus editable paragraph input properly
- switch paragraph direction on target language change
- resolve word list pagination never loading remaining data
- improve responsive settings layout
- skip target-language words without bidirectional mode
- emit hotkey release event when shortcut is lifted
- exclude only overlay windows from screen capture
- recover hotkey after system wake
- improve export toolbar layout in learning view
- align system picker layout in settings
- optimize word list scrolling performance

## [1.3.9-beta.5] - 2026-05-18

### Added
- add resizable OCR sentence regions
- edit pinned sentence source text

### Changed
- refine sentence overlay visuals
- add 1.3.9-beta.4 release entry [skip ci]

### Fixed
- focus editable paragraph input
- switch paragraph direction on target change

## [1.3.9-beta.4] - 2026-05-14

### Added
- add paragraph target language selector

## [1.3.9-beta.3] - 2026-05-11

### Changed
- paginate word list loading

### Fixed
- resolve word list pagination never loading remaining data
- improve responsive settings layout

## [1.3.9-beta.2] - 2026-05-10

### Changed
- add 1.3.9-beta.1 release entry [skip ci]

### Fixed
- skip target-language words without bidirectional mode
- emit release when shortcut is lifted

## [1.3.9-beta.1] - 2026-05-10

### Changed
- optimize word list scrolling
- add 1.3.9-beta.0 release entry [skip ci]

### Fixed
- exclude only overlay windows from capture
- recover after system wake
- improve export toolbar layout
- align system picker layout

## [1.3.9-beta.0] - 2026-05-10

### Added
- export words for Anki
- add menu bar icon style setting

### Changed
- update project build version

## [1.3.8] - 2026-05-06

### Added
- improve word bounding box accuracy and selection logic
- add bidirectional Chinese word lookup support

### Fixed
- align mixed-script word hit boxes
- prevent background termination of menu bar app
- handle Chinese text with English terms
- refine code token hit boxes
- strip pinyin from Chinese system definitions
- detect dominant script in mixed text
- reduce idle overlay overhead
- gate selected text translation

## [1.3.8-beta.3] - 2026-04-28

### Added
- improve word bounding box accuracy and selection logic

### Fixed
- refine code token hit boxes
- handle Chinese text with English terms
- strip pinyin from Chinese system definitions
- detect dominant script in mixed text

## [1.3.8-beta.2] - 2026-04-22

### Added
- add bidirectional Chinese word lookup support

## [1.3.8-beta.1] - 2026-04-20

### Changed
- add 1.3.8-beta.0 release entry [skip ci]

### Fixed
- reduce idle overlay overhead

## [1.3.8-beta.0] - 2026-04-09

### Fixed
- gate selected text translation

## [1.3.7] - 2026-04-07

### Added
- add word learning module with spaced repetition
- add localization support for Learning module
- add Show Dock Icon toggle in System tab
- add Copy to Clipboard option for word and sentence translation
- add configurable third-party dictionary sources
- add selected text translation flow
- add pin and copy buttons for paragraph overlay
- set system dictionary as default first source

### Changed
- add System tab and move launch/menu bar/language settings
- optimize storage and add auto cleanup for learning module
- add localizations for auto cleanup feature
- add System tab label translations
- remove Spanish language support
- stop TimelineView animation when highlight window is hidden
- remove fixed width from filter picker for compact layout
- increase general tab content height

### Fixed
- persist showDockIcon setting across app restarts
- hide Dock icon immediately when toggle is turned off
- move Learning tab below pronunciation options
- improve selected text translation accuracy and readability
- improve selected text accessibility lookup
- avoid unsupported predicate forced unwrap
- prevent settings window from showing on restart
- restore paragraph original selection
- align original copy button
- improve paragraph panel dragging
- correct sentence panel pin and escape states

## [1.3.7-beta.7] - 2026-04-07

## [1.3.7-beta.6] - 2026-04-07

## [1.3.7-beta.5] - 2026-04-07

### Changed
- set system dictionary as default first source

## [1.3.7-beta.4] - 2026-04-07

### Changed
- set system dictionary as default first source

## [1.3.7-beta.3] - 2026-04-06

### Added
- add pin and copy buttons for paragraph overlay
- add selected text translation flow
- add configurable third-party sources
- add Copy to Clipboard option for word and sentence translation
- add Show Dock Icon toggle in System tab
- add localization support for Learning module
- add word learning module with spaced repetition

### Changed
- increase general tab content height from 580 to 650
- stop TimelineView animation when highlight window hidden
- add localizations for auto cleanup feature
- optimize storage and add auto cleanup
- add third-party dictionaries design
- add System tab label translations
- remove Spanish language support
- add System tab and move launch/menu bar/language settings
- remove fixed width from filter picker for compact layout

### Fixed
