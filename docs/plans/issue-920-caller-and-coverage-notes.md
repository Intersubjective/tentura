# #920 — caller finding and coverage map

Bead: `tentura-qgmr.1`. These notes are the handoff for Alloy's bead record;
task tracking and git remain owned by Alloy.

## Caller finding

The reported four events on 2026-11-01 at 00:15 UTC are consistent with an
external/scripted or stale caller posting an operation with a Hasura scalar to
`POST /api/v2/graphql`. The current client documents do not explain that input.
This is attribution by elimination, not identification of a specific user agent:
the original four event payloads and request logs were not available here.
Distinguishing an external/QA script from a stale client requires those records;
do not claim that either specific caller has been proven.

Repository evidence:

```sh
rg -n 'timestamptz' packages/client/lib --glob '*.graphql' --glob '!**/schema.graphql'
```

Only these variable definitions occur:

| Document / operation | Variable | Routing and selections |
| --- | --- | --- |
| `features/inbox/data/gql/activity_offers.graphql` / `ActivityOffers` | `$at: timestamptz!` | Hasura `inbox_item` and `inbox_item_aggregate`; imported `InboxItemFields`, `BeaconModel`, `UserModel`, and `ImageModel` contain Hasura fields, not Tentura remote-schema selections. |
| `features/invitation/data/gql/invitations_fetch_by_user_id.graphql` / `InvitationsFetchByUserId` | `$created_at_gt: timestamptz!` | Hasura `invitation` and `invitation_aggregate`; `InvitationRow` selects Hasura beacon/user relationships. |
| `features/inbox/data/gql/inbox_tombstone_dismiss.graphql` / `InboxTombstoneDismiss` | `$dismissedAt: timestamptz!` | Hasura `update_inbox_item`. |

Paths in the table are relative to `packages/client/lib`. None of these operation
names occurs in `_tenturaDirectOperationNames` in
`packages/client/lib/data/service/remote_api_client/build_client.dart`.
`ActivityOffersV2` is a different operation from `ActivityOffers`.

In `hasura/metadata.json`, `metadata.remote_schemas` contains `name: tentura`,
with `definition.customization.type_names.prefix: v2_` and
`definition.forward_client_headers: true`. Hasura exposes the remote schema's
types with that prefix and forwards client headers. Combined with the routing
and selection audit above, there is no current client document mixing one of
these Hasura variable definitions with a Tentura remote-schema operation.
Metadata alone does not reveal the historical caller or prove the contents of a
forwarded request.

## #920 coverage map

| Acceptance item | Evidence / disposition |
| --- | --- |
| Unknown named variable type returns a GraphQL validation response through real HTTP. | `packages/server/test/api/controllers/graphql/unknown_variable_type_http_test.dart`, `returns a validation error identifying the unsupported type`: sends `$t: timestamptz` to `/api/v2/graphql`, requires HTTP 200/400, no data, a type-specific error, and no internal-error code 1000. Uses the real controller, `TenturaGraphQL`, and production version resolver. |
| Benign client input is not captured as an internal error. | Same file, `does not report an unsupported variable type to Sentry`: verifies an active Sentry observer, empty capture for the request, and the validation-response contract independently. |
| Preserve stitched remote-type resolution. | `packages/server/test/api/graphql_upload_type_test.dart` checks `Upload`, `v2_Upload`, `v2_Coordinates`, and intentionally prefixed types. `TenturaGraphQL.convertType` retains the existing alias fallback and raises `GraphQLException` only when a named type remains unresolved. |
| Fix a client operation and guard it if it was the sender. | Out of scope: no current client sender found in the audit above. Keep all three legitimate Hasura operations unchanged. A guard rejecting them globally would be wrong; no currently failing client guard is justified by this evidence. |
| Record caller of the four events. | External/scripted or stale request is the finding supported by elimination above; exact caller remains unverified. Follow-up evidence check: inspect all four original Sentry event payloads and correlated request logs for operation, variable definitions, user agent, and Hasura forwarding headers. |

Verification commands (repository root):

```sh
scripts/run_tests.sh server-files test/api/controllers/graphql/unknown_variable_type_http_test.dart test/api/graphql_upload_type_test.dart
scripts/run_tests.sh server-gates
```

Both passed before this documentation-only update: five targeted tests; server
analyzer count 1835 against unchanged baseline 1835; custom lint count zero.
UI input, phone layout, locale, roles, and freshness matrix cells are not
applicable: this change classifies GraphQL variable-type validation before any
resolver or UI behavior. No client or unrelated #945 files belong to this fix.
