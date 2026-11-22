# Intent: Separate the app and core in Xcode

- Created: 2026-11-22
- Updated: 2026-11-22

## Problem

The Solvr app and core are split between an Xcode project and a Swift package, and the Xcode project has no separate test areas for the app and core.

## Proposed outcome

The app and core have separate code and test areas in the Xcode project. The project supports development with Xcode 27 or later and the app runs on macOS 26 or later.

## Affected users and systems

Solvr developers; the Solvr app project and its build and test workflows.

## Constraints

- The app runs on macOS 26 or later.
- The project uses Xcode 27 or later.

## Out of scope

None.

## Open questions

None.
