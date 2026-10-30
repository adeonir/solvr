---
name: 003-use-30-days-for-months-without-a-reference-date
status: proposed
date: 2026-10-30
updated: 2026-10-30
sources: []
---

# ADR-003: Use 30 days for months without a reference date

## Context

The calculation language supports dates and durations. Calendar months have different lengths, while an expression such as `1 month in days` supplies no reference date from which to determine a calendar interval.

## Decision

We will convert a month to 30 days when the duration has no reference date.

## Alternatives Considered

- **Require a reference date for every month-to-day conversion:** This would prevent a standalone duration such as `1 month in days` from producing a result.

## Consequences

- `1 month in days` returns `30 days`, independently of the current date.
- This conversion is a fixed duration convention. It does not measure every calendar month correctly.
- Operations on actual dates continue to use calendar months. For example, adding one month to 31 January reaches the last valid day of February, rather than adding a fixed 30 days.
- The evaluator must distinguish a duration without a reference date from a calendar operation on a date.

## References

- [Intent 001: Calculate everyday expressions correctly](../intents/001-calculate-everyday-expressions.md)
