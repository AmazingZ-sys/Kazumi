# Fork Releases Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement tasks, then perform independent spec and quality review.

**Goal:** Publish the first four-platform fork release and make in-app updates follow this fork.

**Architecture:** Reuse scripts/package.py for native packaging. GitHub Actions validates source before producing four platform artifacts, then publishes version-tag builds. Release metadata and download choices come only from the fork's GitHub Releases API.

**Tech Stack:** Flutter/Dart, GitHub Actions, Python packaging, Gradle Android signing.

## Task 1: Fork update channel
- [x] Add failing tests for fork metadata requests, no-release 404, direct GitHub URLs, absent MSIX/mirror selection, and current/new version checks.
- [x] Configure `ApiEndpoints` with fork repository/release API and release web URLs; remove updater dependency on upstream update mirror.
- [x] Choose available platform assets and download sources; keep SHA256 checks and iOS external download behavior.
- [x] Run focused tests, then Flutter analyzer/tests.

## Task 2: Four-platform build/release workflow
- [x] Replace release.yaml with fork branch-push, version-tag, and manual triggers; remove upstream SignPath/MSIX/Linux release dependencies.
- [x] Run Flutter tests/analyzer and Python packaging tests before four independent package builds.
- [x] Use scripts/package.py to produce Android, IPA, DMG, and Windows ZIP. Upload artifacts with failure-on-missing and stable platform names.
- [x] Publish tagged builds only after all four succeed, including release notes, checksums, and explicit unsigned Windows/iOS/macOS information.
- [x] Validate version tag against pubspec version and validate workflow YAML/actionlint.

## Task 3: Stable Android signing and release material
- [x] Add Gradle release signing via repository secret environment variables, keeping local development fallback.
- [x] Generate one private fork keystore outside Git and back it up locally; configure repository Actions secrets without printing secrets.
- [x] Set pubspec version to `2.3.10+20310`; update fork download/signing documentation and README links/roles.
- [x] Review staged diff and run final tests/analyzer.

## Task 4: Publish and verify
- [ ] Commit and push tested source to feat/drama-olevod. Ensure fork Actions is enabled and push numeric tag 2.3.10.
- [ ] Follow build jobs, fix actual failures, and publish only successful artifacts; do not rewrite existing published tags.
- [ ] Verify release assets and update API metadata/digests. Keep users informed while cloud builds run.
