# Case Readiness Percentage Bar

This document explains how the Case Detail header percentage bar works in ProofKit.

## What the percentage means

The percentage is a **product readiness score** for helping the user organize a ProofKit packet. It is not a legal score and must not imply that the user has a complete legal case.

The header displays the score as:

```text
70% ready · Next: Review inbox
```

The progress bar is a visual version of the same score, where `score / 100` determines the filled width.

Implementation lives in:

```text
ProofKit/Services/CaseReadinessCalculator.swift
```

The Case Detail header consumes the result in:

```text
ProofKit/Views/CaseDetailView.swift
```

## Score model

The calculator returns an integer from `0` to `100` using measurable local case state.

### Case basics — 20 points

| Signal | Points |
| --- | ---: |
| Case title exists | 8 |
| Case type/category selected | 6 |
| Short description/context exists | 6 |

Notes:
- `userTitle` powers the title check.
- `userSummary` or `userNotes` powers the description/context check.
- The category chip is normalized for user-friendly display: `School`, `Apartment`, `Refund`, `Work`, etc. `Other` is only used as a fallback.

### Proof added — 25 points

| Signal | Points |
| --- | ---: |
| At least 1 proof item exists | 10 |
| At least 2 proof items exist | 8 |
| At least 1 item has OCR text or manual note content | 7 |

The content check looks only for presence of content. It does not send or expose OCR text or notes.

### Inbox/review readiness — 20 points

| Signal | Points |
| --- | ---: |
| No unreviewed imported items | 12 |
| All proof items are handled | 8 |

A proof item needs review when `EvidenceItem.needsReview` is true. In the current Case Detail session, items the user taps `Skip` on are treated as handled for readiness/export blocker purposes without adding any persisted schema.

### Timeline quality — 20 points

| Signal | Points |
| --- | ---: |
| At least 1 timeline item has a date/time | 7 |
| Timeline has at least 2 dated items, or 1 strong detailed item | 7 |
| Important items have labels/titles/categories | 6 |

A “strong detailed item” currently means a dated item with a useful title/category plus either substantial detail text or an important marker.

### Export readiness — 15 points

| Signal | Points |
| --- | ---: |
| PDF can be generated | 8 |
| Packet includes proof index/timeline | 4 |
| Optional statement setting is chosen/defaulted | 3 |

Currently:
- PDF generation readiness requires a title, at least one proof item, and no current unreviewed inbox blockers.
- The proof index/timeline condition is true when the case has at least one proof item.
- The optional statement setting defaults to chosen, so that signal is true.

## Readiness buckets

The score is also mapped to a bucket for analytics and reporting:

| Score | Bucket |
| ---: | --- |
| 0–24 | `0–24% ready` |
| 25–49 | `25–49% ready` |
| 50–74 | `50–74% ready` |
| 75–99 | `75–99% ready` |
| 100 | `100% ready` |

## Next step label

The next-step label is chosen by priority order:

1. Missing title or category → `Next: Finish case details`
2. No proof items → `Next: Add proof`
3. Unreviewed inbox items → `Next: Review inbox`
4. Weak/no timeline dates → `Next: Check timeline`
5. Ready to export → `Next: Export packet`
6. Export generated and score is 100 → `Packet generated`

Examples:

```text
35% ready · Next: Add proof
70% ready · Next: Review inbox
92% ready · Next: Export packet
100% ready · Packet generated
```

## What makes the bar update

The header recalculates from current SwiftData/view state whenever SwiftUI observes changes to the bound `CaseFile` or related state, including:

- proof added
- proof reviewed
- proof skipped in the current session
- timeline dates/details changed
- case title/summary/category changed
- export packet generated

## Analytics privacy

The readiness flow emits the placeholder/no-op event:

```text
case_readiness_calculated
```

Allowed properties include only safe metadata such as:

- hashed case ID
- hashed user ID
- case type/category
- readiness score and bucket
- next step
- proof/review/timeline/export counts
- booleans like `has_title` and `has_description`
- subscription tier
- case age in days

The event must never include:

- OCR text
- user notes
- screenshots
- documents
- filenames
- raw case title
- raw case description
- local file paths

## Data preservation note

The readiness calculator is read-only. It does not modify SwiftData models, model-container configuration, storage paths, migrations, documents, attachments, photos, or export files.
