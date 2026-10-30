---
name: prd
created: 2026-10-26
updated: 2026-10-30
status: approved
sources: []
---

# PRD: Nume

## 1. Problem

The text calculators the author uses today do not keep sheets between sessions, cannot group sheets, cannot sync sheets, and give wrong results for some calculations. The evidence is anecdotal: the author's own daily use.

## 2. Audience

- **Primary user, the author:** a developer who uses a text calculator on the Mac every day. Main use cases: quick calculations during work, such as unit conversions, currency conversions, `px` to `em`, and time zones; and saved sheets for calculations that come back, such as a budget or a split of expenses.
- **Other Mac users who find the project:** people with the same use cases as the primary user.

## 3. Goals & Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Use Nume for daily calculations | The author uses Nume for daily calculations | The author performs daily calculations in Nume |

Primary metric: the author uses Nume for daily calculations.

## 4. Scope

### Must Have

- FR-1 The calculation language covers the calculations of a daily use of Nume, as the use cases of section 2 state: quick calculations during work, such as unit conversions, currency conversions, `px` to `em`, and time zones; and saved sheets, such as a budget or a split of expenses.
- FR-2 The calculation language reads these expressions as follows:
  - `and` adds. `&` is bitwise AND. `|` and `or` are bitwise OR.
  - `min` followed by parentheses is the minimum function, as in `min(3; 7)`. `min` after a number is the minute unit, as in `15 min`.
  - `KB` is the kilobyte of 1000 bytes, the same SI rule as `MB`, `GB`, and `TB`. `KiB`, `MiB`, and the other binary units are 1024-based.
  - `F` is Fahrenheit and `C` is Celsius, so `100 F in C` converts 100 degrees Fahrenheit to degrees Celsius.
  - `log` without a base uses base 10, so `log 100` gives `2`. `log` with a base uses that base, so `log 2 (8)` gives `3`.
  - A time zone conversion to a city gives the time in that city. `PST` is the Pacific time zone, including daylight saving time, so `11 am PST in London` gives `18:00` on 26 October 2026.
- FR-3 The calculation language adds these calculations: the `max` function and the `min` function; city abbreviations, as in `5pm ldn in sf`; `days until`, as in `days until 31 Mar`; and `to timespan`, as in `145 mins to timespan`.
- FR-4 A number written with a currency uses the number format of that currency, so `$99.99` is 99.99 US dollars. A number written without a currency uses the regional number format of the system, so with the Brazilian format `1.500` is 1500 and `1,500` is 1.5. A result with a currency uses the number format of that currency, as in `$89.99`.
- FR-37 Settings defines one shared pixel base for `rem` and `em` conversions, with a default of 16 px:
  - Without an explicit base in the expression, both units use the value from Settings. With the default base, `1 rem` displays `16px` and `16px in em` returns `1em`.
  - With the base set to 20 px, `1 rem in px` returns `20px` and `16px in em` returns `0,8em` with Brazilian number formatting.
  - An explicit base in an `em` conversion represents the element's font size. With Brazilian number formatting, `16px in em at 20px` returns `0,8em`, using 20 px as the base for that expression only.
  - An expression's explicit base leaves the shared Settings value and other expressions unchanged.
- FR-36 The total of a sheet sums the results of its expressions. The total leaves out the results it cannot add, such as a temperature among money results. A sheet with a date among its results shows no total.
- FR-38 An expression that cannot be calculated shows a short message that names the cause in place of its result, on the same line as the expression, in the error color of the theme. The other expressions of the sheet keep their results. An expression that depends on an invalid expression shows that it depends on an error. An incomplete expression shows no message.
- FR-5 Precision sets the number of decimal places of each result and of the total, from 1 to 10.
- FR-6 The app converts currencies and cryptocurrencies with exchange rates that update over the internet.
- FR-7 The app converts time zones by abbreviation and by city name.
- FR-35 A sheet can be created.
- FR-8 The app saves each sheet locally and automatically after each change, with no save action. Sheets can be edited without an internet connection.
- FR-26 Each sheet has a title, and the title can be renamed.
- FR-27 A sheet can be deleted. Only the first deletion of a sheet asks for confirmation.
- FR-11 The sheet font has a family, a size, and a line height:
  - The family is any monospaced font installed on the Mac.
  - The size is in px, with a default of 13.
  - The line height has a default of 2.
  - An empty size field or an empty line height field returns to its default.
- FR-12 The mode is Light, Dark, or Auto. Auto follows the appearance of macOS.
- FR-33 The default theme uses the Apple colors and has a light version and a dark version. The theme colors the whole window: the sheet, the bars, and the sheet list.
- FR-9 The app shows either in the Dock or in the menu bar. The Show in Menu Bar option moves the app from the Dock to the menu bar, and turning the option off moves it back to the Dock. The option is off by default. The menu of the menu bar icon opens the window, opens Settings, and quits the app.
- FR-13 The app is distributed by direct download and by Homebrew. App Store distribution is TBD. The app updates itself automatically in every case.

