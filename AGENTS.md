# AGENTS.md

Guidance for AI agents working in this repository.

## Project

Solvr is a beautiful text calculator for Mac. It combines a calculation language with sheets that stay saved, organized, and synced.

## Structure

- `App/` — the `Solvr` app target: SwiftUI views, AppKit wrappers, and app-owned coordination
- `Core/` — the `Core` framework target: evaluator, sheet model, and app-independent services
- `CoreTests/` — tests for `Core`
- `AppTests/` — app-hosted tests for `Solvr`
- `PRODUCT.md` — the product register: purpose, users, brand personality, design principles
- `GLOSSARY.md` — the language of the product; define every new domain term here
- `docs/product/PRD.md` — requirements (FR, NFR), scope, assumptions, risks, open questions
- `docs/adr/` — architecture decision records, one file per decision

## Build

- The app and `Core` target macOS 26.0 or later and build with Xcode 27 or later.
- Generate the Xcode project with `xcodegen generate`, then build with `xcodebuild -project Solvr.xcodeproj -scheme Solvr -destination 'platform=macOS' build`.
- Test with `xcodebuild -project Solvr.xcodeproj -scheme Solvr -destination 'platform=macOS' test`. On a machine without the team's Apple Development certificate, append `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Automatic`.
- Judge a test run by the exit status of `xcodebuild`, with `set -o pipefail` when the output is piped, and by a nonzero count in each Swift Testing line `Test run with <N> tests`. The XCTest line `Executed 0 tests` is expected.
- The app lands in Xcode's default DerivedData folder: `~/Library/Developer/Xcode/DerivedData/Solvr-<hash>/Build/Products/Debug/Solvr.app`. The hash differs per machine; print the exact folder with `xcodebuild -project Solvr.xcodeproj -scheme Solvr -destination 'platform=macOS' -showBuildSettings | grep BUILT_PRODUCTS_DIR`.
- To see a visual change, launch the app with `open <BUILT_PRODUCTS_DIR>/Solvr.app`, open Settings with `osascript -e 'tell application "System Events" to keystroke "," using command down'` when the change is there, capture the screen with `screencapture -x <file>.png`, and read the image. The capture needs the macOS Screen Recording permission for the terminal.

## CI

- `.github/workflows/ci.yml` runs on the `xcode-27` runner: it installs XcodeGen and swiftformat, checks formatting with `scripts/check-swift-format.sh`, generates the project, builds, and runs `CoreTests` and `AppTests`.
- A change to a build or test entry point updates the workflow in the same branch.

## Conventions

- All documents in English.
- Use the terms defined in `GLOSSARY.md` and prefer the defined term over an `_Avoid_` word for the same concept; an `_Avoid_` word stays free for its other meanings. When a concept has no term, add it to the glossary instead of rotating synonyms.
- Requirements stay at requirement level. Implementation choices such as the engine, the sync mechanism, or the tracker service enter the documents only when the work asks for them.
- Record only what was said. No gap filling with assumptions, and flag each assumption. Documents carry no chat references.
- Assign an ID to every new requirement: the next free number in its list (FR for functional, NFR for non-functional).
- The PRD keeps its numbered structure (1. Problem through 8. References) and the scope groups Must Have, Should Have, Could Have, Won't Have, and Out of Scope.
- An ADR keeps the structure name, Context, Decision, Alternatives Considered, Consequences, References.
- Code comments follow the keep list of the `strip-comments` skill; a domain rule, an invariant, or a surprise of the project's own code belongs in a name, a type, or a test instead. Comments use normative, self-contained, present-tense prose, with no historical narration and no IDs outside such a link.
- Delete migration scaffolding, such as a conditional compilation guard or a compatibility shim, once its condition can no longer be false; do not leave it disabled.
- Commits follow Conventional Commits in English, with `docs:` for document-only changes so far.
- Conventional commit messages carry the Linear issue they implement as the scope, in lowercase, e.g. `feat(adk-233): add the Solvr core package`. A fix made after a task is integrated into its spec branch takes the spec's issue as scope.
- Pull requests merge into `main` with a merge commit.

## Issue tracker

Tracker: Linear; team Development; project Solvr App.

## Merge method

Pull requests merge with a merge commit, preserving branch commits.
