# ADR 0001: Unified person_capability_event table + extended CommitHelpType (no self-declared source)

Status: Accepted (2026-04-30)

## Context

Tentura needs deterministic, observer-derived capability cues to help people understand who in their network can help with what. Four sources generate these signals:

1. **Private labels** — a viewer privately tags someone with slugs they believe apply.
2. **Forward reasons** — when forwarding a beacon to a recipient, the forwarder picks why that person might help.
3. **Commit roles** — when committing to a beacon, the committer selects what kind of help they are offering (already stored as `beacon_commitment.help_type`; now also mirrored into the event table).
4. **Close acknowledgements** — when evaluating a completed beacon, the evaluator tags what the participant actually helped with.

A fifth source — self-declared capabilities ("I can help with X") — was considered and **explicitly rejected** by the user because people are unwilling to maintain such data and it would re-introduce the exact pattern removed from scope.

We also need a capability taxonomy that can be shared across all four sources. The existing `CommitHelpType` covers 7 slugs; the full taxonomy requires ~30. Extending the existing enum was chosen over a separate taxonomy table.

## Decision

1. **Single `person_capability_event` table** with a `source_type` discriminator covering exactly 4 values: `private_label` (0), `forward_reason` (1), `commit_role` (2), `close_acknowledgement` (3). A fifth `self_declared` value does **not** exist and must not be added.

2. **Extend `CommitHelpType`** (and `kAllowedHelpTypeKeys`) to align with the wider `CapabilityTag` taxonomy. The legacy slug `skill` is deprecated and rewritten to `other` via a one-time migration. All other legacy slugs (`money`, `time`, `verification`, `contact`, `transport`, `other`) become 1:1 aliases.

3. **Hasura is bypassed for capability reads.** All reads go through V2 use cases (`CapabilityCase`) which apply per-source visibility filtering server-side. The table is not exposed to client roles via Hasura. This avoids embedding row-level visibility logic in Hasura permission DSL (which is fragile and hard to audit).

4. **Client-hardcoded `CapabilityTag` enum** with stable `slug` strings. Server stores the slug as plain `text` (mirrors `beacon.tags` / `beacon_evaluation.reason_tags`). No capability taxonomy table in the database.

5. **Profile editor (`ProfileEditScreen`) is untouched.** Users cannot self-declare capabilities.

## Consequences

- Capability cues only become populated as people act (label, forward, commit, close-ack). Cold-start: new users see no cues.
- Server `CapabilityCase` is the single source of truth for visibility; Hasura DSL is not involved for these reads.
- `CommitHelpType` taxonomy grows; clients that do not know a new slug see it as unknown (handled gracefully with `fromSlug` fallback).
- Slug validation happens at the API boundary in `CapabilityCase`; invalid slugs are rejected with exception code 1300+.

## Alternatives considered

- **Separate tables per source** — rejected: four schema definitions, four sets of queries, more JOINs for aggregated cue views. Unified table simplifies `getCapabilityCues` into a single filtered `SELECT`.
- **Shared Hasura permissions for capability reads** — rejected: `visibility` column semantics differ per `source_type`; encoding that in Hasura permission rows is brittle and not auditable.
- **Self-declared source** — rejected explicitly by the user (second instruction during grilling). Users were unwilling to maintain self-declared capability profiles; including it would re-introduce the exact pattern that was removed from scope.
- **Separate taxonomy table** — rejected: client-hardcoded enum + server slug validation matches existing `beacon.tags` pattern; avoids a migration when adding new slugs (add to enum + server constant + l10n only).
