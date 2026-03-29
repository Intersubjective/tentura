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
