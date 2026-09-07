---
name: fix-bug
description: Reproduce, diagnose, and fix a Flutter bug with a regression test and minimal architecture-preserving changes.
paths:
  - "**/*.dart"
  - "pubspec.yaml"
---

# Fix a Flutter Bug

1. Reproduce the problem or create the smallest failing test; capture platform, lifecycle, and state conditions.
2. Trace widget, state, service, and data boundaries to identify the root cause rather than the visible symptom.
3. Confirm the hypothesis, add a regression test when practical, and apply the narrowest fix.
4. Preserve null safety, mounted/cancellation handling, state ownership, and generated-code conventions.
5. Run the reproduction, formatting, `flutter analyze`, focused tests, relevant broader tests, and any platform build required by the bug.
6. Report root cause, exact fix, evidence, and residual platform/device risk.
