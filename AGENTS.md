# Tekmor

Tekmor builds and flashes STM32 firmware and monitors serial ports on Apple Silicon (macOS 15+, Swift 6). `Workspace` owns SwiftUI state and task lifecycles on the main actor. `TekmorCore` coordinates build, flash and reset through `STM32Workflow`. Run external tool commands through `CommandRunner` for cancellation and timeouts. `TekmorWorkbench` owns console buffering and search, build diagnostic locations and workbench layout.

## Project and hardware contracts

- Validate the in-memory configuration with `ProjectConfiguration.validate()`. Persist per-project selections through `ProjectPreferences` in app-local `UserDefaults`.
- Keep Tekmor configuration outside imported projects and treat their CMake files and presets as read-only. Build in Tekmor's cache. When cleaning a project, remove only its own cache directories.
- In the app, identify the target and require confirmation before flashing dropped firmware or erasing internal flash. Raw BIN files require an explicit load address.
- During pre-release, keep internal databases, data structures and wire formats at version `1`. Edit the current schema directly without migrations, legacy branches or compatibility aliases.

## Swift and localization

- Document public APIs with `///`. Prefer optional binding and conditional casts. Document any non-obvious safety invariant for a necessary force unwrap or forced cast. Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Route UI copy through `AppL10n` and `Tekmor/Resources/Localizable.xcstrings`. Use `TekmorLocalization` and the core module's `Localizable.strings` for user-facing core messages. Match format placeholders across `en` and `zh-Hans`.

## Validation

Run checks from the repository root. For Swift changes, format and run strict lint, including the icon generator under `Design/AppIcon/`.

```bash
swift_sources=(Package.swift Sources Tekmor Tests Design)
xcrun swift-format format -ir "${swift_sources[@]}"
xcrun swift-format lint -sr "${swift_sources[@]}"
```

Reuse existing temporary project and command fixtures for workflow tests where applicable. Run focused tests during development and `swift test` at completion for both `TekmorCoreTests` and `TekmorWorkbenchTests`. For changes to the app, resources or Xcode project settings, also build the `Tekmor` scheme.

```sh
xcodebuild -project Tekmor.xcodeproj -scheme Tekmor -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode build
```

Docs-only changes may skip tests with a note. After further edits, failures or new evidence, rerun affected checks only. Fix regressions introduced by the change and report unrelated failures or remaining limitations.

## Workflow and Git

- Implement and validate without waiting for plan approval. Decide reversible details independently. Ask only when ambiguity materially affects acceptance or a decision about data loss, external protocol breaks or new dependencies lacks authorization. Continue independent work while waiting. Report authorized breaking changes.
- Commit or push only on explicit request. Give each commit one logical change and a Gitmoji title of the form `<emoji> <concise Chinese summary>`. Gitmoji is optional for PR titles.
- Prefer stacked PRs for dependent, independently reviewable changes. Keep each stack in one repository. Target trunk with the first PR and the preceding branch with each subsequent PR. Open separate PRs against the appropriate trunk for unrelated changes.
