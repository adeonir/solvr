---
name: 002-match-the-longest-defined-variable-name
status: proposed
date: 2026-10-30
updated: 2026-10-30
sources: []
---

# ADR-002: Match the longest defined variable name

## Context

Variable names can contain spaces. A sheet can define names with a shared prefix, such as `despesa` and `despesa mensal`. The language needs to distinguish a complete variable reference from a shorter name followed by other text.

## Decision

We will recognize the longest complete variable name defined before the reference.

## Alternatives Considered

- **Require quotes around names containing spaces:** This would add quoting syntax to references that can be resolved from complete names already defined in the sheet.

## Consequences

- When both `despesa` and `despesa mensal` are defined, `despesa mensal * 2` uses `despesa mensal`.
- Names containing spaces can be referenced without quotes.
- Parsing a reference depends on the variable names visible at that point in the sheet. Splitting text at spaces alone is insufficient.
- Adding, removing, or renaming a preceding definition can change how subsequent text is recognized.

## References

- [Intent 001: Calculate everyday expressions correctly](../intents/001-calculate-everyday-expressions.md)
- [ADR-001: Resolve variables from preceding definitions](001-resolve-variables-from-preceding-definitions.md)
