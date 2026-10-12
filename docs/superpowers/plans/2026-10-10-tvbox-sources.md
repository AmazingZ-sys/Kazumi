# TVBox Sources Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for bounded implementation tasks and requesting-code-review for final review.

**Goal:** Import compatible TVBox sources into drama search and persist editable source configurations.

**Architecture:** A TVBox protocol adapter maps sites into Plugin and handles XML/JSON search, chapters and remote playback. PluginsController owns configuration lifecycle and atomically persists configurations with rules. A dedicated settings page manages configurations.

**Tech Stack:** Flutter/Dart, existing Dio, MobX and JSON file storage.

## Task 1 — Protocol adapter
- [ ] Write protocol fixture tests; run and observe missing implementation.
- [ ] Add immutable TvBoxSite and TvBoxImportResult, import parser and API strategy. Plugin carries optional tvBoxSite and subscriptionId.
- [ ] Map search/chapters into existing trace and road models. Handle type 4 playback lazily and propagate headers.
- [ ] Run protocol tests and existing rule engine tests.

## Task 2 — Persistence and lifecycle
- [ ] Write tests for restart recovery, edits, deletion, update failures and name isolation.
- [ ] Add TvBoxSubscription model; PluginsController.tvBoxSubscriptions plus previewTvBoxConfig, saveTvBoxConfig, refreshTvBoxConfig, removeTvBoxConfig methods.
- [ ] Persist one atomic versioned envelope when configurations exist, accept legacy arrays, snapshot/rollback both lists, maintain excluded site keys and local overrides on refresh.
- [ ] Run persistence tests and existing plugin migration tests.

## Task 3 — Management UI
- [ ] Add configuration list and editor with URL/JSON input, import preview, diagnostics, refresh and delete actions.
- [ ] Add navigation from rule management and drama search; reuse existing Material components.
- [ ] Verify add/edit/delete with a widget test using injected config loader/writer.

## Task 4 — Integration and verification
- [ ] Review protocol, persistence, playback and route integration against spec.
- [ ] Run flutter test --no-pub --reporter expanded and flutter analyze --no-pub --no-fatal-infos --fatal-warnings.
- [ ] Build macOS release, document supported formats, limitations and usage.
- [ ] Request independent review and fix actionable findings. Leave changes locally reviewable.
