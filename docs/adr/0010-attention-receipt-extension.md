# ADR 0010: Extend notification outbox for in-app attention receipts

## Status

Accepted for Updates v1 (2026-07-16). The normative source is revision 4 of
`docs/updates-tab-implementation-plan.md`.

This ADR records the target contract. T-00 does not implement the schema or the
transactional durability boundary described below. In the current implementation,
notification dispatch placement is inconsistent. Many producers dispatch after their
repository mutation, so the domain mutation can succeed before an outbox write fails;
`EvaluationCase.beaconClose` is concrete counter-evidence to any stronger claim because
it awaits `notifyReviewOpened` inside `runInBeaconStateTransaction`. The current
dispatch service can therefore reach outbox, FCM-queue, and email consideration while a
mutation transaction is still open. Channel attempts remain best effort and have no
durable retry ledger. Strictly post-commit channel hand-off is the revision-4 target,
enforced by T-03; it is not the current ordering. T-03 must also close the in-app
receipt gap. Durable channel delivery remains out of v1 scope.

## Decision gates

The Updates v1 product and architecture decisions are:

- **D-1 — unread badge:** the navigation badge counts unread visible receipts from
  the same authorized relation used by the feed. It does not count unresolved work.
- **D-2 — canonical v1 store:** the existing `notification_outbox` is extended in
  place as the per-recipient attention-receipt store. V1 adds no occurrence,
  occurrence-recipient, delivery-job, or throttle table.
- **D-3 — transaction boundary:** each producing use case owns one transaction for
  its domain mutation, recipient resolution, policy projection, and receipt writes
  through a domain-owned unit-of-work port. Destructive transitions resolve their
  audience before the destructive statement in that transaction. Channel hand-off
  remains strictly post-commit and best effort.
- **D-4 — muteability:** mandatory safety or obligation receipts can never be
  suppressed. Only contract-declared noisy in-app preference classes are mutable;
  existing push/email categories are not reused as that policy.
- **D-5 — independent axes:** v1 persists monotonic read acknowledgement only.
  Settlement and unresolved-work facts are deferred to T-16 and are not v1 schema.
- **D-6 — card and badge unit:** one visible unread receipt is one feed card and one
  badge unit. Existing write-time collapse may merge repeats, but v1 has no
  `group_key` and performs no read-time grouping.
- **D-7 — v1 boundary:** v1 includes the feed, unread badge, typed destinations,
  acknowledgement, noisy-class preferences, realtime/catch-up/multi-tab correctness,
  and the required event producers. Settlement, field-level dwell highlights,
  search, non-required event kinds, durable delivery/audit infrastructure, card-marker
  unification, and new retention machinery are deferred.
- **D-8 — one-release flip:** T-08 through T-14 remain hidden behind the default-off
  QA flag. T-15 is one flip release: it exposes Updates unconditionally, removes the
  old Notifications bell, and flips the legacy `/notifications` route to Updates in
  that same release. T-15 also removes the dormant new-producer gate.

## Receipt contract

The outbox extension carries seen state, source identity, typed destination,
presentation data, suppression/preference class, and access policy. Exact destinations
are typed rather than inferred from channel URLs. Opening, explicit acknowledgement,
mark-all-seen, and the defined Chat bridge advance the same monotonic read axis.

The normative event taxonomy is exactly:

1. `relayReceived`
2. `helpOfferSubmitted`
3. `offerAccepted`
4. `offerDeclined`
5. `offerRemoved`
6. `roomMessagePosted`
7. `requestStatusChanged`
8. `reviewOpened`
9. `mutualConnectionFormed`
10. `inviteAccepted`

Issue class 5, Chat admission/removal, is represented by `offerAccepted` and
`offerRemoved`; there is no separate `roomAdmissionChanged` event type. The compact
machine-readable source is `docs/contracts/updates-event-contract.json`. Each row owns
only producer, recipient category, destination family, muteability, and covering test.
The currently missing producer set is exactly `roomMessagePosted`,
`requestStatusChanged`, and `mutualConnectionFormed`. `inviteAccepted` already has live
producers and is not pending.

