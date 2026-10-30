---
name: 001-resolve-variables-from-preceding-definitions
status: proposed
date: 2026-10-30
updated: 2026-10-30
sources: []
---

# ADR-001: Resolve variables from preceding definitions

## Context

A sheet contains expressions and variable assignments in text order. Variables can be reassigned, and expressions recalculate when their dependencies change. The language needs a rule for which assignment a reference uses and whether definitions below an expression are visible to it.

## Decision

We will resolve each variable reference to its nearest preceding definition in the sheet.

## Alternatives Considered

- **Allow references to definitions below the expression:** This makes the meaning of an expression depend on assignments that appear later, rather than following the sheet from top to bottom.

## Consequences

- A reference before its first definition produces an undefined-variable error.
- Reassigning a variable changes its value for subsequent expressions. Expressions above the reassignment retain their earlier binding.
- Editing an assignment recalculates the expressions that depend on that assignment.
- Moving an assignment can change which definition a reference uses or leave the reference undefined. Sheet order is part of the language's meaning.

## References

- [Intent 001: Calculate everyday expressions correctly](../intents/001-calculate-everyday-expressions.md)
- [Glossary: Sheet and Expression](../../GLOSSARY.md#language)
