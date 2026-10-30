---
name: 005-use-swift-testing-for-application-tests
status: accepted
date: 2026-10-30
updated: 2026-10-30
sources: []
---

# ADR-005: Use Swift Testing for application tests

## Context

The evaluator tests take complete sheet inputs and check each expression's result. The acceptance examples of the calculation language are the fixtures, so one test body runs over many pairs of input and expected output. A failing pair needs to be identifiable on its own.

The integration tests check what a direct evaluator call cannot show: the reevaluation triggers, the removal of stale results, and the effect of the Settings. These behaviors depend on the clock and on application events.

## Decision

We will write the application tests with Swift Testing, at the evaluator and at the model layer, without UI automation.

## Alternatives Considered

- **XCTest:** It has no built-in parameterized tests, so the examples would run in a loop inside one test.
- **Quick and Nimble:** These are third-party libraries for behavior-style tests. They add a dependency without a need the application tests have.
- **UI automation:** Model-layer tests cover the reevaluation triggers and the Settings without opening the window.

## Consequences

- Each acceptance example is one argument of a parameterized test, and the test report shows which argument failed.
- Model-layer tests receive the clock and the application events as injected dependencies.
- The appearance of results, errors, and Settings is checked by hand.
- Tests need a Swift toolchain that includes Swift Testing.

## References

- [ADR-004: Use Swift for the application](004-use-swift-for-the-application.md)
- [Intent 001: Calculate everyday expressions correctly](../intents/001-calculate-everyday-expressions.md)
- [Swift Testing](https://github.com/swiftlang/swift-testing)
