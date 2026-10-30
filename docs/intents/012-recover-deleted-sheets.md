---
id: "012"
name: recover-deleted-sheets
status: draft
created: 2026-10-29
updated: 2026-10-29
---

# Intent: Recover deleted sheets

## Problem

Users can delete sheets and folders. The reason for offering recovery beyond these deletion actions is not stated.

## Proposed outcome

Users can recover sheets from Recently Deleted before automatic permanent removal, or remove those sheets permanently themselves.

## Affected users and systems

The author and other Mac users with the same use cases; Nume sheets, folders, and Recently Deleted.

## Constraints

- One Recently Deleted holds deleted sheets from all folders for 30 days, after which Nume removes the sheets permanently.
- Before expiry, users can recover sheets or delete them permanently.
- Recovery restores the previous folder when that folder still exists; otherwise the sheet belongs to no folder.

## Open questions

None.
