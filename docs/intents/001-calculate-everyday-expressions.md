---
id: "001"
name: calculate-everyday-expressions
status: done
created: 2026-10-29
updated: 2026-10-30
---

# Intent: Calculate everyday expressions correctly

## Problem

The author uses a text calculator every day for quick calculations during work and recurring calculations such as budgets and expense splits. Some calculations in the calculators the author uses give wrong results. This evidence comes from personal daily use.

## Proposed outcome

Users can write expressions, variables, and comments in a sheet and get correct results for daily calculations, including unit conversions, px to em, minimum and maximum values, dates, and durations.

## Affected users and systems

The author and other Mac users with the same use cases; macOS regional settings.

## Constraints

- The calculation language covers daily use.
- `and` adds; `&` is bitwise AND; `|` and `or` are bitwise OR.
- `min(3; 7)` uses the minimum function; `15 min` uses the minute unit. Both `min` and `max` functions are supported.
- `KB`, `MB`, `GB`, and `TB` use the SI base of 1000; `KiB`, `MiB`, and other binary units use base 1024.
- `F` means Fahrenheit and `C` means Celsius; `100 F in C` converts between those temperature units.
- `log 100` uses base 10 and gives `2`; `log 2 (8)` uses the given base and gives `3`.
- Numbers without a currency use the system regional number format: in Brazilian format, `1.500` is 1500 and `1,500` is 1.5.
- The language supports `days until 31 Mar` and `145 mins to timespan`.
- Settings holds one shared pixel base for `rem` and `em`, 16 px by default. `16px in em at 20px` uses 20 px for that expression only.
- An expression that cannot be calculated shows a short message that names the cause in place of its result. The other expressions keep their results.
- The shortcut Cmd + / comments and uncomments the line with the cursor or the selected lines.

## Open questions

None.
