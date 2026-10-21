# Anime Source Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show anime-source onboarding on fresh or previously affected installations while preserving existing user choices, then publish 2.3.13.

**Architecture:** Put the shared anime-source predicate and startup decision in `lib/pages/onboarding/onboarding_policy.dart`. Call them from startup and onboarding completion. Keep all existing rules and the completion setting.

**Tech Stack:** Flutter/Dart, flutter_test, GitHub Actions, existing Python packaging tools.

---

### Task 1: Regressions and onboarding repair

**Files:**
- Create: `lib/pages/onboarding/onboarding_policy.dart`
- Modify: `lib/pages/init_page.dart`
- Modify: `lib/pages/onboarding/onboarding_page.dart`
- Test: `test/onboarding_policy_test.dart`
- Test: `test/onboarding_page_test.dart`

- [ ] Write startup tests for no rules, fresh bundled-only rules, persisted bundled-only rules, legacy anime users, normalized anime types, and completed onboarding.
- [ ] Write widget tests for the TV-only skip warning, returning to rule installation, and explicitly completing without anime rules. Observe the original TV-only completion failure before changing the page.
- [ ] Implement `hasAnimeSources(Iterable<Plugin> plugins)` with `plugin.type.trim().toLowerCase() == 'anime'`.
- [ ] Implement `shouldShowOnboarding({required bool completed, required Iterable<Plugin> plugins})` with `!completed && !hasAnimeSources(plugins)`.
- [ ] Use `shouldShowOnboarding` for startup routing and `!hasAnimeSources` for the final skip dialog. Change its title to `暂不添加番剧来源？` and explain that anime sources can be installed through rule management.
- [ ] Run `flutter test --no-pub test/onboarding_policy_test.dart test/onboarding_page_test.dart test/bundled_rule_migration_test.dart --reporter expanded`; expect all cases to pass.

### Task 2: Verify and prepare release

**Files:**
- Modify: `pubspec.yaml`
- Create: `docs/releases/2.3.13.md`

- [ ] Set `version: 2.3.13+20313` and write release notes describing the startup repair and upgrade behavior.
- [ ] Run `flutter test --no-pub`, `flutter analyze --no-pub --no-fatal-infos --fatal-warnings`, and `python3 -m unittest discover -s scripts/tests -v`; require successful exits.
- [ ] Run `python3 scripts/release_metadata.py version --tag 2.3.13`; expect `2.3.13+20313`.
- [ ] Obtain an independent review of the completed diff, address actionable findings, and commit the verified change.

### Task 3: Merge and publish

- [ ] Push the repair branch, merge it into main, and push main without force.
- [ ] Create and push the new `2.3.13` tag at the verified merged commit.
- [ ] Wait for the tag workflow to finish and verify the published APK, IPA, DMG, Windows installer/ZIP, and SHA256SUMS. Report the release URL and any remaining platform limitation accurately.
