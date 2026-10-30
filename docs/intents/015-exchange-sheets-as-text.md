---
id: "015"
name: exchange-sheets-as-text
status: draft
created: 2026-10-29
updated: 2026-10-29
---

# Intent: Export and import sheets as text

## Problem

The author wants sheet export and import. The specific exchange or migration problem is not stated.

## Proposed outcome

Users can export expressions and results as text and import that text while preserving expressions and assignments.

## Affected users and systems

The author and other Mac users with the same use cases; Nume sheets and text files.

## Constraints

- Export writes a `.txt` file with one `expression = result` line per expression.
- Import removes the last `= result` from each line and preserves assignment operators: `price = $8 times 3 = $24` becomes `price = $8 times 3`.

## Open questions

None.