### Should Have

- FR-28 A sheet can be moved to a folder, and out of its folder to no folder.
- FR-14 Folders group sheets.
- FR-30 A folder can be deleted. Deleting a folder deletes its sheets. Only the first deletion of a folder asks for confirmation.
- FR-34 More themes join the default theme (FR-33):
  - The themes are catppuccin with all its variants, rose-pine with all its variants, tokyo-night with all its variants, Dracula and Alucard, one-dark and One Light, and Monokai dark and Monokai light. Each theme is light or dark and has an error color.
  - The theme list shows only the themes that match the current mode. The default theme is first in each list.
  - In Auto, when macOS changes between light and dark, Nume applies the first theme in the list for the new mode.
- FR-18 A global hotkey opens Nume from any app. The user configures the hotkey in Settings. No global hotkey is configured by default.
- FR-19 Launch at Login opens Nume when the user logs in to macOS.
- FR-22 Telemetry sends crash reports, errors, and usage data. Telemetry is on by default. The Telemetry option in Settings turns all telemetry off. Telemetry follows NFR-1.
- FR-39 The shortcut Cmd + / comments the line with the cursor by adding `// ` at its start, and uncomments it when it already starts with `//`. With several lines selected, the shortcut comments all of them, or uncomments all of them when every selected line is already a comment.

### Could Have

- FR-25 Recently Deleted holds every deleted sheet for 30 days, and then the app removes the sheet permanently. A single Recently Deleted holds the deleted sheets of all folders. Before the 30 days end, a sheet in Recently Deleted can be recovered or deleted permanently. A recovered sheet goes back to the folder it was in before it was deleted. When that folder no longer exists, the recovered sheet belongs to no folder.
- FR-29 A sheet can be duplicated.
- FR-32 Search finds sheets by title and by text. The results leave out the sheets in Recently Deleted.
- FR-31 A folder can be renamed.
- FR-15 iCloud syncs sheets and folders. Sync resumes when an internet connection returns. When the same sheet is edited on two devices, changes are compared against the last synced version:
  - Changes to different parts are merged automatically. Identical changes are kept once.
  - When devices make different changes to the same expression, including deleting it on one device and editing it on another, the user chooses the final content. Both versions are preserved until the conflict is resolved.
  - Nume recalculates the sheet after merging changes.
- FR-16 Export writes a `.txt` file with one `expression = result` line for each expression. Import reads the same format: it removes the last `= result` from each line and keeps the `=` of an assignment, so `price = $8 times 3 = $24` comes back as `price = $8 times 3`.
- FR-20 A URL scheme opens a sheet, creates a sheet with a given text, and adds a given text to the end of a sheet.
- FR-21 A Raycast integration searches sheets and opens a sheet in Nume.
- FR-10 Always on Top keeps the window above other windows.

### Won't Have

- FR-23 Built-in demo sheets — not a priority now.
- FR-24 Send Feedback — not a priority now.

### Out of Scope

- Alfred integration.
- Extensions.
- Dynamic font size.

## 5. Non-Functional Requirements

| ID | Requirement | Target |
|----|------------|--------|
| NFR-1 | Telemetry carries no personal data. Sheet text and expressions go with telemetry only in anonymized form: each real name and each real number is replaced by a false value of the same type and format, and the expression can still be calculated, so `salário = R$ 8.000 - 4%` becomes `var1 = R$ 3.517 - 7%`. | Every telemetry event |
| NFR-2 | Without an internet connection, currency conversion and time zone conversion by city name use the cached data. | Each conversion that has cached data |
| NFR-3 | Nume runs on the supported macOS versions. | macOS 15 or later |

## 6. Phases

| Phase | Delivery | Criterion to advance |
|-------|----------|----------------------|
| MVP | FR-1 to FR-9, FR-11 to FR-13, FR-18, FR-19, FR-26, FR-27, FR-29, and FR-33 to FR-39 | The author uses Nume for daily calculations |
| Next | FR-10, FR-14, FR-15, FR-16, FR-20, FR-21, FR-22, FR-25, FR-28, and FR-30 to FR-32 | Not applicable: each item ships when the roadmap reaches it |

## 7. Assumptions & Risks

- **Risk:** Currency conversion and time zone conversion by city name depend on an external data source. If the source stops working or changes, these conversions stop. — The cache (NFR-2) keeps conversions working with the last data, and telemetry (FR-22) shows failures. Telemetry ships after the MVP, so during the MVP only the cache covers this risk.

## 8. Open Questions

- App Store distribution: TBD.

## 9. References

- Product positioning: [PRODUCT.md](../../PRODUCT.md)
- Hi-fi mockup: [Nume main window](https://claude.ai/artifact/FhzDwfzVV31GPTf6LKWWe9)
