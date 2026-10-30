# AGENTS.md

Guidance for AI agents working in this repository.

## Project

Nume is a beautiful text calculator for Mac. It combines a calculation language with sheets that stay saved, organized, and synced.
## Layout

- `PRODUCT.md` — the product register: purpose, users, brand personality, design principles
- `GLOSSARY.md` — the language of the product; define every new domain term here
- `docs/product/PRD.md` — requirements (FR, NFR), scope, assumptions, risks, open questions
- `docs/adr/` — architecture decision records, one file per decision

## Conventions

- All documents in English.
- Use the terms defined in `GLOSSARY.md` and prefer the defined term over an `_Avoid_` word for the same concept; an `_Avoid_` word stays free for its other meanings. When a concept has no term, add it to the glossary instead of rotating synonyms.
- Requirements stay at requirement level. Implementation choices such as the engine, the sync mechanism, or the tracker service enter the documents only when the work asks for them.
- Record only what was said. No gap filling with assumptions, and flag each assumption. Documents carry no chat references.
- Assign an ID to every new requirement: the next free number in its list (FR for functional, NFR for non-functional).
- The PRD keeps its numbered structure (1. Problem through 8. References) and the scope groups Must Have, Should Have, Could Have, Won't Have, and Out of Scope.
- An ADR keeps the structure name, Context, Decision, Alternatives Considered, Consequences, References.
- Commits follow Conventional Commits in English, with `docs:` for document-only changes so far.
- Conventional commit messages carry the Linear issue they implement as the scope, in lowercase, e.g. `feat(adk-233): add the Nume core package`.

## Issue tracker

Tracker: Linear — team Development, project Nume App. Configuration: repository-local `tracker.*`; inspect with `git config --local --get-regexp '^tracker\.'`. Change with "configure tracker".
