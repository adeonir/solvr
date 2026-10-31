---
id: "014"
name: sync-sheets-and-folders
status: accepted
created: 2026-10-29
updated: 2026-10-29
---

# Intent: Keep sheets and folders synced

## Problem

The calculators the author uses cannot sync sheets. The evidence comes from personal daily use.

## Proposed outcome

Users have their sheets and folders synced through iCloud.

## Affected users and systems

The author and other Mac users with the same use cases; sheets, folders, and iCloud.

## Constraints

- Sync uses iCloud and covers both sheets and folders.
- Sheets are saved locally and can be edited without an internet connection. Sync resumes when the connection returns.
- Changes from two devices are compared against the last synced version of the sheet. Changes to different parts are merged automatically; identical changes are kept once.
- When devices make different changes to the same expression, including deleting it on one device and editing it on another, users choose the final content. Both versions are preserved until the conflict is resolved.
- The app recalculates the sheet after merging changes.

## Open questions

None.
