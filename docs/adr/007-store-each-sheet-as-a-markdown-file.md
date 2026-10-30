---
name: 007-store-each-sheet-as-a-markdown-file
status: proposed
date: 2026-10-30
updated: 2026-10-30
sources: []
---

# ADR-007: Store each sheet as a Markdown file

## Context

Nume saves each sheet locally after each change, and a sheet can be edited without an internet connection. A sheet is text in a format close to Markdown, with a title, a creation time, and a last-edit time. Two later features read sheets in other ways: iCloud sync of sheets, and export and import of sheets as text. Nume runs on macOS 15 or later.

## Decision

We will store each sheet as one Markdown file in the Application Support folder of Nume. The frontmatter of the file holds the title, the creation time, and the last-edit time. The file name is the UUID of the sheet.

## Alternatives Considered

- **SwiftData:** It keeps sheet text inside a managed database, so a sheet is not a file and exchanging sheets as text needs a separate export step.
- **SQLite:** It has the same property as SwiftData and adds code for the schema and the access to it.

## Consequences

- A sheet is readable and editable outside Nume, and each sheet is one unit for sync and for export.
- Renaming a sheet changes the frontmatter only. The file name stays the same.
- The sheet list reads the frontmatter of every file. A file with no valid frontmatter does not appear in the list.
- Search over sheet text reads the files, because there is no query engine.
- Each save replaces the whole file.

## References

- [PRD: Nume](../product/PRD.md), FR-8, FR-15, FR-16, FR-26
- [Intent 002: Keep and reuse saved sheets](../intents/002-keep-and-reuse-saved-sheets.md)
- [Intent 014: Keep sheets and folders synced](../intents/014-sync-sheets-and-folders.md)
- [Intent 015: Exchange sheets as text](../intents/015-exchange-sheets-as-text.md)
