# Mutual Friends

Shows which users Alice and Bob both know and trust, computed on-demand server-side via MeritRank.

## What it does

When Alice views Bob's profile (or considers accepting Bob's invite), she can tap **"Show mutual friends"** to fetch the set of users that:

1. Alice knows mutually — i.e. Alice→person score > 0 **and** person→Alice score > 0
2. Bob knows mutually — i.e. Bob→person score > 0 **and** person→Bob score > 0
3. Are neither Alice nor Bob themselves

The result replaces the button with overlapping mini-avatars (+N overflow badge). If the set is empty a short "No mutual friends" label is shown instead.

## Sorting (bridge score)

Results are ordered by a synthetic **bridge score** computed for each mutual friend P:

```
bridge_score(P) = fwd(alice→P) × rev(P→alice) × fwd(bob→P) × rev(P→bob)
```

Higher bridge score means P is more strongly connected to **both** sides, so they appear first. The computation is done in a single SQL expression with no extra queries.

## Architecture

```
[Alice's client]
  └─ MutualFriendsButton (StatefulWidget, on-demand)
       └─ MutualFriendsRepository (client, @lazySingleton)
            └─ Ferry: MutualFriendsFetch query  ─────────────────────────┐
                                                                         ▼
                                                      [Tentura V2 /api/v2/graphql]
                                                      QueryMutualFriends resolver
                                                        └─ MutualFriendsCase
                                                             └─ MutualFriendsRepository (server)
                                                                  └─ SQL: mutual_friends(alice, bob, ctx)
                                                                       └─ mr_mutual_scores() × 2  (pgmer2)
```

### Key files

| Layer | File |
|---|---|
| DB migration | `packages/server/lib/data/database/migration/m0031.dart` |
| Server repository | `packages/server/lib/data/repository/mutual_friends_repository.dart` |
| Use case | `packages/server/lib/domain/use_case/mutual_friends_case.dart` |
| V2 GraphQL query | `packages/server/lib/api/controllers/graphql/query/query_mutual_friends.dart` |
| GraphQL operation | `packages/client/lib/features/profile_view/data/gql/mutual_friends_fetch.graphql` |
| Client repository | `packages/client/lib/features/profile_view/data/repository/mutual_friends_repository.dart` |
| UI widget | `packages/client/lib/features/profile_view/ui/widget/mutual_friends_button.dart` |

### Surfaces

- **Profile view screen** — button row below "Show Beacons" in `profile_view_body.dart`
- **Invitation accept dialog** — below the inviter's name in `invitation_accept_dialog.dart`

## Design notes

- **On-demand only** — never fetched proactively; no caching; no cubit involvement. The `StatefulWidget` owns the fetch lifecycle so it works identically inside a full screen (where a cubit is present) and inside a dialog (where there is none).
- **V2 only** — `MutualFriendsFetch` is registered in `_tenturaDirectOperationNames` and resolves against `/api/v2/graphql`, not Hasura.
- **SQL-level intersection** — the entire computation (dual `mr_mutual_scores` calls + INTERSECT + bridge-score sort) is a single `STABLE` PostgreSQL function, keeping the server resolver trivial.
- **`mr_mutual_scores` column semantics** — for a row `(src, dst)`: `score_value_of_dst` is src→dst (forward from src), `score_value_of_src` is dst→src (forward from dst / reverse from src). This matches the convention used throughout the codebase (e.g. `m0023.dart` inbox provenance).
- **Overflow display** — reuses `CompactForwarderAvatars` (up to 5 avatars shown, remainder as `+N`).
