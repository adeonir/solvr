# AGENTS.md

Facts about SwiftUI on macOS 15 that the app code depends on.

## Grouped Form in the Settings window

- Apply `foregroundStyle` and `listRowSeparatorTint` to each row, not to the Form. A `foregroundStyle` on the Form also colors the row separators, and a `listRowSeparatorTint` takes effect only when the row's style is set on the row.
- `.listRowSeparator(.hidden)` has no effect in a grouped Form.
- A `TextField` with the plain style takes a click only on its text. To make the whole field start editing, give its background a tap gesture that sets the field's focus, and add `.pointerStyle(.horizontalText)`.

## Appearance

- Set the app's appearance through `NSApp.appearance`. `preferredColorScheme(nil)` does not return a window to the macOS appearance until the window is activated.
