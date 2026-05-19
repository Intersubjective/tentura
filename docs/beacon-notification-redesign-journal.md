# Beacon notification redesign — implementation journal

Consult at the start of each work session and after any FCM test failure.

## Phase 6.4 journal drift

`docs/beacon-room-implementation-journal.md` claimed plan/blocker-open FCM was done; code had `notifyPlanUpdatedToRoom` unwired, coordination-item paths had zero FCM, and legacy `beacon_blocker` paths were still active. This redesign supersedes that slice.

---

## YYYY-MM-DD — PR N title

### Done

- …

### Unexpected

- …

### FCM checklist status

- [ ] link format (`/#/shared/view?…` or `/#/beacon/review/{id}`)
- [ ] data payload strings only (`link`, `kind`, `priority`, `beaconId`, `item`)
- [ ] batch key (receiver + beacon + priority band)
- [ ] actor excluded from recipients
- [ ] tests green

### Next

- …

---

## 2026-05-19 — Full plan implementation

### Done

- PR1–PR5: `BeaconNotificationPort`, coordination-only resolver/copy, batch composite key, coordination use-case wiring, evaluation review link fix.
- PR6: `dest=review|people|room`, `item=` query → `kQueryCoordinationItemId`, room thread scroll on open.
- PR7–PR8: Client need-info → ask; mark-done resolve → `resolveBlocker`; removed legacy GraphQL mutations; server `roomMessageMarkSemanticDone` only.
- PR9: `m0076` drops `beacon_blocker` table and `linked_blocker_id`; room state open blocker from `coordination_item`.
- PR10: Removed `BeaconBlockerRepository`, dead `beacon_room_repository` legacy helpers, orphan `.graphql` ops.

### Unexpected

- Client `flutter test` for router tests blocked by local Flutter SDK compile errors (unrelated to diff); server pure tests pass.

### FCM checklist status

- [x] link format (`/#/shared/view?…`, `/#/beacon/review/{id}`, `dest=people`)
- [x] data payload strings only (`link`, `kind`, `priority`, `beaconId`, `item`)
- [x] batch key (receiver + beacon + priority band)
- [x] actor excluded from recipients
- [x] server unit tests green (aggregator, evaluation, coordination)

### Next

- Deploy client before or with server (legacy mutations removed). Consider `MIN_CLIENT_VERSION` minor bump when shipping.
- Optional: remove Drift `BeaconBlockers` table class after `dart run drift_dev make-migrations` on m0076.
