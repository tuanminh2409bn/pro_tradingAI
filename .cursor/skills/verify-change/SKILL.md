---
name: verify-change
description: Review and verify Flutter changes before commit or release without editing unless fixes are requested.
paths:
  - "**/*.dart"
  - "pubspec.yaml"
---

# Verify a Flutter Change

Default to read-only verification.

1. Inspect repository instructions, status, full relevant diff, manifest/lockfile changes, generated files, and platform configuration.
2. Map changed behavior to unit/widget/integration coverage and check lifecycle, state, null safety, accessibility, localization, and platform boundaries.
3. Format-check changed Dart files; run `flutter analyze`, focused tests, broader relevant `flutter test`, and required target builds.
4. Inspect the produced artifact or runtime result when the requested claim depends on it.
5. Report findings by severity and list passed, failed, skipped, and unavailable checks separately.
