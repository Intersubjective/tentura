# Attention Indicators (Inbox & My Work)

**User-facing:** bottom-navigation dots and per-Request card markers indicate unread
attention only when the Request belongs to a successfully loaded Inbox or My Work
projection.

## Product contract

- A Request belongs to **Inbox XOR My Work XOR neither** for these indicators.
- Becoming genuinely involved—for example, authoring or offering help—moves the Request
  to My Work; My Work wins if stale client snapshots temporarily contain it in both.
- If neither loaded projection contains the Request, the client shows no Inbox/My Work
  dot or card marker.
- The active tab hides its navigation dot. Its per-card markers remain visible; entering
  a tab does not mark attention receipts seen.
- The Updates tab remains the place that owns receipt acknowledgement and unread totals.

## Architecture boundary

Server/domain authority is semantic involvement plus receipt state, not UI surface
membership. Beacon-scoped producers record event-time recipient reasons such as author,
forward recipient, admitted or active participant, affected participant, review
participant, Inbox stance holder, or directed Chat target. The attention policy rejects
a Beacon-scoped receipt that lacks a semantic Beacon relationship.

The server exposes:

```graphql
attentionMarkers(beaconIds: [String!]!): AttentionMarkerProjection!
```

It accepts at most 500 unique candidate ids and returns authorized, unseen
`unreadBeaconIds`. It does not accept or return Inbox/My Work labels.

The presentation adapter owns surface selection:

```text
successful Inbox snapshot ─┐
                            ├─ candidate union ─▶ authorized unread ids
successful My Work snapshot ┘                         │
                                                      ▼
Inbox markers   = unread ids ∩ (Inbox ids - My Work ids)
My Work markers = unread ids ∩ My Work ids
```

This distinction matters during eventual consistency. A stale or failed client
projection does not revoke a valid domain receipt, but it also cannot manufacture a dot.
The client suppresses indicators until it can map semantic unread ids onto current cards.

## Candidate projections

- **Inbox:** ids in the successfully loaded Needs me and Watching collections.
- **My Work:** ids in the successfully loaded non-archived card collection.
- Rejected Inbox rows and archived My Work cards do not contribute to their primary-tab
  indicators.

`HomeAttentionCubit` queries the candidate union in chunks of 500. A changed surface
snapshot, account change, attention-feed refresh, query failure, or unknown initial load
clears existing markers immediately. Both surface snapshots and the marker query must
complete successfully before any marker can appear. Account and projection generations
discard stale asynchronous responses.

Inbox and My Work projections are loaded eagerly at the home shell (alongside their
snapshot reporters), so markers can appear on the first visited tab without requiring
the user to open the other surface first.

## Key files

| Responsibility | File |
|---|---|
| Server GraphQL projection | `packages/server/lib/api/controllers/graphql/query/query_attention.dart` |
| Authorized unread lookup | `packages/server/lib/domain/port/attention_query_port.dart`, `packages/server/lib/data/repository/attention_repository.dart` |
| Domain recipient invariant | `packages/server/lib/domain/attention/attention_models.dart`, `attention_policy.dart` |
| Client GraphQL request | `packages/client/lib/features/attention/data/gql/attention_markers.graphql` |
| Client attention boundary | `packages/client/lib/domain/attention/attention_case.dart`, `attention_repository_port.dart` |
| Surface presenter | `packages/client/lib/features/home/ui/bloc/home_attention_cubit.dart`, `home_attention_state.dart` |
| Snapshot reporters | `inbox_needs_me_reporter.dart`, `my_work_attention_reporter.dart` |
| Navigation dots | `inbox_navbar_item.dart`, `my_work_navbar_item.dart` |
| Card marker | `packages/client/lib/features/home/ui/widget/attention_marker.dart` |

## Retired behavior

T-21 removed the local “since last visit” cursor system: `NewStuffCubit`, per-account
Drift timestamp keys, max-activity comparisons, `InboxRowHighlightKind`, and New/Updated
timestamp reasons. Indicator truth now comes from unread attention receipts, while
surface placement remains a client presentation decision.
