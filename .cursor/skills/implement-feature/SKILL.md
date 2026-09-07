---
name: implement-feature
description: Implement a Flutter feature using the repository's architecture, pinned SDK, focused tests, and analyzer evidence.
paths:
  - "**/*.dart"
  - "pubspec.yaml"
---

# Implement a Flutter Feature

1. Inspect acceptance criteria, repository instructions, `pubspec.yaml`, lockfile, analyzer config, affected widgets/services, and existing tests.
2. Follow the existing state, navigation, DI, data, localization, and design-system patterns. Avoid a new dependency unless clearly necessary.
3. Implement the smallest coherent behavior with sound null safety and explicit async/error handling.
4. Add focused unit, widget, or integration coverage at the lowest useful level.
5. Format changed Dart files; run `flutter analyze`, focused tests, then relevant broader tests and build.
6. Inspect the diff and report behavior, checks, assumptions, and unverified device/platform conditions.
