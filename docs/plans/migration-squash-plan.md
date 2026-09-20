# Squashing the server SQL migrations — plan

**Status:** rev 2 — **executed** on 2026-09-20. The owner chose the full squash to
head over the staged cut this document originally recommended, so §3's
recommendation is superseded by §9, which records what was actually done and
what it cost. §§1–2 and §5 stand as written: they are the measurements and the
mechanic, and both survived the change of cut point.

**Scope:** `packages/server/lib/data/database/migration/` and the tests that
reach into it. No client change, no Hasura metadata change, no schema change.

---

## 1. Measured starting state

| Fact | Value |
|---|---|
| Migration files | 196 (`_migrations.dart` + 195 `m*.dart` parts) |
| Registered migrations | 195 (`0001`…`0193`, plus the out-of-band `0161a` and `0163a`) |
| Total SQL statements | 1009 |
| Total lines / bytes | 19 735 lines / 1.1 MB |
| Wall time, full chain on a fresh DB | **1.3 s** |
| Resulting schema | 88 tables, 5 views, 127 functions, 73 triggers, 210 indexes |
| `pg_dump --schema-only` of that schema | 10 213 lines / 334 KB |
| Test files that call `migrateDbSchema*` | 60 |

**The cost is not runtime.** 1.3 s per disposable database is noise next to
everything else a pg test does. The cost is that 1.1 MB of superseded SQL sits
in the read path of anyone trying to answer "what shape is this table", and that
196 files make `migration/` unnavigable. Squashing is a legibility change, and
the plan should be judged as one — it must not be allowed to become a risk
change.

### 1.1 The registry is already not a linear history

Two facts found while measuring, both load-bearing for the design below:

- `m0161a` and `m0163a` are **the same statements** inserted at two different
  points, because `0161a` was added retroactively after databases had already
  passed `0163a`. `m0169` then re-applies `m0162`+`m0163`'s function bodies as a
  forward repair for the databases that took the other branch.
- The local dev database is at head `0193` with **194** version rows; a
  chain-built fresh database has **195**. The one it lacks is exactly `0161a`.

I diffed `pg_dump --schema=public` of the chain-built database against the live
dev database. The only differences are:

1. `public.nested_requests_apply_legacy_cleanup()` — a one-shot `m0158` helper
   that the fresh chain **leaves behind** and the live database does not have;
2. `public.tasks` / `public.tasks_schema_version` — owned by the `pgmer2`
   extension, not by us;
3. `COMMENT ON SCHEMA public`.

**Nothing diverges because of the missing `0161a`.** The `m0169` repair worked
and the head schema is path-independent. That is what makes a baseline
well-defined at all, and it is the single most important precondition here.
It also means item 1 is dead weight the squash should drop rather than inherit.

---

## 2. How migrant decides what to run (the mechanic the whole plan rests on)

From `migrant 0.3.0` + `migrant_db_postgresql 0.3.0`:

- `currentVersion()` is `SELECT version FROM public.schema_version ORDER BY version COLLATE "C" DESC LIMIT 1` — **the maximum, not the set.**
- `Database.upgrade` calls `getInitial()` **only when `currentVersion()` is null**
  (table absent or empty). Otherwise it repeatedly calls
  `getNext(current)` = the first registered migration whose version string sorts
  after `current`.
- Each migration is applied in one transaction, with its `schema_version` row
  inserted first.

Three consequences:

1. **Removing old migration entries cannot affect a database whose `MAX(version)`
   already exceeds them.** A live database at `0193` never looks at the registry
   below `0193`. Historical rows in `schema_version` are inert.
2. **A baseline is only reachable by a database that is empty.** Any database
   sitting *strictly between* the old floor and the new baseline version would
   have the baseline handed to it by `getNext` and would try to `CREATE TABLE`
   over live objects. This is the one way to break production, and §5 is the
   gate against it.
