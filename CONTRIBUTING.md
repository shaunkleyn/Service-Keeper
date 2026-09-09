# Contributing to Service Keeper

Thank you for considering contributing to Service Keeper! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Submitting Changes](#submitting-changes)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)

## Code of Conduct

This project adheres to a simple code of conduct:

- Be respectful and constructive
- Welcome newcomers and help them learn
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

### Prerequisites

- Flutter 3.24+ installed
- Android SDK with API 26+ support
- A physical Android device (emulators don't support Shizuku)
- Shizuku installed and running on your test device
- Git for version control

### Setting up your development environment

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/Service-Keeper.git
   cd Service-Keeper
   ```
3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/shaunkleyn/Service-Keeper.git
   ```
4. **Install dependencies**:
   ```bash
   flutter pub get
   ```
5. **Connect your Android device** and verify Flutter can see it:
   ```bash
   flutter devices
   ```
6. **Run the app**:
   ```bash
   flutter run
   ```

## Development Workflow

### Creating a feature branch

Always create a new branch for your work:

```bash
git checkout -b feature/my-new-feature
# or
git checkout -b bugfix/issue-123
# or
git checkout -b docs/improve-readme
```

Branch naming conventions:
- `feature/` — new features
- `bugfix/` — bug fixes
- `docs/` — documentation changes
- `refactor/` — code refactoring
- `test/` — test improvements

### Keeping your fork updated

Regularly sync with upstream:

```bash
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

## Coding Standards

### Dart (Flutter)

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide
- Use `flutter format .` before committing
- Run `flutter analyze` and fix all warnings
- Maximum line length: 80 characters (can be flexible for readability)
- Use meaningful variable and function names
- Add doc comments for public APIs

Example:
```dart
/// Restarts a background service using Shizuku.
///
/// Returns true if the restart command was sent successfully.
/// Throws [ShizukuException] if Shizuku is not running.
Future<bool> restartService(String packageName, String serviceName) async {
  // Implementation
}
```

### Kotlin (Android native)

- Follow [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html)
- Use Android Studio's auto-formatting (Ctrl+Alt+L)
- Prefer `val` over `var` when possible
- Use null safety features (`?.`, `?:`, `!!` sparingly)
- Add KDoc comments for public functions

Example:
```kotlin
/**
 * Executes a shell command via Shizuku.
 *
 * @param command The shell command to execute
 * @return The command output, or null if failed
 */
fun executeShellCommand(command: String): String? {
    // Implementation
}
```

### File organization

- Keep files under 500 lines when possible
- Group related functionality together
- Use clear directory structure:
  ```
  lib/
    models/       # Data models
    screens/      # UI screens
    widgets/      # Reusable widgets
    services/     # Business logic
    utils/        # Helper functions
  ```

## Testing Guidelines

### Manual testing checklist

Before submitting a PR, test on a real device:

- [ ] App builds without errors
- [ ] All new features work as expected
- [ ] No regressions in existing features
- [ ] Shizuku integration still works
- [ ] UI looks good on different screen sizes
- [ ] No crashes or ANRs
- [ ] Background monitoring continues after device reboot
- [ ] Audit log records events correctly

### Testing environments

Test on multiple Android versions if possible:
- Minimum: Android 8.0 (API 26)
- Recommended: Android 10+ (API 29+)
- Latest: Android 14+ (API 34+)

### What to test specifically

- Service restart functionality
- Accessibility service re-enabling
- Notification listener re-enabling
- App relaunch behavior (all idle modes)
- Audit log accuracy
- Settings persistence
- Boot receiver functionality

## Submitting Changes

### Before creating a PR

1. **Test thoroughly** on a physical device
2. **Format your code**:
   ```bash
   flutter format .
   ```
3. **Run static analysis**:
   ```bash
   flutter analyze
   ```
4. **Update documentation** if needed
5. **Commit with clear messages**:
   ```bash
   git commit -m "Add feature: service restart retry logic"
   ```

### Commit message guidelines

Good commit messages:
- Use present tense ("Add feature" not "Added feature")
- Be concise but descriptive
- Reference issues when applicable: "Fix #123: Service restart timeout"

Examples:
```
Add export/import configuration feature
Fix crash when Shizuku disconnects mid-operation
Improve audit log performance for large datasets
Update README with troubleshooting section
Refactor service monitoring logic for clarity
```

### Creating the pull request

1. **Push to your fork**:
   ```bash
   git push origin feature/my-new-feature
   ```
2. **Open a PR** on GitHub
3. **Fill out the PR template** completely:
   - Describe what changed and why
   - Link related issues
   - Add screenshots for UI changes
   - List testing performed
   - Note any breaking changes

### PR review process

- Maintainers will review your PR
- Be responsive to feedback
- Make requested changes in new commits
- Once approved, your PR will be merged!

## Reporting Bugs

### Before reporting

1. **Search existing issues** — your bug might already be reported
2. **Update to latest version** — check if it's already fixed
3. **Verify it's reproducible** — try to reproduce consistently

### Bug report template

Include:

1. **Description** — clear summary of the bug
2. **Steps to reproduce**:
   - Step 1
   - Step 2
   - Step 3
3. **Expected behavior** — what should happen
4. **Actual behavior** — what actually happens
5. **Environment**:
   - Service Keeper version
   - Android version
   - Device model
   - Shizuku version
6. **Logs/screenshots** — if applicable
7. **Additional context** — anything else relevant

## Feature Requests

### Suggesting features

1. **Check existing issues** — it might already be suggested
2. **Explain the use case** — why is this needed?
3. **Describe the solution** — how should it work?
4. **Consider alternatives** — are there other approaches?
5. **Additional context** — mockups, examples, etc.

### Feature request template

```markdown
**Problem/Use Case**
Describe the problem or use case this feature would solve.

**Proposed Solution**
Describe how you envision this feature working.

**Alternatives Considered**
What other approaches could solve this problem?

**Additional Context**
Any mockups, examples, or relevant information.
```

## Questions?

- Check the [FAQ](README.md#-faq) in the README
- Search [existing issues](https://github.com/shaunkleyn/Service-Keeper/issues)
- Open a new issue with the `question` label

---

Thank you for contributing to Service Keeper! 🎉
