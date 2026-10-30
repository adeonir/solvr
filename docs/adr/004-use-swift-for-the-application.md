---
name: 004-use-swift-for-the-application
status: accepted
date: 2026-10-30
updated: 2026-10-30
sources: []
---

# ADR-004: Use Swift for the application

## Context

Nume is a text calculator for the Mac that runs on macOS 15 or later (NFR-3). The repository holds documentation and no application code yet, so no language is in use.

## Decision

We will write the application in Swift.

## Consequences

- The application and its tests use the Swift toolchain and the Foundation framework.
- Libraries and frameworks for the application are chosen from the Swift ecosystem.
- The application runs only on Apple platforms.

## References

- [PRD: NFR-3](../product/PRD.md)
- [Intent 001: Calculate everyday expressions correctly](../intents/001-calculate-everyday-expressions.md)
