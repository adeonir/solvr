---
id: "003"
name: convert-currencies-and-cryptocurrencies
status: done
created: 2026-10-29
updated: 2026-11-01
---

# Intent: Convert currencies and cryptocurrencies

## Problem

The author needs currency conversions during daily work.

## Proposed outcome

Users can convert currencies and cryptocurrencies using exchange rates that update over the internet and can continue converting offline when cached data exists.

## Affected users and systems

The author and other Mac users with the same use cases; the external exchange rate source.

## Constraints

- Exchange rates update over the internet. Without an internet connection, conversions use cached data when available.
- The external data source can stop working or change. Cached data preserves conversions using the last available data.

## Open questions

None.
