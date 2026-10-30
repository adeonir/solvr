---
id: "007"
name: choose-window-appearance
status: draft
created: 2026-10-29
updated: 2026-10-30
---

# Intent: Choose the window appearance

## Problem

The author wants light and dark appearances and selectable themes. A specific problem with existing appearances is not stated.

## Proposed outcome

Users can choose a mode and a theme for the whole Nume window, including following macOS appearance automatically.

## Affected users and systems

The author and other Mac users with the same use cases; Nume and macOS appearance.

## Constraints

- Modes are Light, Dark, and Auto. Auto follows macOS.
- The default theme uses Apple colors and has light and dark versions. Themes color the sheet, bars, and sheet list.
- Additional themes are catppuccin with all variants, rose-pine with all variants, tokyo-night with all variants, Dracula and Alucard, one-dark and One Light, and Monokai dark and Monokai light.
- Each theme is light or dark. The list shows only themes matching the current mode, with the default theme first.
- In Auto, a macOS appearance change applies the first theme in the list for the new mode.
- Each theme has an error color.

## Open questions

None.