The contract records the revision-4 target, while `coveringTest` records current
producer evidence. For a non-pending row, that test must exercise the live command and
its legacy notification-port pathway; it does not claim that T-04 has already migrated
the producer to transactional target receipts or that target recipient, destination,
and muteability policy are already implemented. In particular, `reviewOpened` keeps
Part D's target of admitted participants even though its current producer derives the
legacy `reviewReady` audience from the evaluation participant graph. For a pending row,
the pointer is explicitly command-characterization evidence only, never completed
receipt coverage; T-05 must replace that status with enforced producer/receipt proof.

Part D's human-readable `help_offer_case` family maps the accepted, declined, and
removed commands to the concrete command owner `CoordinationCase`; submission remains
`HelpOfferCase.offerHelp`. The misleadingly narrow legacy port name
`notifyHelpOfferToAuthor` does not narrow the `helpOfferSubmitted` target: the downstream
resolver already includes stewards, and the target recipient category remains
`author_and_stewards`.

`inviteAccepted` is limited to relationship-forming invite acceptance. This includes
invite signup in `AuthCase`/`CredentialAuthCase`, `InvitationCase.accept`, and the
non-Beacon relationship-forming route through `InvitationCase.acceptAsExisting`.
`InvitationCase.acceptAsExisting` Beacon-only branches call `bindMutual` with
`bindFriendship: false`; their current legacy notification calls are a producer gap for
T-04/T-05 and must not be projected as profile-directed relationship changes.

## Authorization and presentation boundary

Normal Request (internally: Beacon) receipts use the ADR-0008 visibility predicates.
`recipient_safe` is solely an access policy: a narrow amendment for a sanitized
terminal result that must remain visible after Request access is lost. Destination is
a separate fact. In the compact contract, only `offerDeclined` and `offerRemoved` use
the destination family `beacon_people_or_safe_terminal`; `recipient_safe` never appears
as a destination.

The safe terminal privacy boundary is strict: the receipt is bound to the addressed
account and exposes no Request content and no beacon target. It copies no free-form
reason, body, title, or `action_url`. Its stale-client fallback is sanitized and cannot
link back to the Request. Presentation is accepted only through an allowlisted key and
per-key schema; the allowlist is exactly `room_member_removed`, `offer_declined`, and
`offer_removed`. Focused negative tests must reject every other event/key, unexpected or
overlong payload fields, Request/beacon identifiers or targets, and copied free-form or
channel-link content. This is not a general authorization bypass. These policy/payload
rules live beside the T-02 implementation and tests, not as extra compact-contract
fields.

Private contact labels are excluded because notifying their subject would reveal
viewer-private data. Unilateral negative or unsubscribe trust actions are excluded.
Ordinary Chat traffic is also excluded: only a directed mention, reply, or another
declared semantic target produces `roomMessagePosted`; the general Chat unread model
continues to use `room_seen`. Extra event kinds require a separately reviewed contract
change.

## Deferred target topology and proportionality

The long-term notification-platform shape remains:

`semantic occurrence -> per-recipient receipt -> durable delivery job`

That topology is deferred to T-20 until durable multi-channel delivery, audit/replay,
or historical audience reconstruction becomes approved product scope. Issue #80 asks
for reliable in-app unread activity, not replayable occurrences or retryable push/email
delivery. Transactional per-recipient receipts provide the required in-app guarantee
with materially less schema, projection, retry, and operations machinery.

V1 is retention-neutral. Existing outbox cleanup and digest watermarks continue
unchanged, the extension adds no orphanable tables, and account deletion retains its
current behavior. Retention windows, erasure rewriting, and noisy-unseen expiry belong
to T-22; their deferral is not a claim that the broader policy question is resolved.

## Consequences

Once T-03 is implemented, in-app receipt durability will equal domain-mutation
durability. A receipt failure will roll back the mutation, while a post-commit channel
failure will never do so. Until then, both the current best-effort in-app gap and the
inconsistent transaction/channel placement remain.

Extending the outbox minimizes migration and rollout surface but requires compatibility
with legacy `read_at` rows until T-19. The old bell and route remain authoritative until
the single T-15 flip; T-00 introduces no UI, schema, producer, or durability change.
