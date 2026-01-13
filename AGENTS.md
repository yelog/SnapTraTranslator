# AGENTS.md

## Scope
- Applies to the entire repository at `/Users/yelog/workspace/swift/Snap Translate`.
- This file is intended for agentic coding assistants.

## Project Overview
- Xcode project: `Snap Translate.xcodeproj`.
- SwiftUI app source: `Snap Translate/`.
- No separate test targets or CLI tooling detected.

## Build / Run / Test Commands

### Build (CLI)
- Debug build:
  - `xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" -configuration Debug build`
- Release build:
  - `xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" -configuration Release build`

### Run
- Preferred: open in Xcode and run the `Snap Translate` scheme.
  - `open "Snap Translate.xcodeproj"`

### Clean
- `xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" clean`

### Tests
- No test target found in the project.
- Once a test target exists, use:
  - `xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" test`

### Run a Single Test (when tests exist)
- Use `-only-testing` with the test target:
  - `xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" test -only-testing:<TestTarget>/<TestCase>/<testMethod>`

### Lint / Format
- No `SwiftLint`, `SwiftFormat`, or `EditorConfig` config found.
- If you introduce lint/format tools, add config files at repo root and document commands here.

## Code Style Guidelines

### Formatting
- Indentation: 4 spaces (Xcode default).
- Use trailing commas for multiline collections and parameter lists.
- Keep `body` and view builders vertically aligned and indented consistently.
- Prefer line breaks for view modifier chains once they exceed one line.
- Avoid trailing whitespace and excessive vertical spacing.

### Imports
- One `import` per line.
- Keep `SwiftUI` at the top when it is used.
- Avoid unused imports.

### Naming
- Types and protocols: `UpperCamelCase`.
- Variables, functions, and properties: `lowerCamelCase`.
- Boolean properties: affirmative names (`isEnabled`, `hasFocus`).
- SwiftUI views: suffix with `View` only when it clarifies intent.
- File names should match the primary type when practical.

### Types and APIs
- Prefer explicit types at public boundaries.
- Use type inference for local values when it improves readability.
- Avoid force unwraps (`!`); use `guard`, `if let`, or `throws`.
- Avoid `as!`; use safe casts with `as?` and handle nil.

### Error Handling
- Use `throws` for recoverable failures.
- Convert errors to user-visible messages at the UI boundary.
- Prefer `Result` only when you need to store or pass outcomes.
- Do not swallow errors; log or surface them.

### SwiftUI Patterns
- Keep `body` small; extract subviews for complex layouts.
- Use `@State` for local UI state and `@ObservedObject` / `@StateObject` for model state.
- Prefer view modifiers for styling over wrapper views.
- Use `@MainActor` when interacting with UI state from async code.

### View Composition
- Favor small, reusable views over deeply nested stacks.
- Use `ViewBuilder` helpers for conditional composition.
- Group modifier chains by purpose (layout, style, behavior).
- Use `Spacer()` intentionally to express layout intent.
- Prefer `Label` for icon + text pairs when possible.

### State and Data Flow
- Keep a single source of truth for view state.
- Use `@State` for view-owned state and `@StateObject` for owned models.
- Use `@ObservedObject` or `@EnvironmentObject` for injected models.
- Avoid mutating state directly inside `body`.
- Trigger side effects from `task`, `onAppear`, or explicit actions.

### Accessibility
- Provide accessibility labels for non-text buttons and images.
- Avoid embedding critical text inside images.
- Use system colors and dynamic type where possible.
- Ensure tappable areas meet minimum size expectations.

### Previews
- Keep previews lightweight and deterministic.
- Supply sample data for empty and populated states.
- Avoid network calls in previews.

### File Organization
- One primary type per file when practical.
- Group extensions below the main type definition.
- Keep related types close to their primary view or model.

### Logging and Diagnostics
- Use `Logger` if structured logging is introduced.
- Avoid leaving debug `print` statements in production code.

### Dependencies
- Avoid adding dependencies without explicit approval.
- If a dependency is added, document it in this file.

### Testing Guidance
- Add a test target before writing unit tests.
- Prefer XCTest for native Swift tests.
- Keep tests deterministic and fast.
- Avoid network calls in unit tests; use stubs.

### Concurrency
- Use Swift Concurrency (`async`/`await`) for asynchronous work.
- Avoid blocking the main thread; offload work to tasks.
- Wrap UI updates in `MainActor.run` if called off-main.

### Localization
- Use `LocalizedStringKey` / `Text("...")` for user-facing strings.
- Prefer string catalogs if localization is added.

### Assets
- Put image and color assets in `Assets.xcassets`.
- Reference assets by name via `Image("name")` or `Color("name")`.

## Repository Conventions (Observed)
- Minimal project with a single SwiftUI app target.
- File headers include Xcode template comments.

## Editor / Assistant Rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.
- If any are added later, mirror them here.

## Change Discipline
- Keep changes minimal and focused.
- Avoid refactors unless they are required for the task.
- Do not add new dependencies without explicit request.
