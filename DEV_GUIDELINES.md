# Development guidelines

Project-specific conventions beyond what lives in `.cursor/rules/`.

## Initial load on detail and list screens (spinner)

When a screen's cubit loads data asynchronously after navigation, the first frame must not paint "success" UI built from empty or placeholder domain objects (that causes wrong actions, empty titles, and layout flashes).

**Do this:**

1. **State** — Start with `status: StateStatus.isLoading` (or equivalent) until the first fetch completes. Do not default to `StateIsSuccess()` while `beacon`, `author`, or similar fields are still placeholders.
2. **Body** — Use `BlocBuilder` with `buildWhen: (_, c) => c.isSuccess || c.isLoading` (or a superset that includes loading when the UI must react). When `state.isLoading`, show:

   ```dart
   const Center(
     child: CircularProgressIndicator.adaptive(),
   )
   ```

3. **Consistency** — Follow the same pattern as `InboxScreen`, `MyFieldScreen`, `MyWorkScreen`, `RatingScreen`, and `BeaconViewScreen`. A thin linear progress indicator under the app bar can supplement this for in-place reloads; it is not a substitute for hiding bogus content on the **initial** load.

**Rationale:** A centered adaptive progress indicator is the project default for \u201cdata not ready yet.\u201d It avoids rendering ownership-specific controls (e.g. Commit vs owner actions) against `Profile()` / empty ids.

## Ferry custom scalars (Hasura)

Every Hasura `scalar` type that appears in query **responses** must have a
`type_overrides` entry in **both** `ferry_generator|graphql_builder` and
`ferry_generator|serializer_builder` in `packages/client/build.yaml`.

Without an override Ferry generates a `G<Scalar>` wrapper class whose
`DefaultScalarSerializer` casts the raw JSON value to `String?`.
This works only when the wire format is already a string (e.g. `uuid`).
For numeric scalars (`smallint`, `float8`) Hasura sends JSON integers /
numbers, so the cast crashes silently and the Ferry stream never emits \u2014
resulting in hanging Futures and infinite spinners.

| Scalar | Dart type | Needs custom serializer? |
|--------|-----------|--------------------------|
| `timestamptz` | `DateTime` | Yes (`TimestamptzSerializer`) |
| `smallint` | `int` | Yes (`SmallintSerializer`) — see below |
| `float8` | `double` | Yes (`Float8Serializer`) — see below |
| `uuid` | `String` | No |
| `Upload` | `MultipartFile` | Yes (`UploadSerializer`) |

**Why `smallint` and `float8` still need serializers after `type_overrides`:** mapping
them to `int` / `double` fixes Ferry’s broken `G<Scalar>` wrappers for **typical**
Hasura responses (JSON numbers). MeritRank plugin fields (`mr_*` functions) feed
computed relationships such as `mutual_score` (`user.scores`, `beacon.scores`, …).
For those paths Hasura often emits `float8` (and sometimes `smallint`) as **JSON
strings** (e.g. `"95"`). `built_value` then expects a `num` and throws
`String is not a subtype of num`. `Float8Serializer` and `SmallintSerializer`
deserialize both wire shapes: register them under `custom_serializers` in
`ferry_generator|serializer_builder` only (see `packages/client/build.yaml`).
Details: `packages/server/WORKAROUNDS.md` section 3.

When adding a **new** Hasura custom scalar to the schema, add the
corresponding `type_overrides` entry before running codegen.
If the Dart type is not a JSON primitive, or the same GraphQL scalar can arrive
as both number and string (MeritRank / computed fields), also add a
`custom_serializers` entry (see `TimestamptzSerializer`, `Float8Serializer`).

## V2 direct routing (client → Tentura, bypassing Hasura)

Operations implemented on the Tentura V2 server must be called at
`/api/v2/graphql`. The client’s `_V2RoutingLink` in
`packages/client/lib/data/service/remote_api_client/build_client.dart`
routes by **operation name**: if the name is in `_tenturaDirectOperationNames`,
the request goes to V2; otherwise it goes to Hasura V1 (`/api/v1/graphql`).

When adding a new V2 server query or mutation:

1. Add the client-side **operation name** (from the `.graphql` file) to
   `_tenturaDirectOperationNames` in `build_client.dart`.
2. Ensure the V2 GraphQL schema defines every type and field the client selects.
   If the query uses shared fragments (e.g. `UserModel` on `user`), V2 must
   expose matching GraphQL types and field names (aligned with Hasura’s schema
   from which Ferry is generated).
3. No Caddy change is required for routing: `/api/v2/graphql` is already
   proxied to Tentura in production (`Caddyfile`) and in local web dev
   (`packages/client/web_dev_config.yaml`).
