# Journal — issue-178 help offer author seen

Implementation journal for issue #178 (help offer "seen by the author").
Entries cite the plan's bead units by id.

## P1.6 — bridge_attention_people_seen UPDATE plan

The focused PostgreSQL test seeds 200 outbox rows for each account, including 20 matching receipts, runs `ANALYZE`, and explains the bridge UPDATE with `enable_seqscan = off` for the author obligation and steward optional shapes. The UPDATE requires `seen_at IS NULL` and filters by `account_id` and `created_at`, so the existing partial `notification_outbox__unread` index is eligible for both shapes. The obligation and optional indexes require predicates absent from this UPDATE.

**Decision: no index added.**

**Rationale:** Both author and steward have an eligible Index Scan through `notification_outbox__unread`; the PostgreSQL test checks the actual plans for an outbox index scan and rejects a sequential scan. Verified against the local docker PostgreSQL: both EXPLAIN cases ran (not skipped) and passed.

## P6 — two-account check: author opens People, offerer's footer flips

`run_client_integration_web_local.sh` cannot drive two accounts (one headless
`flutter drive` session per file), so the two-browser check runs through the
multiclient runner instead:

```bash
REALTIME_MULTICLIENT_DRIVER=help_offer_author_seen_multiclient_web_test.dart \
REALTIME_MULTICLIENT_RUNS=3 REALTIME_MULTICLIENT_NEGATIVE_PROOFS=false \
./scripts/run_realtime_multiclient_web_local.sh
```

Session `20260925-152254` (base `70e8e0e80` plus the working-tree observer
People fix), 3 of 3 runs passed:

- Account A (offerer) opened the Request's People tab and saw its own pending
  offer with "Sent · not seen by the author yet".
- Account B (author) then opened People; A flipped to "Seen by the author ·
  awaiting decision" after 240–320 ms, with no reload (window marker and URL
  unchanged).
- B's help_offer_submitted receipt in Activity was marked seen 44–54 ms after
  that (the `bridge_attention_people_seen` bridge).

Findings while getting the driver green:

- The author's own Request is in their responsibility scope, so B's
  `help_offer_submitted` receipt lives on the `myWork` attention surface,
  never `activity`. The driver reads the author's whole attention feed.
- The seen row's `Tooltip` puts "Seen <date> · <time>" before the label in
  the same web semantics node, so the driver matches the label per line.
- B's People lens keeps pending offers in a collapsed "Willing to help"
  section, so the driver waits on that heading, not the offer message.
- Icons are painted on the canvas; the label stands in for `Icons.done` /
  `Icons.done_all`, whose pairing `help_offer_tile_author_seen_test.dart`
  pins.
