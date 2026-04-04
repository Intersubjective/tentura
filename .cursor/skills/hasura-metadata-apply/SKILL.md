---
name: hasura-metadata-apply
description: >-
  Applies Hasura metadata changes (track tables, relationships, permissions)
  by editing hasura/metadata.json and running scripts/hasura_apply_metadata.sh
  against local dev compose. Use when tracking a new Postgres table in Hasura,
  adding relationships or permissions, or when the user asks to update Hasura
  metadata.
---

# Hasura metadata apply

## Overview

This project manages Hasura metadata as a single JSON file (`hasura/metadata.json`).
Changes are applied via `replace_metadata` through `scripts/hasura_apply_metadata.sh`.

## When to apply

- Tracking a new Postgres table in Hasura.
- Adding an object or array relationship on an existing tracked table.
- Changing select/insert/update/delete permissions for a role.
- User says "update Hasura", "track table", "add relationship", or "apply metadata".

## Workflow

### 1. Edit metadata

Edit `hasura/metadata.json` (Hasura v2 metadata format, version 3).

**Track a new table** — add an entry to `metadata.sources[0].tables`:

```json
{
  "table": { "name": "my_table", "schema": "public" },
  "object_relationships": [],
  "select_permissions": [
    {
      "role": "user",
      "permission": {
        "columns": ["col_a", "col_b"],
        "filter": {}
      }
    }
  ]
}
```

**Add object relationship** (e.g. 1:1 via FK on child table):

```json
{
  "name": "my_table",
  "using": {
    "foreign_key_constraint_on": {
      "column": "parent_id",
      "table": { "name": "my_table", "schema": "public" }
    }
  }
}
```

**Add array relationship** (parent → children via FK on child):

```json
{
  "name": "children",
  "using": {
    "foreign_key_constraint_on": {
      "column": "parent_id",
      "table": { "name": "child_table", "schema": "public" }
    }
  }
}
```

### 2. Validate JSON

```bash
python3 -m json.tool hasura/metadata.json > /dev/null
```

### 3. Apply to local Hasura

```bash
./scripts/hasura_apply_metadata.sh
```

Default endpoint: `http://127.0.0.1:8080` (compose.dev.yaml).
Default admin secret: `password`.

Override with env vars:

```bash
HASURA_URL=http://127.0.0.1:8080 HASURA_GRAPHQL_ADMIN_SECRET=mysecret ./scripts/hasura_apply_metadata.sh
```

The script uses `jq` (required dependency). It:
1. Extracts `.metadata` from the JSON file.
2. Sends `replace_metadata` to `/v1/metadata`.
3. Checks HTTP 200, no `.error`, and `is_consistent == true`.

### 4. Update client schema

After Hasura accepts metadata, re-introspect if the client's `schema.graphql` needs new types. The compose dev stack includes an introspection service, or run manually:

```bash
get-graphql-schema -h 'x-hasura-admin-secret=password' -h 'x-hasura-role=user' \
  http://localhost:8080/v1/graphql > packages/client/lib/data/gql/schema.graphql
```

Then run Ferry codegen:

```bash
cd packages/client && dart run build_runner build -d
```

### 5. Bump resource_version

Increment `resource_version` at the top of `metadata.json` after each change (convention only; Hasura ignores it on `replace_metadata` but it helps track edits).

## Key conventions

- **Permissions**: most tables use `"filter": {}` (public read) for `role: user`. Tables with user-scoped data use `"filter": { "user_id": { "_eq": "X-Hasura-User-Id" } }`.
- **Relationship naming**: matches Postgres table name in snake_case (e.g. `beacon_review_window`).
- **Computed fields**: require `session_argument` and often `table_argument`; see existing examples in `metadata.json`.
- **replace_metadata** replaces everything: always edit the full `metadata.json`, never partial API calls.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `is_consistent: false` | Table or FK doesn't exist in Postgres; run migrations first. |
| HTTP 401 | Wrong admin secret; check `HASURA_GRAPHQL_ADMIN_SECRET`. |
| `jq: command not found` | Install jq: `sudo apt install jq`. |
| New field returns null in client | Ensure `schema.graphql` has the type and the `.graphql` fragment selects it; re-run codegen. |
