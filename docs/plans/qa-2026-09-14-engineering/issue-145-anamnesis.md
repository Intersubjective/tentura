# Issue #145 — Stale child invite restores parent access after leave

**GitHub:** [Intersubjective/tentura#145](https://github.com/Intersubjective/tentura/issues/145)  
**Parent:** [Intersubjective/tentura#142](https://github.com/Intersubjective/tentura/issues/142) (2026-09-14 product testing)

## Symptom

A participant who **left** a parent request regained access by opening an **old invite** into a nested (child) request. Consumed / revoked / superseded invites must not re-admit someone who abandoned parent membership; joining a child must not silently restore parent privileges.

## Root cause

Two server gaps work together with the client accept flow:

1. **`InvitationCase.acceptAsExisting`** (`invitation_case.dart` ~281–298): When the caller is already friends with the issuer and the invite targets a child request (`beaconId != null`), a **consumed** invite still returns **`true`** without throwing and **never** calls `bindMutual`. The landing / accept path treats that as success, so reopening a spent child invite link is indistinguishable from a fresh join (no expired/revoked UX).

2. **`UserRepository.bindMutual` → `_materializeBeaconInviteForward`** (`user_repository.dart` ~840–889, ~116–146): For a **pending** child invite, consumption does **not** validate that `parent_forward_edge_id` still denotes an active parent admission. After the guest’s inbound forward on the parent is cancelled (leave), `bindMutual` still **claims the invitation** and materializes a child forward edge anchored to the stale parent edge id. That re-opens the coordination path the product classifies as “back on the request tree.”

Invite **preview** correctly hides beacon payload for consumed codes (`BeaconVisibility.canPreviewInvite` + `_previewBeaconForInvite`); the failure is on **accept** and on **consumption guards**, not on anonymous preview.

**Note:** `beacon_can_read_content` ignores `recipient_rejected` on forward edges (only `cancelled_at IS NULL`). Declining without cancel may still look like “has edge” in SQL; product “leave” may use cancel, withdraw, or reject — fixes should align invite invalidation with effective admission, not only `cancelled_at`.

## Relevant code

| Area | Path | Symbol / lines |
|------|------|----------------|
| Accept (existing user) | `packages/server/lib/domain/use_case/invitation_case.dart` | `acceptAsExisting` ~262–317; friends + consumed branch ~281–298 |
| Preview | same | `preview` ~126–187; `_previewBeaconForInvite` ~189–232 |
| Invite consumption | `packages/server/lib/data/repository/user_repository.dart` | `bindMutual` ~840–907; `_materializeBeaconInviteForward` ~116–146 |
| Parent read predicate | `packages/server/lib/data/database/migration/m0169.dart` | `beacon_can_read_content` (forward edge `cancelled_at IS NULL` only) |
| Hierarchy linked read | `packages/server/lib/data/database/migration/m0155.dart` | `beacon_can_read_linked_detail` |
| Client accept UX | `packages/client/lib/features/invitation/ui/dialog/invitation_accept_dialog.dart` | Confirmation before accept (does not re-check leave state) |

## Failing tests (TDD — expected red)

### Unit (no Postgres)

**File:** `packages/server/test/domain/use_case/invitation_case_test.dart`  
**Test:** `consumed child beacon invite, already friends -> IdNotFoundException (issue #145 stale invite must not re-admit)`

**Command (from `packages/server`):**

```bash
../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test \
  test/domain/use_case/invitation_case_test.dart \
  --exclude-tags pg \
  --name "issue #145"
```

**Observed (2026-09-15):** `+0 -1` — `acceptAsExisting` emits `true` instead of `IdNotFoundException`.  
Log: `/tmp/issue-145-unit.log`

### Postgres (`@Tags(['pg'])`)

**File:** `packages/server/test/data/repository/issue_145_stale_child_invite_pg_test.dart`  
**Test:** `unconsumed child invite must not be consumable after parent leave (issue #145)`

**Command:**

```bash
../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test \
  test/data/repository/issue_145_stale_child_invite_pg_test.dart \
  --tags pg \
  --name "issue #145"
```

**Observed (2026-09-15):** `+1 -1` — after cancelling the parent forward edge, `bindMutual` still returns `true` (expected `false` / reject consumption).  
Log: `/tmp/issue-145-pg.log`

**Green guard in same file (documents desired hierarchy invariant):** `after child invite consumed, leaving parent must drop parent linked access` — passes with current SQL when parent forward is cancelled.

**Unit-only reproduction:** The consumed-invite + `acceptAsExisting` path is fully reproducible without Postgres. The stale-`parent_forward_edge_id` consumption path needs `@Tags(['pg'])` (real `bindMutual` + forward materialization).

## Expected behavior (fix acceptance)

- After leaving the parent, opening an old child invite shows **expired/revoked/consumed** state; **no** request body / join success.
- `acceptAsExisting` / `bindMutual` must **reject** invites whose parent anchor or issuer admission is no longer valid.
- Consuming a child invite must **not** materialize forwards that resurrect abandoned parent membership.
- Optional hardening: `beacon_can_read_content` should treat `recipient_rejected` like a dead edge if product defines decline as leave.

## Recommended fix (for implementer)

1. **`InvitationCase.acceptAsExisting`:** For `beaconId != null`, treat `isAccepted` / `isExpired` like non-friend path (`IdNotFoundException` or dedicated invite-invalid exception). Do **not** return `true` for consumed child invites when already friends.
2. **`bindMutual` / `_materializeBeaconInviteForward`:** Before claiming the row, resolve `parent_forward_edge_id` (if set): require active parent forward chain and/or current parent `beacon_can_read_content` for the recipient via issuer anchor; otherwise fail closed (no forward insert, no invite claim).
3. **Invitation invalidation:** On parent leave (cancel forward, reject, or explicit leave mutation when it exists), invalidate or supersede pending child invites that reference that admission (DB column or join table — product decision).
4. **Client:** Map server invite-invalid errors to landing revoked/expired UI (`invitation_accept_dialog` / invite route); never navigate to child detail on silent `true`.

Do not weaken `BeaconVisibility.canPreviewInvite` consumed checks.

## Codex / agent edit boundaries

**May touch:**

- `packages/server/lib/domain/use_case/invitation_case.dart`
- `packages/server/lib/data/repository/user_repository.dart` (consumption + materialize only)
- `packages/server/lib/domain/port/user_repository_port.dart` (only if signature/contract change required)
- `packages/server/test/domain/use_case/invitation_case_test.dart`
- `packages/server/test/data/repository/issue_145_stale_child_invite_pg_test.dart`
- Optional: SQL migration for `beacon_can_read_content` / invite invalidation if admission rules change
- Client invite accept + landing only if server errors need mapping: `packages/client/lib/features/invitation/**`

**Do not touch:**

- Generated `*.g.dart`, `*.freezed.dart`, Drift generated code (regenerate via build_runner)
- Unrelated constellation / evaluation / other QA issues
- User-facing copy that says **beacon** / **room** (Request / discussion per terminology contract)
- `packages/server/lib/domain/port/**` except narrow invite/admission ports if added

## Architecture constraints

- Server use cases depend on **ports**, not concrete repositories, for new dependencies.
- No hand-edits to generated files.
- Internal **Beacon** naming in code; user-facing **Request** in any new strings.
