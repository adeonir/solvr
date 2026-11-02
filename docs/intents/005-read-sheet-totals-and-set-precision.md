---
id: "005"
name: read-sheet-totals-and-set-precision
status: done
created: 2026-10-29
updated: 2026-11-01
---

# Intent: Read sheet totals and set result precision

## Problem

The author uses saved sheets for budgets and expense splits, which involve multiple expression results.

## Proposed outcome

Users can read a sheet total and choose the number of decimal places for individual results and the total.

## Affected users and systems

The author and other Mac users with the same use cases; sheets and expression results.

## Constraints

- The total sums expression results and leaves out results it cannot add, such as a temperature among money results.
- A sheet with a date among its results shows no total.
- Precision sets decimal places for every result and the total, from 1 to 10. The precision of a cryptocurrency result, and of a total in a cryptocurrency, is set apart, from 5 to 15, with a default of 10.

## Open questions

None.
