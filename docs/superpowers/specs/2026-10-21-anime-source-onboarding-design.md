# Anime source onboarding repair

## Problem

Fresh installations load the bundled Olevod TV rule before startup decides whether to open onboarding. The existing empty-list check therefore skips onboarding even though no anime sources are installed. Development installations retain previously installed anime rules, hiding this problem.

## Authorized behavior

- Open onboarding when its completion flag is false and no anime source is installed, including upgrades affected by the previous skipped onboarding.
- Preserve the legacy shortcut for users with installed anime rules and honor an explicitly completed onboarding flow even when the user chose to skip anime sources.
- Treat a normalized `anime` rule type as an anime source; TV and TVBox rules do not satisfy that requirement.
- Before completing onboarding without an anime source, explain the missing anime sources and let the user return to installation or explicitly continue.
- Keep installed rules and subscriptions intact. Anime rules remain individually installable from the existing catalog.

## Implementation

Share the anime-source and startup decisions in a small onboarding policy module. Use the same anime-source predicate for the final skip confirmation. No new settings or persisted schema are needed.

## Validation and release

Cover fresh bundled-only installs, affected persisted installs, existing anime users, normalized rule types, and completed onboarding. Widget tests exercise the skip dialog and its choices. Run the Flutter tests, analyzer, and packaging tests, then review the diff independently. Merge the repair branch into main and publish version `2.3.13+20313` through the existing `2.3.13` tag workflow, verifying all release attachments.
