---
id: "007"
name: choose-window-appearance
status: accepted
created: 2026-10-29
updated: 2026-11-21
---

# Intent: Choose the window appearance

## Problem

The author wants light and dark appearances and selectable themes. A specific problem with existing appearances is not stated.

## Proposed outcome

Users can choose a mode and a theme for the whole window, including following macOS appearance automatically.

## Affected users and systems

The author and other Mac users with the same use cases; macOS appearance.

## Constraints

- Modes are Light, Dark, and Auto. Auto follows macOS.
- The default theme uses Apple colors and has light and dark versions. Themes color the whole window.
- Additional themes are catppuccin with all variants, rose-pine with all variants, tokyo-night with all variants, Dracula and Alucard, one-dark and One Light, and Monokai dark and Monokai light.
- Each theme is light or dark. The list shows only themes matching the current mode, with the default theme first.
- Solvr keeps one theme for the light mode and one for the dark mode. Each change between light and dark, by hand or in Auto, applies the theme kept for the new mode, or the default theme when none was chosen.
- Each theme has an error color.

## Open questions

None.
