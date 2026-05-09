# ProofKit Codex Rules

## P0: Preserve local SwiftData user data

ProofKit stores user-created and user-owned data locally with SwiftData, including documents, photos, learning/progress state, and other app data. There is currently no cloud backup for this data.

Data preservation across app updates is the top user-experience priority. Treat any realistic risk of data loss as release-blocking.

When working in this project, Codex must:

- Never reset, wipe, recreate, relocate, or destructively migrate the production SwiftData store as a shortcut.
- Never remove, rename, or change SwiftData models, properties, relationships, delete rules, identifiers, storage paths, or model-container configuration without an explicit backward-compatible migration/data-preservation plan.
- Prefer additive, backward-compatible schema changes. If a breaking change is unavoidable, implement and verify a migration path from the previously released app schema.
- Preserve user documents, imported/generated photos, progress, settings, and account-scoped local data during updates, sign-in/sign-out flows, and account switching.
- Avoid storing user-owned data only in temporary/cache locations unless the data is intentionally disposable and clearly documented as such.
- Before completing any persistence-related change, document the data-loss assessment and verification performed in `tasks/todo.md`.
- If migration behavior cannot be verified, clearly call that out before considering the work complete.

## P1: Keep simple UI changes fast and proportional

For clearly scoped UI edits like adding, moving, styling, or wiring a single button, Codex must:

- Make the code change directly and keep the task focused.
- Avoid broad refactors, full clean builds, DerivedData cleanup, dependency reinstalls, or unrelated environment work unless the user explicitly asks or the quick change cannot be checked otherwise.
- Prefer fast static verification (`git diff --check`, targeted code inspection, or a small focused compile check if already cheap).
- If a full build is blocked by local environment issues such as low disk space, stop and report that instead of spending extra time cleaning or debugging the environment.
- Treat a simple button/UI tweak as a minutes-scale task; with high or extra-high reasoning, the extra reasoning should improve precision, not expand scope or runtime.
