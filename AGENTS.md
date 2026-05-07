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
