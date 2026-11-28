## Quick Overview

Tekmor is a native macOS STM32 build, flashing, and serial monitoring tool for Apple Silicon.

- `Tekmor/` is the SwiftUI application. `TekmorApp` is the entry point, and `Workspace` manages UI state, commands, and task lifecycles on the main actor.
- `Sources/TekmorCore/` is the Swift Package core module. `STM32Workflow` orchestrates build, flash, and reset flows, with tool logic maintained in `CMakeBuild` and `CubeProgrammer`. External commands use `CommandRunner` for cancellation and timeout handling.
- `Tests/TekmorCoreTests/` uses Swift Testing. Prefer reusing existing temporary project and command fixtures when verifying tool invocations or workflows.
- `Design/AppIcon/` contains the app icon's drawing source and generator.
- `Distribution/` contains release packaging scripts.

## Swift Style Guide

Prioritize clarity at the point of use. Use `UpperCamelCase` for types and protocols, and `lowerCamelCase` for methods, properties, variables, and enum cases. Name by role, omit redundant type information, and choose argument labels that read naturally at call sites (e.g., `insert(_:at:)`).

- Use imperative verbs for mutating methods, noun phrases for non-mutating methods, and assertions for boolean properties/queries (e.g., `isEmpty`). Pair mutating and non-mutating operations consistently (e.g., `sort()` and `sorted()`).
- Use `guard` for early exits to keep the main flow shallow. Prefer optional binding and conditional casts over force unwrapping; when force unwrapping or casting is necessary, document the non-obvious safety invariant in a comment.
- Name files after their primary type or responsibility, organize members by responsibility, and group with `// MARK:` when helpful. Document public APIs with `///` summarizing behavior, parameters, return values, and thrown errors where relevant.

References: [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/), [Google Swift Style Guide](https://google.github.io/swift/), and [Airbnb Swift Style Guide](https://swift.airbnb.tech/).

Formatting follows the repository root `.swift-format` (2-space indentation, 100-column line width). Format and run strict lint checks matching CI:

```bash
swift_sources=(Package.swift Sources Tekmor Tests Design)
xcrun swift-format format -ir "${swift_sources[@]}"
xcrun swift-format lint -sr "${swift_sources[@]}"
```

## Localization

- App UI copy goes through `AppL10n`, backed by entries in `Tekmor/Resources/Localizable.xcstrings`.
- Core module user-facing messages go through `TekmorLocalization`, backed by `en` and `zh-Hans` `Localizable.strings` under `Sources/TekmorCore/Resources/`. Verify format placeholders across both languages when editing interpolated strings.

## Pre-Release Data Contracts

Tekmor is pre-release: keep internal databases, data structures, and wire formats pinned at version `1`. Maintain a single current schema directly without adding upgrade chains, legacy branches, compatibility aliases, or data migrations.

Project configuration is maintained in memory only and validated via `ProjectConfiguration`; never write config files into imported project directories. Write build artifacts to Tekmor's build cache and leave imported projects' CMake files and presets untouched.

## Write Code

Proceed through implementation and applicable validation without waiting for plan approval. Decide reversible implementation details independently and do not reconfirm actions already authorized. Ask only about ambiguities that materially affect acceptance or unauthorized decisions involving data loss, breaking external protocols, or adding dependencies. Continue independent work while awaiting an answer. Declare authorized breaking changes in the final response.

## Commit Convention

Use Gitmoji format: `<emoji> <concise Chinese>` (no `feat:`/`fix:` prefix), e.g., `✨ 新增串口发送功能`.
Do not commit or push unless explicitly requested; reporting completion ≠ committing.

## Branch, Commit, and PR Contracts

- Keep each commit focused on one logical change and follow the Commit Convention above.
- When a larger change can be split into independently reviewable layers and an upper layer depends on unmerged lower-layer work, prefer stacked pull requests: target the bottom PR at the trunk and each higher PR at the immediately preceding branch. Keep unrelated changes in separate PRs targeting the appropriate trunk; all branches in a stack must belong to the same repository.
- Pull request titles do not need Gitmoji.

## Validation

Run `swift test` at the repository root to verify the core module. When changes touch app code, resources, or project settings, also build the `Tekmor` scheme (matching [macOS CI](.github/workflows/ci.yml)):

```sh
xcodebuild -project Tekmor.xcodeproj -scheme Tekmor -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode build
```

Run scoped tests during iteration and the full suite once at the end; docs-only changes may skip tests with a note. Rerun affected checks only after further changes, failures, or new evidence. Fix failures caused by the requested change; report unrelated failures without expanding scope. Work is complete when the requested behavior is implemented, applicable validation is complete, and any remaining limitations are reported.
