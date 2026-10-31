---
id: "008"
name: access-the-app-during-work
status: draft
created: 2026-10-29
updated: 2026-10-29
---

# Intent: Access the app during work

## Problem

The author uses a text calculator for quick calculations during work and wants control over how the app is opened and accessed.

## Proposed outcome

Users can access the app through the Dock or menu bar, open it from any app with a global hotkey, and have it open at login.

## Affected users and systems

The author and other Mac users with the same use cases; the macOS Dock, menu bar, global hotkeys, and login.

## Constraints

- The app appears either in the Dock or in the menu bar. Show in Menu Bar is off by default.
- Enabling Show in Menu Bar moves the app from the Dock to the menu bar; disabling it moves the app back.
- The menu bar icon menu opens the window, opens Settings, and quits the app.
- A global hotkey opens the app from any other app. Launch at Login opens the app when the user logs in to macOS.
- Users configure the global hotkey in Settings. No global hotkey is configured by default.

## Open questions

None.
