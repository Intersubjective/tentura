# GitHub Copilot — Tentura

Follow [`AGENTS.md`](../AGENTS.md) for invariants and rule index.

## Terminology alias (always)

- **Internal / code / DB / GraphQL / routes:** `Beacon`, `beacon`, `beacon_room`, room.
- **User-facing copy (UI, push, landing, emails, snackbars):** **Request** / **Requests**; coordination workspace **Chat**.
- **Never** introduce a `Request` domain entity, table, repository, or route — `Beacon` stays the canonical type.
- Put user-visible wording in [`packages/client/l10n/`](../packages/client/l10n/) ARB values, not hardcoded strings.

See [`.cursor/rules/terminology.mdc`](../.cursor/rules/terminology.mdc) and [`CONTEXT.md`](../CONTEXT.md).
