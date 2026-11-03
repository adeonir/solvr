---
name: 006-use-foundation-decimal-for-numeric-values
status: accepted
date: 2026-10-30
updated: 2026-10-30
sources: []
---

# ADR-006: Use Foundation Decimal for numeric values

## Context

The calculation language needs exact decimal arithmetic, so that `0,1 + 0,2` is exactly `0,3`. Approximate values keep at least 34 significant decimal digits, and exact ties round away from zero. Foundation `Decimal` holds 38 significant digits. In a test on the target toolchain, `1e127` and `1e-128` were representable, while `1e128` and `1e-150` were not. `Decimal` has no `sqrt`, `sin`, or `log`, and its `pow` takes an integer exponent.

## Decision

We will use the Foundation `Decimal` type for numeric values.

## Alternatives Considered

- **`Double`:** It holds about 15 to 17 significant digits and does not represent `0,1` exactly.
- **A C decimal library wrapped in Swift:** It adds a dependency outside Swift.
- **A decimal type written for Solvr:** It requires writing and testing the arithmetic itself.

## Consequences

- The supported magnitude range is `10^-127` through `10^127`, with either sign and zero. A result beyond it is a numeric-range error, and an overflow that `Decimal` reports as `NaN` is shown as that error.
- The 38 digits of `Decimal` cover the 34 significant digits that approximate values keep.
- The `plain` rounding mode of `Decimal` resolves exact ties away from zero.
- `sqrt`, `sin`, `log`, and `fact` are code in Solvr, calculated on `Decimal` without passing through `Double`. Solvr's tests check their results against the error bounds of the calculation language.

## References

- [ADR-004: Use Swift for the application](004-use-swift-for-the-application.md)
- [Intent 001: Calculate everyday expressions correctly](../intents/001-calculate-everyday-expressions.md)
- [NSDecimalNumber](https://developer.apple.com/documentation/foundation/nsdecimalnumber)
