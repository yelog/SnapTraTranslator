# Learning Feature Design

## Overview

Add a learning module to the Settings > Service tab to track word lookups, display high-frequency words, and provide spaced repetition reminders based on the Ebbinghaus forgetting curve.

## Requirements Summary

1. **Location**: New sidebar item "Learning" in Service Tab (alongside Dictionary / Sentence / Pronunciation)
2. **Record Scope**: Only record word lookups (not paragraph translations)
3. **Learning Curve**: Ebbinghaus forgetting curve reminders
4. **Storage**: SwiftData

## Data Model

### WordRecord

```swift
@Model
class WordRecord {
    var word: String
    var lookupCount: Int
    var firstLookupDate: Date
    var lastLookupDate: Date
    var nextReviewDate: Date?
    var isMastered: Bool
    var reviewStage: Int  // 0-5, for Ebbinghaus stages
}
```

### Ebbinghaus Intervals

| Stage | Interval |
|-------|----------|
| 0 | 1 day |
| 1 | 3 days |
| 2 | 7 days |
| 3 | 15 days |
| 4 | 30 days |
| 5 | Mastered (no more reminders) |

## Components

### 1. LearningService

- Record word lookups
- Calculate next review dates
- Query words for review
- Mark words as mastered

### 2. LearningSettingsView

- Statistics card (total words, pending review, mastered)
- Word list (searchable, filterable by status)
- Mark as mastered action
- Trigger review notification

### 3. NotificationService

- Schedule local notifications for review reminders
- Handle notification actions

## User Flow

1. User looks up a word via hotkey
2. `AppModel` records the word via `LearningService`
3. `LearningService` creates/updates `WordRecord` with review schedule
4. User opens Settings > Service > Learning
5. Sees word list sorted by frequency (high to low)
6. Can filter "Pending Review" words
7. Can mark words as "Mastered"
8. System sends notification when review time arrives

## Files to Create/Modify

### New Files
- `WordRecord.swift` - SwiftData model
- `LearningService.swift` - Business logic
- `LearningSettingsView.swift` - UI view
- `NotificationService.swift` - Local notifications

### Modified Files
- `DictionarySettingsView.swift` - Add Learning tab
- `Snap_TranslateApp.swift` - Configure SwiftData container
- `AppModel.swift` - Record word lookups
- `AppSettings.swift` - Add learning-related settings keys
- `SettingsStore.swift` - Add learning toggle settings

## Implementation Order

1. Create `WordRecord.swift` (SwiftData model)
2. Create `LearningService.swift`
3. Create `LearningSettingsView.swift`
4. Modify `DictionarySettingsView.swift` (add tab)
5. Configure SwiftData in `Snap_TranslateApp.swift`
6. Integrate with `AppModel.swift` (record lookups)
7. Implement `NotificationService.swift`