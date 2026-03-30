# Server Workarounds

## 1. graphql_server2: nullable arguments reject null values

**Library:** `graphql_server2` 6.5.0 (latest as of 2026-03)
**File:** `lib/api/controllers/graphql/schema.dart`
**Class:** `_NullSafeGraphQL`

### Bug

`GraphQL.coerceArgumentValues` calls `argumentType.validate(name, value)` for
every argument that appears in the query, even when the resolved value is
`null` and the argument type is nullable. Scalar `validate` methods
(e.g. `graphQLString`) check `input is String`, which is `false` for `null`,
so validation fails with:

```
Type coercion error for value of argument "context" of field "beaconForward". (null)
Expected "context" to be a string.
```

Per the GraphQL spec, nullable arguments must accept `null` without
validation. The library never implemented this check.

### Affected scenario

Any mutation or query with a nullable scalar argument (e.g. `context: String`)
that receives a `null` value from a client variable (e.g. `context: $context`
where `$context` is not provided or explicitly `null`).

### Workaround

Subclass `GraphQL` and override `coerceArgumentValues`. The override is an
exact copy of the base method with one added check after resolving the
input value:

```dart
if (inputValue == null && argumentType is! GraphQLNonNullableType) {
  coercedValues[argumentName] = null;
  continue;
}
```

This skips validation for null values on nullable types, matching the
GraphQL spec behavior.

### Removal condition

Remove `_NullSafeGraphQL` and revert to plain `GraphQL(...)` when
`graphql_server2` ships a version that handles null values for nullable
arguments correctly in `coerceArgumentValues`.

---

## 2. graphql_schema2: `.nonNullable()` on `GraphQLListType` causes TypeError

**Library:** `graphql_schema2` 6.5.0 (latest as of 2026-03)
**File:** `lib/api/controllers/graphql/input/input_field_recipient_ids.dart`
**Rule:** `.cursor/rules/quick-reference.mdc` → "Server GraphQL (graphql_schema2)"

### Bug

`GraphQLNonNullableType<List<T>, List<T>>.validate` has a Dart-typed
parameter `List<T> input`. JSON-decoded lists are always `List<dynamic>` at
runtime. Calling `validate` with `List<dynamic>` throws a `TypeError`:

```
type 'List<dynamic>' is not a subtype of type 'List<String>' of 'input'
```

This only affects **list** arguments wrapped in `.nonNullable()`. Scalar
`.nonNullable()` types use untyped `dynamic input` and work fine.

### Workaround

Never call `.nonNullable()` on `GraphQLListType`. Define list arguments as:

```dart
GraphQLListType(graphQLString.nonNullable())   // [String!], list itself nullable
```

Enforce list non-null at the resolver layer via `fromArgs`:

```dart
static List<String> fromArgs(Map<String, dynamic> args) =>
    List<String>.from(args[_fieldKey]! as List);
```

This pattern is encapsulated in `InputField*` classes (see
`InputFieldRecipientIds`, `InputFieldPolling`).

### Removal condition

Remove the pattern and use `.nonNullable()` on list types when
`graphql_schema2` changes `GraphQLNonNullableType.validate` to accept
untyped `input` (or `Object?`) instead of `Serialized input`.

---

## 3. Hasura / MeritRank: `float8` (and sometimes `smallint`) as JSON strings in responses

**Client:** `packages/client/lib/data/gql/float8_serializer.dart`,
`packages/client/lib/data/gql/smallint_serializer.dart`,
`packages/client/build.yaml` (`custom_serializers` under
`ferry_generator|serializer_builder`)
**Server DB:** computed fields that `RETURNS SETOF mutual_score` and call MeritRank
`mr_*` functions (`mr_node_score`, `mr_neighbors`, `mr_mutual_scores`, `mr_graph`,
`mr_scores`, etc.) — see migrations in `lib/data/database/migration/`.

### Issue

For ordinary table columns, Hasura usually serializes PostgreSQL `float8` as JSON
numbers. For **computed** `mutual_score` rows produced by MeritRank (`mr_*`),
responses often contain `src_score` / `dst_score` as **quoted strings** (e.g.
`"95"`) instead of numbers. After mapping GraphQL `float8` → Dart `double` via
Ferry `type_overrides`, `built_value` deserialization fails with:

`TypeError: "95": type 'String' is not a subtype of type 'num'`.

The same inconsistency can theoretically affect `smallint` in similar paths.

### Workaround (client)

Keep `type_overrides` for `smallint` → `int` and `float8` → `double`, and register
`Float8Serializer` and `SmallintSerializer` as Ferry `custom_serializers`. They
accept both JSON numbers and numeric strings.

### Removal condition

Remove the serializers if Hasura (or the MeritRank integration) consistently
returns numeric JSON for these scalars everywhere, and no query still receives
string-encoded values — then verify with `FriendsFetch` / `UserModel.scores` and
other selections that include `mutual_score`.

---

## 4. Hasura: `inbox_item.inbox_provenance_data` computed field

**Migration:** `m0015` defines `public.inbox_item_inbox_provenance_data(inbox_row, hasura_session)`.

**Deploy:** In Hasura Console, add a computed field on table `inbox_item`:

- Name: `inbox_provenance_data`
- Definition: SQL function `inbox_item_inbox_provenance_data`
- Session argument: `hasura_session` → `Hasura-Session-Variable`

Reload metadata and re-introspect the client `schema.graphql` if the field type differs from `String`.
