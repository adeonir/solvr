---
id: "011"
name: report-operation-without-personal-data
status: draft
created: 2026-10-29
updated: 2026-10-29
---

# Intent: Report operation without personal data

## Problem

External data sources can fail or change, and the author wants visibility into failures through telemetry.

## Proposed outcome

The app sends crash reports, errors, and usage data without personal data, and users can turn all telemetry off together.

## Affected users and systems

The author and other Mac users with the same use cases; the app.

## Constraints

- Telemetry is on by default. The Telemetry option in Settings turns all telemetry off.
- Every telemetry event carries no personal data.
- Sheet text and expressions are sent only after anonymization: each real name and number is replaced by a false value of the same type and format, preserving calculability. No link between real and false values is kept.
- For example, `salário = R$ 8.000 - 4%` becomes `var1 = R$ 3.517 - 7%`.

## Open questions

None.
