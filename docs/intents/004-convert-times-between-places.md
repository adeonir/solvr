---
id: "004"
name: convert-times-between-places
status: draft
created: 2026-10-29
updated: 2026-10-29
---

# Intent: Convert times between places

## Problem

The author needs time zone conversions during daily work.

## Proposed outcome

Users can convert times by time zone abbreviation, city name, and city abbreviation, including `5pm ldn in sf`.

## Affected users and systems

The author and other Mac users with the same use cases; Nume and the external city time zone data source.

## Constraints

- A conversion to a city gives the time in that city.
- `PST` means the Pacific time zone, including daylight saving time. `11 am PST in London` gives `18:00` on 26 October 2026.
- Without an internet connection, conversions by city name use cached data when available. The external source can stop working or change.

## Open questions

None.