3. **Statements must stay a `List<String>` of single statements.** `migrant`
   calls `ctx.execute(statement)`, which uses the extended protocol (the
   connection's `queryMode` default), and that protocol rejects multi-statement
   strings. Switching the connection to `QueryMode.simple` is not an escape
   hatch: migrant's own `INSERT INTO schema_version … @version` is parameterised
   and simple mode cannot bind parameters.

---

## 3. Where to cut

The registry cannot be squashed past the point the test suite reaches into it.
Two kinds of test pin a version:

- `migrateDbSchemaThrough(conn, v)` — pins `0153, 0154, 0155, 0159, 0160, 0163a,
  0165, 0166, 0167, 0170, 0178, 0179`.
- hand-rolled downgrade scripts that `DELETE FROM public.schema_version` to walk
  a head database backwards and re-upgrade it. Six files do this; the deepest
  (`realtime_notification_migration_test.dart`, 84.5 KB) walks down to `0115`,
  i.e. it needs the database to be able to sit at state **`0114`**.

That fixes the highest zero-rewrite cut point exactly:

### Recommendation: squash `0001`–`0114` into a single `m0114`, now.

- Removes **114 of 196 files** (58%) and the great majority of the superseded
  SQL, including the whole pre-realtime era.
- Breaks **no** behavioural test. Every `migrateDbSchemaThrough` pin and every
  downgrade script still lands at or above `0114`.
- Leaves `0115`…`0193` untouched, so the `0161a`/`0169` repair story and its
  tests keep working unmodified.
- Is repeatable: the same recipe cuts again in a year without new thinking.

Collateral: three tests die, and should simply be deleted rather than ported.
`m0089_backfill_test.dart`, `m0100_dedup_test.dart` and
`m0103_provenance_test.dart` do not touch a database — they `File(...).readAsStringSync()`
the migration source and `expect(source, contains('type = 15'))`. They assert
that a string is present in a file, which is worth nothing once the file is one
of 114 merged into a dump, and was worth little before.

### Alternatives considered

**Squash to head (`0193`), one file, nothing left.** The biggest legibility win
and it permanently ends the `0161a`/`0169` branch. It costs the rework of ~18
tests, including two large ones whose *assertions* are genuinely valuable
(`realtime_notification_migration_test` checks that receipt-shape constraints
reject bad rows and that acknowledgement updates emit exactly one hint — those
are live invariants, only the downgrade/re-upgrade scaffolding is historical).
That rework is real work on an 84 KB and a 23 KB file and it is not what the
user asked for. **Proposed as a separate, later decision (§8), not bundled.**

**Squash to `0152`** (78% of files) is the awkward middle: it breaks all six
downgrade-script tests to gain 38 files over the recommendation. Not worth it.

---

## 4. Producing the baseline

The baseline is generated, never hand-written. Recipe, all of it reproducible:

**4.1 Build the reference database.** A throwaway Dart entrypoint under
`packages/server/tool/` that creates a disposable database, runs
`SET check_function_bodies = false` (required — function bodies reference the
`pgmer2` extension's `mr_*` functions, which do not exist in a fresh database;
this is why a naive `run_migrations_once.dart` against a fresh DB fails with
`42883: function mr_node_score(text, text, text) does not exist`), then calls
`migrateDbSchemaThrough(conn, '0114')`.

**4.2 Dump it.** `pg_dump` is not installed on this machine; use the container:

```bash
docker exec postgres pg_dump -U postgres -d <disposable> \
  --schema-only --schema=public --no-owner --no-privileges
```

**4.3 Strip.** The dump is not directly usable. Remove:

- `\restrict` / `\unrestrict` psql meta-commands (not SQL);
- `SELECT pg_catalog.set_config('search_path', '', false);` — the dump fully
  qualifies everything so it does not need it, but it would persist on the
  connection and break the server afterwards;
- `CREATE TABLE public.schema_version (…)` and its primary key — migrant's
  gateway creates that table itself in `initialize()` before the baseline runs,
  and the dump's version has no `IF NOT EXISTS`;
- `COMMENT ON SCHEMA public`;
- `public.nested_requests_apply_legacy_cleanup()` if the cut ever moves past
  `m0158` (§1.1 item 1). Not applicable at `0114`.

Keep the `SET` preamble lines, including the dump's own
`SET check_function_bodies = false` — they are correct and each is its own
statement.

**4.4 Split.** A dollar-quote-aware splitter, not a split on `;`. 127 function
bodies contain semicolons, `SELECT`, and nested `CREATE TEMP TABLE`. The
splitter must track `$tag$…$tag$`, `'…'` with doubled-quote escapes, `"…"`, and
`--` line comments. Two checks make it falsifiable:

- re-joining the statements with `;\n` reproduces the stripped dump modulo
  whitespace;
- no emitted statement contains an unbalanced dollar-quote tag.

**4.5 Emit** `m0114.dart` as `final m0114 = Migration('0114', [ … ]);`, each
statement an `r'''…'''` raw triple-quoted string, and delete `m0001.dart` …
`m0113.dart` plus their `part` directives and `_allMigrations` entries.

**4.6 Re-seed.** A schema-only dump loses the rows the old migrations inserted.
On a fresh chain-built head database, exactly three tables are non-empty:
`mr_publish_epoch` (1 row), `trust_context_config` (4), `trust_policy` (1).
Check which of those are seeded at or below `0114` and re-add those `INSERT`s
explicitly at the end of the baseline, idempotently (`ON CONFLICT DO NOTHING`).
**This is the most likely thing to be silently got wrong**, because a missing
seed row does not fail the migration — it fails some feature much later.

The 30 migrations containing `INSERT INTO` are mostly backfills over rows that
do not exist on a fresh database, i.e. no-ops; the three tables above are the
ones that actually retain state, and the §5 gate catches any I have miscounted.

---

## 5. Verification gate

Two mechanical checks. Neither is a judgement call.

**G1 — schema equivalence.** Build two disposable databases: one with the old
registry (`git stash` / previous commit), one with the squashed registry. Dump
both with identical `pg_dump` flags, strip the `\restrict` nonce lines, `diff`.
**The diff must be empty.** This is the same comparison I ran in §1.1, so the
method is known to work and known to be clean on this schema.

**G2 — data equivalence.** On both databases, compare
`SELECT relname, n_live_tup FROM pg_stat_user_tables WHERE n_live_tup > 0`
after an `ANALYZE`, and dump the contents of the three seeded tables. Must match.

**G3 — no database is stranded between the floor and the baseline.** Before
merging, confirm every database that will meet the new registry is at
`MAX(version) >= '0114'`:

```bash
docker exec postgres psql -U postgres -d postgres -tAc \
  "SELECT max(version) FROM public.schema_version"   # expect 0193
```

Run this against the dev and production databases. This is the §2 consequence 2
hazard and the only one that can damage a live database. Given both are at
`0193` today, the margin is 79 versions — but it must be *checked*, not assumed,
and checked again at deploy time rather than only at merge time.

**G4 — the suite.** Per `AGENTS.md`:

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
  dart test --tags pg
```

The 156 pg-tagged files are the real gate; they each build the schema from the
registry. Per memory, wrapped test runs must be serial — do not run these two in
parallel.

---

## 6. Units

| # | Unit | Output |
|---|---|---|
| U1 | Generator + splitter under `packages/server/tool/` (`squash_baseline.dart`), with unit tests for the splitter alone | tool, not shipped in the server binary |
| U2 | Generate `m0114.dart`; delete `m0001`–`m0113`; update `part` directives and `_allMigrations` | 114 files removed |
| U3 | Re-seed pass (§4.6) folded into the baseline | idempotent `INSERT`s |
| U4 | Delete `m0089_backfill_test.dart`, `m0100_dedup_test.dart`, `m0103_provenance_test.dart` | 3 files removed |
| U5 | Run G1/G2; iterate on §4.3 strip list until the diff is empty | empty diff, pasted into the commit message |
| U6 | Run G4 | green suite |
| U7 | Docs: `docs/production-deploy.md:210` says "runs all 104 SQL migrations" — already stale at 195, fix to describe the baseline-plus-increment shape | doc fix |

U1–U3 are one commit's worth of mechanical work; U5 is where the time actually
goes.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| A database between the floor and `0114` meets the new registry and the baseline runs over live objects | **high** | G3, re-run at deploy. At `0114` vs a live head of `0193` this is already implausible; it becomes real if §8 ever moves the cut to head. |
| Seed rows lost by the schema-only dump | medium | G2; §4.6 |
| Splitter corrupts a function body | medium | G1 catches it — a mangled body either fails to create or dumps differently |
| `pg_dump` 17.9 emits syntax the server's runtime Postgres rejects | low | same container produces and consumes; G1 proves it applies |
| Lost archaeology — `git log` on a deleted `m0042.dart` still works, but "why is this column here" gets one hop harder | low, accepted | the commit message names the squashed range and the commit that last touched it |

---

## 8. Deferred: squash to head

Not part of this plan. Worth doing once someone is willing to separate the
behavioural assertions in `realtime_notification_migration_test.dart` and
`beacon_cover_migration_test.dart` from their downgrade scaffolding — the
assertions should run against `migrateDbSchema` on a fresh database, and the
`DELETE FROM public.schema_version` walk-backs should be deleted outright, since
after a head baseline no database will ever take those upgrade paths again.
The remaining `migrateDbSchemaThrough` pins (`0153`…`0179`) are each a
before/after pair around one migration and would have to be rewritten as direct
assertions on the final shape, or dropped.

Doing that first, then squashing to head, would leave `migration/` as two files.
It is the right end state; it is just not the cheap half.


---

## 9. What was done (rev 2)

The cut is at head. `m0001`–`m0192`, `m0161a` and `m0163a` are gone; the registry
is `final _allMigrations = <Migration>[m0193];` and `migration/` holds two files.

| | before | after |
|---|---|---|
| Files in `migration/` | 196 | 2 |
| Registered migrations | 195 | 1 |
| Lines | 19 735 | 8 191 |
| Bytes | 1.1 MB | 265 KB |
| SQL statements | 1009 | 748 |

The baseline is generated, not written: `packages/server/tool/squash_baseline.dart`
builds a disposable database from the registry, dumps `public` with `pg_dump`
inside the Postgres container, strips, splits and emits the part file. Re-run it
against a future chain to squash again.

### 9.1 What the generator had to handle

Four things the plan named as risks, and one it did not:

1. **Splitting.** Semicolons live inside 127 function bodies, so the splitter
   tracks dollar quotes, `'…'` with doubled-quote escapes, `"…"`, `E'…'`
   backslashes and both comment forms. It asserts the split reproduces the dump.
2. **`CREATE SCHEMA public`.** `pg_dump` 17 emits it bare; `CREATE DATABASE`
   inherits `public` from `template1`, so applying the baseline failed with
   `42P06: schema "public" already exists`. Rewritten to `IF NOT EXISTS`, which
   is what `m0001` said.
3. **`schema_version`.** Dropped from the dump — migrant's gateway creates it in
   `initialize()` before the baseline runs, and the dump's `CREATE TABLE` has no
   `IF NOT EXISTS`.
4. **`search_path`.** `SELECT pg_catalog.set_config('search_path', '', false)`
   dropped; it would persist on the connection the server goes on to use.
5. **Comments inside function bodies** (not anticipated). The first splitter
   stripped every `--` line, including documentation inside `$$…$$`. Postgres
   stores `prosrc` verbatim and dumps it back, so the rebuilt schema differed by
   exactly those comment lines — caught by G1, fixed by stripping only the
   leading banner.

### 9.2 Gates

Both hold, and both are re-runnable:

```bash
cd packages/server
dart run tool/squash_baseline.dart --version 0193 \
  --db tentura_test_squash_verify --verify-against <chain-dump>.sql
```

- **G1 (schema).** The schema the squashed registry builds is **character-identical**
  to the dump of the chain it replaced. Not "equivalent" — identical.
- **G2 (seeds).** A schema-only dump carries no rows, so the three tables the
  chain seeded (`mr_publish_epoch`, `trust_policy`, `trust_context_config`) are
  re-seeded by statements transcribed from `m0122`/`m0142`, not captured by
  `pg_dump --data-only` — a data dump would have baked this machine's
  `DEFAULT now()` timestamps into every future deployment. The generator refuses
  to run if the chain leaves any other table non-empty.
- **G3 (no stranded database).** Still the only way to damage a live database,
  and now with no margin at all: the baseline's version *is* head. Any database
  below `0193` that meets this registry gets the baseline from `getNext` and
  creates objects over live ones. Dev and production were both at `0193` when
  this was written. **Check again at deploy:**
  `SELECT max(version) FROM public.schema_version` must be `0193`.

### 9.3 Test fallout

Ten files deleted, eight rewritten. Three of the deletions were already fully
skipped with the reason *"Disabled for the planned schema squash cutover"* —
someone had staged this.

**Deleted** — all of them tested upgrades between schemas that no longer exist:
`realtime_notification_migration_test.dart` (84.5 KB, skipped),
`beacon_cover_migration_test.dart` (skipped),
`m0149_resolution_removal_migration_test.dart` (skipped),
`nested_requests_cleanup_pg_test.dart`, `m0187_first_entry_backfill_pg_test.dart`,
`constellation_migration_repair_pg_test.dart`,
`constellation_migration_order_test.dart`, and the three source-text tests
`m0089_backfill_test.dart`, `m0100_dedup_test.dart`, `m0103_provenance_test.dart`,
which asserted that strings appeared in files rather than that anything worked.

**Replaced:**

- `schema_baseline_pg_test.dart` — new, carries the live assertions from the
  retired repair test: the read wall and trust-edge function are installed and
  callable, the direct-trust trigger exists, the seeds are present, and the
  registry records exactly one version.
- `migration_registry_test.dart` — new, keeps the invariant the squash depends
  on: versions must increase in list order, or migrant silently skips one. The
  `0161a` case that made this sharp is gone; the next migration can reintroduce
  it.

**Rewritten in place** — each kept its schema-shape or behavioural assertions and
lost only the upgrade scaffolding: `attention_additive_schema_pg_test.dart`,
`attention_receipt_identity_index_pg_test.dart`,
`settlement_kind_constraint_pg_test.dart`, `beacon_discoverability_pg_test.dart`,
`constellation_anchor_storage_pg_test.dart`, `beacon_ancestor_pg_test.dart`,
`beacon_hierarchy_outbox_pg_test.dart`, `m0141`/`m0142`/`m0143`/`m0148` tests.
Two tests that read migration *source files* now read the installed function
definition with `pg_get_functiondef` instead, which is a better assertion than
the one they replaced. `realtime_entity_contract_test.dart` reads the baseline
instead of six named migration files.

The two "re-applying every mNNNN statement is a no-op" tests could not be
carried over honestly: the baseline is not idempotent by construction —
`pg_dump` emits bare `CREATE`s — and migrant applies it once. Their schema-shape
assertions were kept and the replay dropped.

### 9.4 Known leftover

`public.nested_requests_apply_legacy_cleanup()` is a one-shot `m0158` helper.
`m0158` defines it and then, as its own last statement, calls it:
`SELECT public.nested_requests_apply_legacy_cleanup();`. So it ran automatically,
once, inside the transaction that took a database across `0158`. No application
code has ever called it; `m0158` left it defined on purpose, so it could be
re-invoked by hand ("Idempotent in shape … subsequent passes delete/update zero
rows").

The baseline carries the **definition** and not the call, which is correct: a
fresh database has no legacy rows to clean, so the invocation would be a no-op.
Nothing else references it, and the only test that did was deleted with the rest
of the `m0158` coverage. It was kept rather than stripped because dropping a
schema object is a different change from a squash and would have made G1's
"identical" claim conditional.

**Dropped by `m0195` (2026-09-20).** Not by stripping it from `m0193` and
regenerating, which is what this section first suggested — that advice was wrong
once `m0193` shipped, for the same reason §10.2 documents: editing a migration
that has shipped reaches only the databases that have not yet applied it, and
both deployments already had the function. `m0195` is a plain
`DROP FUNCTION IF EXISTS`, a no-op wherever it is already absent. A later
regeneration of the baseline will not contain the function anyway, because the
database it dumps will have run `m0195`.

Verified before dropping: no Dart, SQL or Hasura reference; no other function
body mentions it; `pg_depend` reports no dependents on either deployment.
`schema_baseline_pg_test` asserts a fresh database ends up without it, and
`m0194_drift_reconciliation_pg_test` asserts a database at `0193` has it and no
longer does after the registry runs.

**Unexplained, and not caused by the squash.** The local dev database has `0158`
stamped (2026-09-06 17:39) but does *not* have the function, while a chain-built
database does. No migration drops it, and all three commits that touched
`m0158.dart` define it — the first is titled "salvage Task 09 partial work",
which suggests that database ran an uncommitted intermediate form of the
migration. Whether the cleanup itself actually ran there is a separate question
about that one database, worth answering before trusting its contents, and it
says nothing about a production deployment, which was not inspected.


---

## 10. Live-database drift found while checking §9.4 (2026-09-20)

Checking whether `m0158`'s cleanup had actually run on the deployed databases
answered that question — and turned up unrelated drift that the squash does not
cause and cannot fix.

### 10.1 The cleanup did run

Both deployments are clean. `coordination_item` with `kind IN (2,3,5)` and
`beacon_room_message` with `thread_item_id IS NOT NULL` — the two doomed sets
`nested_requests_apply_legacy_cleanup()` snapshots — are **0 rows on both**, and
the function is present on both.

| | `dev.tentura.io` | `ssh.tentura.io` (prod) |
|---|---|---|
| `schema_version` rows | 192 | 195 |
| max version | `0193` | `0193` |
| `0158` applied | 2026-09-07 12:24 | 2026-09-20 10:06 |
| cleanup function present | yes | yes |
| legacy coordination items | 0 | 0 |
| legacy thread messages | 0 | 0 |

Dev lacks `0161a`, `0162`, `0163` — the branch of §1.1, reconverged by `m0169`.
Prod has all three. Both are at `0193`, so both skip the baseline.

The local dev database on the developer machine is a third case: it has `0158`
stamped but no cleanup function, which §9.4 attributes to an uncommitted
intermediate form of `m0158`. It is not either deployment and nothing depends on
it.

### 10.2 Drift from what the chain builds

Below, "the chain is wrong" and "the deployment is wrong" both occur — the
direction has to be decided per item against what the application expects, not
assumed.

`pg_dump --schema=public` of each deployment against the chain-built reference,
ignoring `pgmer2`'s own tables and Hasura console trigger comments:

**Both deployments**

- A stale `emit_realtime_entity_change(text, text, text, text[])` survives.
  `m0133` drops that signature and creates a 5-argument replacement; both hosts
  carry **two** overloads where a fresh build has one. Overload resolution
  therefore differs between a deployed database and a new one.
- `notification_preference` defaults differ from the chain: `email_categories`
  has an extra `'coordination'` and `email_digest` defaults to `'daily'`, where
  `m0111`/`m0095` produce `ARRAY['asksOfMe','connections']` and `'off'`.
  **Here the deployments are right and the chain is wrong.** Version `0123` used
  to be "default email digest on (daily) + coordination into email categories";
  it was later *repurposed* for the beacon-visibility change that occupies
  `m0123` now, taking those defaults out of the chain entirely. Both deployments
  stamped `0123` while it was the preferences migration. The values they kept are
  the ones `NotificationPreferencesEntity.defaults` documents ("email for
  asksOfMe / connections / coordination …; digest daily").

**Prod only, and this one has a user-visible consequence**

`public.on_user_created()` on prod is **`m0003`'s body** — it inserts into
`user_vsids` and stops. `m0007` replaces that function to also insert into
`user_presence`, and prod records `0007` as applied 2026-06-28 19:12, ten months
after that line landed (commit `3ef84a0ab`, 2025-08-13, which edited the
already-shipped `m0007` in place). `m0007`'s tables (`fcm_token`,
`user_presence`) do exist on prod, so the migration ran.

Result: `public.user_presence` on prod holds **0 rows for 4 users**, and every
new prod signup gets none. Dev's trigger is correct and its 234 presence-less
users all predate 2025-11-07, so dev's gap is historical backlog, not ongoing.

**Unexplained.** No migration after `0007` mentions `on_user_created`, and
migrant stamps the version inside the migration's own transaction, so a
partially-applied `m0007` could not have committed. Something replaced the
function on prod after `m0007` ran, or the ledger was written independently of
the schema. This was not chased further.

### 10.3 Why it matters here

Both deployments are at `0193`, so they skipped every migration below it before
this squash and will skip the baseline after it. The squash neither introduces
nor repairs any of the above. What it does change is that there is no longer a
chain to replay against a drifted database — the only forward path is a new
migration above `0193` that asserts the intended state. Concretely, prod's
trigger needs one:

```sql
CREATE OR REPLACE FUNCTION public.on_user_created() ...  -- m0007's body
INSERT INTO public.user_presence (user_id)
  SELECT id FROM public."user" ON CONFLICT (user_id) DO NOTHING;
```

See §11 — this was written as `m0194`.

**Process note.** Two of the three drift items trace to migrations being edited
after they shipped (`m0007` here, `m0158` in §9.4). migrant never re-runs a
stamped version, so an in-place edit silently applies only to databases that had
not yet reached it. The squash removes the edit target for everything at or below
`0193`, which makes the failure mode harder to reintroduce below the baseline —
and no harder above it.


---

## 11. The reconciliation migration (`m0194`)

`m0194` is the forward path §10.3 called for. Every statement is a no-op on a
database that is already correct, because the drift is per-deployment and there
is no longer a chain to replay.

| § | Statement | Fixes |
|---|---|---|
| 1 | `DROP FUNCTION IF EXISTS public.emit_realtime_entity_change(text, text, text, text[])` | both deployments |
| 2 | `CREATE OR REPLACE FUNCTION public.on_user_created()` — `m0193`'s body, byte-identical | prod |
| 3 | `INSERT INTO public.user_presence (user_id) SELECT id FROM public."user" ON CONFLICT DO NOTHING` | prod (4 accounts), dev (234 historical) |
| 4 | `ALTER COLUMN email_digest SET DEFAULT 'daily'` | the chain / every future database |
| 5 | `ALTER COLUMN email_categories SET DEFAULT ARRAY['asksOfMe','connections','coordination']` | the chain / every future database |

§2's body is copied from `m0193` character for character, so re-issuing it on a
correct database does not even change `prosrc`.

### 11.1 What it deliberately does not do

The original `m0123` also carried row backfills:
`UPDATE … SET email_digest = 'daily' WHERE email_digest = 'off'` and an
`array_append` of `'coordination'`. Those already ran on both deployments.
Re-running them would **re-subscribe every account that has since opted out** —
`UnsubscribeCase` writes exactly the `'off'` the first statement would overwrite.
`m0194` restates the column defaults and touches no preference row.
`m0194_drift_reconciliation_pg_test.dart` asserts that an opted-out account stays
opted out.

### 11.2 Verification

- A baseline database wound back to prod's exact shape (both overloads,
  `m0003`'s trigger, the chain's defaults, one account created under the broken
  trigger) converges on all four items, and a signup after the migration gets a
  presence row. This is `m0194_drift_reconciliation_pg_test.dart`, and it asserts
  the fixture is drifted before asserting the fix, so it cannot pass vacuously.
- On a clean build the whole registry differs from the pre-`m0194` reference dump
  by **exactly two lines** — the two defaults. Nothing else moved.
- Server suites: 1688 non-pg green, custom lints 0, pg 1066 green — with the two
  §11.4 test fixes in place. The pg suite is intermittently red on a developer
  machine either way; §11.5 measures that against unmodified `HEAD`.

`m0194` has not been deployed. It applies on the next server start, which is when
the §5 G3 check matters: both deployments must still read `0193` as their max
version, or something else has touched them since 2026-09-20.

### 11.3 Cosmetic difference left alone

Prod's MeritRank init function differs from the chain's only in line wrapping and
comments — identical SQL, different `prosrc`. It is not worth a statement in a
migration, and re-issuing a 60-line body to normalise whitespace risks more than
it fixes.

### 11.4 Two pre-existing tests that break when the pg suite gets busier

The first full pg run after `m0194` failed
`capability_evidence_repository_pg_test.dart` → *"upsertSeedAttestation
serializes disjoint complete replacements via pair lock"* with
`TimeoutException after 0:00:05: predicate not satisfied`. It passed on its own,
so it looked like a flake; it then failed on every full-suite run, where the run
before `m0194` had been green. Neither reading was right.

Bisecting settled it in two runs:

- `m0194` in the registry, the new test file removed → **green** (1061, the
  pre-`m0194` figure). The migration is not involved.
- The new test file replaced by a *trivial* probe — one disposable database, one
  schema upgrade, one `SELECT 1` → **the same failure**, plus a second one. So it
  is not that test either: one more pg file of any kind is enough.

**The real bug.** That test waits for its own blocker to take the cell lock by
polling

```sql
SELECT 1 FROM pg_locks WHERE locktype = 'advisory' AND granted = false
```

`pg_locks` reports the whole cluster, and `migrateDbSchema` takes a blocking
advisory lock (`tentura_schema_upgrade`, §2). So any *other* disposable database
waiting to migrate satisfies that poll. The test then stops waiting before its
blocker is in place, the second upsert completes before the next poll can catch
it mid-flight, and that poll spins to its five-second timeout. More concurrent
migrations, more false positives — which is why it tracked load so precisely.
Fixed by scoping the query to `current_database()`.

**The second one.** `m0143_capability_evidence_sql_test.dart` asserted
`closeTo(1.0, 1e-9)` on `s_seed`, a value that decays with wall-clock time since
`created_at`; a slower run drifts past it (observed: `0.9999999985563891`). The
sibling assertion three lines above already used `1e-4`. Matched to it — the
claim is which bucket the mass lands in, not nine decimal places.

Both are pre-existing and neither is caused by the squash or by `m0194`; they
were simply never exercised with one more pg file in the suite.

The drift test was also rebuilt along the way, from a per-test `setUp` fixture
(five disposable databases, nine schema upgrades) to a single `setUpAll` (one
database, two upgrades). That did not fix the failure — the probe run proved the
cost was never the trigger — but it is the right shape for a pg fixture and it
is what shipped.



### 11.5 The pg suite is intermittently red before this change too

Two of the three post-fix full runs were green; the red one failed
`person_visibility_repository_pg_test` and `user_block_graph_enforcement_pg_test`
— both MeritRank-dependent, and MeritRank is a **single shared service** across
every disposable database, so tests can see each other's graph state. That is a
third interference source, untouched here.

Rather than assert it was pre-existing, it was measured. A detached worktree at
unmodified `HEAD` (196 migrations, no `m0194`, no test changes) was built with
`dart pub get` + `build_runner` and run three times against the same Postgres:

| | pristine `HEAD` | this branch |
|---|---|---|
| run 1 | −3, all `JWT_PUBLIC_PEM … required` | green |
| run 2 | −1 `forward_edge_repository_create_batch_dedup_test` | −2 MeritRank tests |
| run 3 | green | green |

`HEAD` run 1's three failures are an artifact of the worktree, not of the code:
the repo-root `.env` is gitignored, so it was absent until it was copied in.
`HEAD` run 2's failure is the real signal — `duplicate key value violates unique
constraint "user_public_key_key"`, a fixture collision between tests, on code
this branch does not touch.

So: one genuine intermittent failure in three runs on `HEAD`, one in three on
this branch, and a different test each time. The squash and `m0194` did not
introduce this; the two fixes in §11.4 removed two of its causes. Treat a single
full-suite pg result on a developer machine accordingly.

**Also environmental:** stale `tentura_test_*` databases accumulate — 113 were
found — and slow every `CREATE DATABASE` the suite issues. One run with them
present took 4:35 against the usual 3:30 and failed five scattered tests with
30-second timeouts. `run_with_test_cleanup.sh` sweeps `/tmp` kernel files but not
databases, so this recurs; drop them before trusting a suite result.
