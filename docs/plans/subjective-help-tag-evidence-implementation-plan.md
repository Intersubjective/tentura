# Subjective Help-Tag Evidence — Implementation Plan

**Revision:** rev 6 — five adversarial passes: three by codex, plus an independent multi-model pass by **Grok 4.5, Gemini 3.6 Flash and Kimi K3** reviewing the same prompt without knowledge of each other's findings. Headline changes: **D23's per-request budget withdrawn** as non-monotone (an unadmitted co-acknowledger erased evidence a trusted witness supplied); **tier precedence re-derived as channel-first** (`ownOutcome > networkOutcome > ownRouting > networkSeed`) after splitting Tier A by channel inverted "seed is weaker than outcome"; **C5's acceptance grep replaced** — it could not detect its own target, because `fetchCues` binds `source_type` as a parameter rather than a literal; **half-lives in seconds** (a `…Days` constant in a `_half_life_seconds` parameter silently gives the system a six-minute memory); **C4 re-anchored to `invite_genealogy`** because `bindMutual` deletes the invitation row mid-acceptance; **admission policy moved out of SQL** into a pure Dart function with the port returning raw facts plus the unbounded trusted population; D12's cap per-evaluator at submission and beacon-wide at finalization; MR-epoch bumps moved inside SQL and extended to every publisher; batch block queries to avoid N+1; migrations renumbered contiguously; G1 and G3 split.
**Audience:** implementation workers (Cursor CLI, composer-2.5), **one bounded unit per fresh session**, no memory of other units.
**Design authority:** [`subjective-help-tag-evidence-architecture.md`](subjective-help-tag-evidence-architecture.md) rev 4 — read it for *why*; this plan gives *what* and *where*.
**Live-code authority:** the repository wins over both.
**Shared journal:** `docs/plans/subjective-help-tag-evidence-implementation-journal.md`. Create it if absent (unit A0). Read it fully before editing; append a checkpoint on meaningful progress and a final entry before exit.

---

## 0. Reading order for a worker

1. `AGENTS.md`, `.claude/skills/clean-architecture/SKILL.md`, `.cursor/rules/architecture.mdc`
2. The journal, in full
3. §1 (orientation facts), §2 (global rules), §3 (decisions) of this document
4. Your assigned unit — including its **Preconditions** block
5. Implement, verify, commit per coherent step, journal, exit

**Implement only your assigned unit.** If you find another unit incomplete, record it in the journal; do not fix it.

**Stop-and-report rule:** if a fact in your unit's **Preconditions** is false in the tree, stop and report.

§1 facts are *orientation*, not gates — rev 2 claimed no unit changes them and was wrong three times over (A1 changes the source enum, C3 changes `createBatch`'s return contract, F3 changes the `viewerVisible` flow). A §1 row that looks stale is expected if an earlier unit owns it; check §4's ownership column before treating it as a contradiction, and only stop if no unit claims that change.

---

## 1. Orientation facts

Facts marked **[changed by X]** are true *before* unit X runs and are that unit's to change.

| Fact | Value |
|---|---|
| Migration registration | `packages/server/lib/data/database/migration/_migrations.dart` — requires **both** a `part 'mNNNN.dart';` line **and** an entry in the ordered list. |
| SQL mirror | `sql/triggers.sql` mirrors **only** functions extracted from m0002/m0003/m0005 (see its header). It is **not** a complete mirror — m0140's four visibility functions, including `person_visibility_peers`, are absent. Add new functions to it only when a unit says so; do not treat divergence as a contradiction. |
| Advisory lock idiom | `pg_advisory_xact_lock(hashtextextended(<text key>, 4242))` — `m0122.dart:167`. Transaction-scoped. |
| Unit of work | `MutatingUnitOfWorkPort.run({action, actorUserId})` — `domain/port/mutating_unit_of_work_port.dart`. |
| Mutating-user GUC | `_database.withMutatingUser(userId, fn)`. **Nesting with a *different* actor throws.** Same-actor nesting is safe. |
| Ledger table | `person_capability_event` (m0048). No CHECK on `source_type` before A1. |
| Source enum **[changed by A1]** | `packages/server/lib/domain/capability/capability_event_source.dart` — `privateLabel(0)`, `forwardReason(1)`, `commitRole(2)`, `closeAcknowledgement(3)`. A1 adds `seedRoutingAttestation(4)`. |
| Taxonomy | 37 slugs; server `domain/capability/capability_tag.dart` (`kAllowedCapabilitySlugs`), client `lib/domain/capability/capability_tag.dart`. |
| Evaluation values | `noBasis=0, neg2=1, neg1=2, zero=3, pos1=4, pos2=5`. |
| Evaluation roles | `domain/evaluation/evaluation_participant_role.dart` — `author(0), committer(1), forwarder(2), formerCommitter(3)`. |
| Evaluation pairs | `domain/evaluation/evaluation_visibility_rules.dart` → `beacon_evaluation_visibility`. |
| Submission method | **`EvaluationCase.evaluationSubmit`** (not `submitEvaluation`), `evaluation_case.dart:~1059`. |
| Forward reason writes | `forward_case.dart` — **update path ≈ `:89-115`**, **create path ≈ `:125-278`**. (rev 1 had these reversed.) |
| `beacon_forward_edge.id` | `text` PK (m0014). |
| `forwardEdgeRepository.createBatch` **[changed by C3]** | Returns **recipient IDs, not edge IDs**. C3 changes it to return typed `ForwardEdgeCreated`. |
| Ego MR facts | `person_visibility_peers(viewer_id, ctx)` → `peer_id, forward_mr, reverse_mr, viewer_explicitly_trusts_subject, subject_explicitly_trusts_viewer, viewer_can_see_subject, subject_can_see_viewer, is_mutually_visible`. **Includes explicitly-trusted peers with `forward_mr = 0`.** Incoming-only MR (peer→viewer only, including mixed trustOut+mrIn) is omitted as of m0151: first for speed, second for simplicity. Mixed `trustIn + mrOut` is unchanged. |
| Forward candidates | Hasura SQL function `mutually_visible_users(context)` — reached **through Hasura, not Dart**. |
| GraphQL registration | `api/controllers/graphql/query/_queries_all.dart`, `mutation/_mutations_all.dart`, types in `custom_types.dart`. No server-side `schema.graphql`. |
| Client Ferry schema | `packages/client/lib/data/gql/schema.graphql` — **tracked in git**; Ferry validates against it. |
| Client V2 routing | `data/service/remote_api_client/build_client.dart` → `_tenturaDirectOperationNames`. Operations absent from this list route to **Hasura** and fail. |
| Dropped in m0122 | `trust_apply_evidence`, `meritrank_sweep`, `trust_recompute_all`. Do not reference them. |
| Trust storage | `user_trust_source_edge` = fixed-anchor accumulators; `user_trust_edge` = effective projection. |
| Client profile chips **[changed by F3]** | Rendered from `state.cues.viewerVisible` in `features/profile_view/ui/widget/profile_view_body.dart:~395-415`. **`viewerVisible` also feeds the editable capability dialog (~`:425`) and the Forward picker** — F3 must add a *separate* state field rather than repoint it, or witness-derived tags become user-editable. `profileBeaconCueSlugs` / `strongestNetworkCueSlugs` have **no production call sites** (tests only). |

**Known-stale doc:** `docs/features/trust_edges.md` describes the pre-m0122 world. Unit G1 fixes it; do not trust it.

---

## 2. Global rules

**Layering:** server use cases import `domain/port/` only. Repositories return domain entities. Policy (thresholds, tiers, admission, caps, mute) lives in domain use cases; SQL owns arithmetic only. Client cubits never import `data/service/`.

**Never:** edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `_g/`); add any tag→people query; expose `S`, `m`, `forward_mr`, counts or witness identities through any API or UI; write tag evidence into MeritRank; touch pre-existing unrelated changes; push or deploy.

**Codegen:**
```bash
cd packages/server && dart run build_runner build -d
cd packages/client && flutter gen-l10n && dart run build_runner build -d
```

**Verification:**
```bash
cd packages/tentura_lints && dart test
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
cd packages/client && flutter test
cd packages/server && dart test -x pg                    # unit tests, no DB
cd packages/server && dart test -t pg                    # requires live Postgres
bash scripts/check-user-facing-terminology.sh
```
Live Postgres for `-t pg`: `sudo service docker start && ./scripts/dev-up.sh` (see `local-debug` skill).

**Constants** — one file, `packages/server/lib/domain/capability/capability_consts.dart` (created in B1):
```
kCapKOut = 2.0                     kCapHalfLifeOutSeconds  = 365 * 86400   // 31536000
kCapKSeed = 1.0                    kCapHalfLifeSeedSeconds =  90 * 86400   //  7776000
kCapThetaOut = 0.30                kCapWindowMonths     = 24
kCapThetaSeed = 0.25               kCapFloorPercentile  = 0.33
kCapWitnessWindowK = 200
kCapBandEvidenceSlots = 3          kCapExplorationSlots = 2
kCapMaxTagsPerSubjectBeacon = 3    kCapExplorationRecentForwardDays = 30

**Half-lives are in SECONDS.** Every SQL function here takes `_half_life_seconds`; a constant named `…Days` passed straight into one decays evidence 86,400x too fast, and nothing errors — it just silently produces a system with a six-minute memory.
kCapWindowTtlMinutes = 15
```

---

## 3. Decisions this plan makes (do not re-litigate)

**3.1 Rebuild-on-write replaces the inflate/deflate accumulator.** Every ledger mutation bumps a generation and fully rebuilds its cell from the eligible ledger window, inside one transaction and lock. `anchor_at` is **reset to the rebuild time** and all contributions are deflated to it. This is algebraically equivalent to the architecture's fixed-anchor VSIDS model but changes the storage invariant — an intentional, recorded deviation from architecture §5.1, chosen because it is far harder to implement incorrectly. Unit A3 must include an equivalence test across repeated rebuilds.

**3.2 No per-request observation budget.** Architecture D23 was **withdrawn** (see architecture §7): splitting `1.0` across acknowledging witnesses is non-monotone, because weights are stored ego-independently while admission is per-ego, so an acknowledger a given ego does not admit erases evidence a trusted witness supplied. Every acknowledgement is therefore emitted at **weight `1.0`**, there is **no `weight` column**, and C2 does no budget arithmetic.

**3.3 No disclosure gate.** Removed pre-launch (architecture D19). There is no `disclosure_version` column, no client-asserted token, no eligibility filter, and no enablement unit. Which sources aggregate is fixed by source type: `privateLabel` and `commitRole` never; `forwardReason`, `closeAcknowledgement`, `seedRoutingAttestation` always.

**Consequence:** the witness layer is **live as soon as A–F land** — no separate switch-on step, and no cold-start gap. Tentura is invite-only and invite consumption writes a mutual `vote_user` pair plus reciprocal trust evidence (`user_repository.dart:~849`), so every organic ego has a defined eligibility floor from their first session, starting with their inviter as sole admitted witness.

Disclosure wording is still required before real users exist, but it is ordinary copy in the UI units, not a gate.

**3.4 Profile context.** `subjectiveTags` uses the **canonical default context (`''`)**, not the viewer's currently selected context. A profile is not a browsing-context-scoped object, and making the same person's profile change as the viewer switches contexts is confusing and untestable. Closes architecture §20.6b.

**3.5 Context normalization contract.** Normalization must be reachable from **both SQL/Hasura and Dart**, because the candidate list goes through Hasura. It is a **SQL function** `public.cap_normalize_context(text) RETURNS text` (A2), plus a **pure Dart implementation** (not a wrapper that calls SQL — a domain function must not perform I/O) held to parity by test.

Rule: `NULL` → `''`; `trim`; if the trimmed length is outside **3–32**, → `''`; otherwise return the trimmed value **with its case preserved**.

Two corrections to an earlier draft: it let 33+ character values through despite claiming a 3–32 bound, and it **lowercased**. Lowercasing is wrong — live context creation preserves case, so folding `Work` to `work` would key the witness window to a different string than the one the existing MR graph uses, silently splitting a context in two.

---

## 4. Unit manifest

| # | Unit | Depends on | Owns (schema/files) |
|---|---|---|---|
| A0 | Journal + baseline | — | journal only |
| A1 | Ledger extension | A0 | m0141; `person_capability_events.dart`; `CapabilityEventSource.seedRoutingAttestation(4)` |
| A2 | Derived tables + context fn | A1 | m0142; cell/window/mute/generation/epoch tables + Drift; `cap_normalize_context` |
| A3 | Evidence SQL functions | A2 | m0143; `cap_strength`, `cap_cell_lock`, `cap_generation_bump`, `cap_cell_rebuild` |
| B1 | Domain types + ports | A3 | `domain/capability/*`, `domain/port/capability_*`, `capability_consts.dart` |
| B2a | Cell write adapter | B1 | `capability_evidence_repository.dart` (ledger mutations, rebuild, locking) |
| B2b | Witness window adapter | B1 | `witness_window_repository.dart` (window SQL, caching, epoch read) |
| B2c | Read adapters | B1 | own-evidence, tombstone, mute, block-query repositories |
| B3 | MR epoch ownership | B2b | **m0144**; epoch bump in `trust_rebuild_effective_edge`; block/vote invalidation |
| C1a | Ack schema + atomic adapter | B2a | m0145; `beacon_evaluation_ack_tag`; `submitEvaluationAtomic` in `evaluation_repository.dart` |
| C1b | Ack use-case policy | C1a | `evaluationSubmit` role/slug/cap policy; typed help-offer port |
| C2 | Finalization emission | C1b | `ReviewCloseSnapshot`, the finalization CTE, batch emission |
| C3a | Forward server paths | B2a | forward-edge port return shape; create/update/cancel + reconciliation |
| C3b | Forward client semantics | C3a | `forward_cubit.dart` null-vs-empty; mutation resolver |
| C4 | Invite seed attestation | B2a, B2c | m0146; `invite_seed_prompt_state`; prompt-state port + use case |
| C5 | Retire `commitRole` reads | B2c | `person_capability_event_repository.dart` |
| D0 | Band candidate facts port | B2b | `BandCandidatePort` + adapter (canonical candidates, `forward_mr`, recent forwards) |
| D1 | Projection use case | C1b–C5 | `capability_projection_case.dart` |
| D2 | Band composition | D1, D0 | `forward_band_case.dart`, `fnv1a64` |
| D3 | Expiry sweep | B2a | m0147; lease columns; sweep case + TaskWorker registration |
| D4 | **Model invariant suite** | D2 | `test/domain/capability/model_invariants_test.dart` — qualitative property tests |
| E1a | Query resolvers + authz | D2, D3, D4 | `subjectiveTags`, `forwardContext`, `tagExplanation`, **and `CapabilityRoutingCase` incl. its read methods** |
| E1b | Mutation resolvers + authz | E1a | `myRoutingTags`, seed, revoke, setMute, prompt answer/skip |
| F1a | Client schema + routing | E1b | `schema.graphql`, `_tenturaDirectOperationNames` |
| F1b | Client gql docs + repository | F1a | `.graphql` documents, repository, client entities |
| F2 | Forward band UI | F1b | forward cubit/state/screen |
| F3 | Profile projection UI | F1b | `profile_view_body.dart` + cubit/state (new field, not `viewerVisible`) |
| F4a | Invite prompt receipt | F1b, C4 | receipt card + prompt state machine |
| F4b | Seed edit/withdraw | F4a | inviter-side edit path on the invitee's profile |
| F5 | Routing mute screen | F1b | route + registration + cubit + settings entry |
| F6 | Client release checks | F2–F5 | semver bump, web cache-buster, min-client-version |
| G1a | Telemetry — producers | F6 | emission points for band fill/conversion, seed renewal, mute rate |
| G1b | Telemetry — analysis signals | G1a | window coverage, floor margin, eligible-witness coverage, reciprocity histogram |
| G2 | Docs and ADR | G1 | `trust_edges.md` rewrite, ADR |
| G3a | Server-side e2e proof | G2 | pg-level 4-user fixture: emission, admission, mute |
| G3b | Browser e2e proof | G3a | web harness assertions on the rendered band |

Strictly sequential except: B2a/B2b/B2c may run in any order after B1; F2–F5 in any order after F1b. Still **one worker at a time**.

### 4.1 How the split units map onto the unit bodies

The unit bodies below are written per *original* unit. A split sub-unit owns the named part of its body and nothing else:

| Sub-unit | Owns, within the body |
|---|---|
| **B2a** | "Write discipline" — ledger mutations, `cap_generation_bump`/`cap_cell_rebuild` calls, lock ordering, `emitOutcomeEvidenceBatch` |
| **B2b** | "`windowFor`" — the window SQL, `R_ego`/floor/admission, caching and epoch checks |
| **B2c** | own-evidence, tombstone, mute and block-query adapters (no body text beyond B1's port signatures — implement exactly those) |
| **C1a** | the `m0145` migration, the Drift table, and `submitEvaluationAtomic` in `evaluation_repository.dart` |
| **C1b** | the numbered policy steps 1–6 in `evaluationSubmit`, and the typed help-offer port |
| **C3a** | the forward-edge port return-shape change and the create/update/cancel server paths |
| **C3b** | the null-vs-empty client semantics — `forward_cubit.dart` and the mutation resolver |
| **E1a** | `subjectiveTags`, `forwardContext`, `tagExplanation` + their §16.1 predicates, **and `CapabilityRoutingCase`** — E1a runs first and a resolver may not call a port directly, so the use case cannot live in E1b |
| **E1b** | `myRoutingTags`, `seedRoutingAttestation`, `revokeAcknowledgement`, `setRoutingMute`, prompt answer/skip |
| **F1a** | `schema.graphql` and `_tenturaDirectOperationNames` (steps 1–2) |
| **F1b** | the `.graphql` documents, codegen, repository and client entities (step 3 onward) |
| **F4a** | the receipt card and its prompt state machine |
| **F4b** | the inviter-side edit/withdraw path on the invitee's profile |

**Splits vs rev 2** (each was too large for one composer-2.5 session): B2 → B2a/b/c; C1 → C1a/b; C3 → C3a/b; E1 → E1a/b; F1 → F1a/b; F4 → F4a/b. **New units:** D0 (rev 2's D2 had no Clean-Architecture path to obtain candidates — the existing `person_visibility_repository_port` can only filter a supplied list, so a literal worker would have imported a data repository), and G1 (architecture §21's telemetry had no owner at all).

---

## UNIT A0 — Journal and baseline

Create `docs/plans/subjective-help-tag-evidence-implementation-journal.md` with: objective, plan path, architecture path, repo/branch/starting HEAD, pre-existing worktree changes recorded verbatim, the §4 manifest as a checklist, verification commands, and an "open questions" section. No code changes.

Entry template every later unit appends:
```
## <unit id> — <status: complete|partial|blocked> — <ISO date>
COMMITS: <hashes + subjects>
TESTS: <exact commands + outcomes>
FILES: <changed paths>
FINDINGS: <facts that contradicted the plan, decisions taken>
REMAINING: <concrete unfinished work or "none">
```

---

## UNIT A1 — Ledger extension

**Preconditions:** latest migration is `m0140`; `person_capability_event` has no `source_type` CHECK.

Create `m0141.dart` + register.

```sql
ALTER TABLE public.person_capability_event
  ADD COLUMN forward_edge_id text NULL
      REFERENCES public.beacon_forward_edge(id) ON DELETE CASCADE,
  ADD COLUMN invitation_id text NULL
      REFERENCES public.invitation(id) ON DELETE SET NULL,
  ADD CONSTRAINT pce_source_type_ck CHECK (source_type IN (0,1,2,3,4));

CREATE UNIQUE INDEX pce_seed_attestation_uq
  ON public.person_capability_event(observer_user_id, subject_user_id, tag_slug)
  WHERE source_type = 4 AND deleted_at IS NULL;

CREATE UNIQUE INDEX pce_forward_reason_uq
  ON public.person_capability_event(forward_edge_id, tag_slug)
  WHERE source_type = 1 AND deleted_at IS NULL AND forward_edge_id IS NOT NULL;

CREATE UNIQUE INDEX pce_close_ack_uq
  ON public.person_capability_event(observer_user_id, subject_user_id, tag_slug, beacon_id)
  WHERE source_type = 3 AND deleted_at IS NULL;

CREATE INDEX pce_aggregation_idx
  ON public.person_capability_event(subject_user_id, tag_slug, observer_user_id)
  WHERE deleted_at IS NULL AND is_negative = false;
```

Verify `public.invitation`'s PK name and type before writing the FK; if it is not a single `text`/`uuid` column, record it in the journal and use a plain column with a documented non-enforcement note.

**Also in this unit** (rev 1 orphaned all three):
- Add `forwardEdgeId`, `invitationId` to `table/person_capability_events.dart`.
- Add `seedRoutingAttestation(4)` to `CapabilityEventSource`.
- Run server `build_runner`.

**Acceptance:** migration applies on a fresh DB and on one at m0140; `source_type = 5` is rejected; duplicate active source-4 rows are rejected; the FK and CHECK behave as stated.

**Verify:** `cd packages/server && dart test -t pg test/data/database/` (add a migration test there if none covers m0141), plus `dart test -x pg`.

---

## UNIT A2 — Derived tables and context normalization

**Preconditions:** `m0141` exists and is registered.

Create `m0142.dart` + Drift tables for each new table.

Tables: `capability_evidence_edge`, `capability_evidence_generation`, `ego_witness_window`, `capability_routing_mute`, `mr_publish_epoch` — exactly as specified in architecture §4.2/§4.3/§4.4, with:

```sql
CREATE TABLE public.capability_evidence_edge (
  observer_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  subject_user_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug         text NOT NULL,
  s_out            double precision NOT NULL DEFAULT 0,
  s_seed           double precision NOT NULL DEFAULT 0,
  anchor_at        timestamptz NOT NULL DEFAULT now(),
  built_from_gen   bigint NOT NULL DEFAULT 0,
  next_expiry_at   timestamptz NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (observer_user_id, subject_user_id, tag_slug),
  CONSTRAINT cee_no_self CHECK (observer_user_id <> subject_user_id)
);
CREATE INDEX cee_projection_idx ON public.capability_evidence_edge (subject_user_id, tag_slug)
  INCLUDE (observer_user_id, s_out, s_seed, anchor_at);
CREATE INDEX cee_expiry_idx ON public.capability_evidence_edge (next_expiry_at)
  WHERE next_expiry_at IS NOT NULL;

CREATE TABLE public.capability_evidence_generation (
  observer_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  subject_user_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug text NOT NULL,
  generation bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (observer_user_id, subject_user_id, tag_slug));
-- FKs are required: without them, deleting a user cascades their ledger and
-- cell rows but leaves their ids here forever. D3 additionally GCs rows whose
-- ledger and cell are both absent.

CREATE TABLE public.ego_witness_window (
  ego_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  context text NOT NULL,
  witness_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  m double precision NOT NULL,
  admitted boolean NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  mr_epoch bigint NOT NULL,
  PRIMARY KEY (ego_user_id, context, witness_user_id));
CREATE INDEX eww_gc_idx ON public.ego_witness_window (computed_at);

CREATE TABLE public.capability_routing_mute (
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, tag_slug));

CREATE TABLE public.mr_publish_epoch (
  id boolean PRIMARY KEY DEFAULT true CHECK (id), epoch bigint NOT NULL DEFAULT 0);
INSERT INTO public.mr_publish_epoch DEFAULT VALUES;
```

**Context normalization (§3.5)** — SQL is the source of truth so Hasura can use it:
```sql
CREATE OR REPLACE FUNCTION public.cap_normalize_context(_c text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN _c IS NULL THEN ''
    WHEN length(btrim(_c)) < 3 OR length(btrim(_c)) > 32 THEN ''
    ELSE btrim(_c)
  END;
$$;
```
Add a pure Dart implementation in `domain/capability/context_normalization.dart` **plus a pg-tagged parity test** asserting both agree on: `null`, `''`, `'  '`, `'ab'`, `' AbC '` (→ `AbC`, case kept), a 32-char string, a 33-char string.

**A2 also owns applying it at the canonical entry point.** `mutually_visible_users` currently passes the raw context straight to `person_visibility_peers`, so without this the candidate list and the witness window can still key on different strings. Redefine that function in this unit's migration to normalize its argument.

**Acceptance:** all tables/indexes exist; self-witness CHECK rejects `observer = subject`; epoch is a singleton row; parity test green.

---

## UNIT A3 — Evidence SQL functions

**Preconditions:** `m0142` exists.

Create `m0143.dart`, mirror into `sql/triggers.sql`.

```sql
-- STABLE, not IMMUTABLE: it reads now(). IMMUTABLE would let Postgres
-- constant-fold decay into a cached plan and serve stale strengths.
CREATE OR REPLACE FUNCTION public.cap_strength(
  _s double precision, _k double precision,
  _anchor timestamptz, _half_life_seconds double precision
) RETURNS double precision LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN _s <= 0 THEN 0 ELSE
    (_s * pow(2, -extract(epoch FROM (now() - _anchor)) / _half_life_seconds))
    / (_k + _s * pow(2, -extract(epoch FROM (now() - _anchor)) / _half_life_seconds))
  END;
$$;

CREATE OR REPLACE FUNCTION public.cap_cell_lock(_o text, _s text, _t text)
RETURNS void LANGUAGE sql VOLATILE AS $$
  SELECT pg_advisory_xact_lock(
    hashtextextended(_o || chr(31) || _s || chr(31) || _t, 4242));
$$;

CREATE OR REPLACE FUNCTION public.cap_generation_bump(_o text, _s text, _t text)
RETURNS bigint LANGUAGE sql VOLATILE AS $$
  INSERT INTO public.capability_evidence_generation AS g
    (observer_user_id, subject_user_id, tag_slug, generation)
  VALUES (_o, _s, _t, 1)
  ON CONFLICT (observer_user_id, subject_user_id, tag_slug)
    DO UPDATE SET generation = g.generation + 1
  RETURNING generation;
$$;
```

`cap_cell_rebuild(_o, _s, _t, _window_months, _hl_out, _hl_seed)` — PL/pgSQL:
1. `PERFORM cap_cell_lock(...)`.
2. Read current `generation`.
3. **One expression only**, in both places — do not also define a `now() - interval` cutoff:
   eligibility: `e.created_at + make_interval(months => _window_months) > now()`
   expiry:      `min(e.created_at) + make_interval(months => _window_months)`
   **Use `e.created_at + make_interval(months => _window_months) > now()` for eligibility**, i.e. the exact inverse of the expiry expression, so the two can never disagree. rev 2 used `created_at > now() - interval` for eligibility and `min(created_at) + interval` for expiry; PostgreSQL month arithmetic is not invertible at month ends, so a 2024-02-29 row stays eligible while already being due, and the sweep re-claims it every run for about a day. **Add a boundary test for 2024-02-29 + 24 months and for 31st-of-month dates.**
4. Aggregate over `person_capability_event` where `observer/subject/tag` match, `deleted_at IS NULL`, `is_negative = false`, `source_type IN (1,3,4)`, and the **step-3 expression** `e.created_at + make_interval(months => _window_months) > now()`. Do not introduce a `_cutoff` variable or a `now() - interval` form anywhere:
   - `s_out  = Σ pow(2, -extract(epoch FROM (anchor - e.created_at)) / _hl_out)` for `source_type = 3`
   - `s_seed = Σ pow(2, -extract(epoch FROM (anchor - e.created_at)) / _hl_seed)` for `source_type IN (1,4)`

   Each eligible row contributes **1.0** before decay (no weight column — §3.2). Note `extract(epoch FROM …)`: subtracting two `timestamptz` yields an `interval`, which cannot be divided or passed to `pow` directly, and `_hl_*` are **seconds**.
   with `anchor = now()`.
5. Upsert the cell; delete it when both accumulators are zero.

Aggregates are fine without `GROUP BY` here — every other selected value is a PL/pgSQL scalar.

**Acceptance (pg-tagged):**
- one source-3 row, fresh → `cap_strength(s_out, 2, anchor, H) ≈ 0.3333`
- three such rows → `≈ 0.60`
- rows older than 24 months contribute nothing
- **§3.1 equivalence:** rebuilding the same cell 5 times in a row leaves `cap_strength` unchanged to within 1e-9
- **half-life units:** a row 365 days old halves (`s ≈ 0.5`). If it decays to ~0 instead, `_hl_out` was passed in days.
- concurrent rebuilds of one triple serialize (two sessions, one blocks)

---

## UNIT B1 — Domain types and ports

**Preconditions:** A3 functions exist.

Create `packages/server/lib/domain/capability/capability_consts.dart` with §2's constants.

**Complete** Freezed entities (rev 1 referenced undefined types — every field below is required):

```dart
enum EvidenceChannel { outcome, seed }
enum ProjectionTier { ownOutcome, networkOutcome, ownRouting, networkSeed }
  // Declaration order IS precedence: channel first, then origin (D2, §5.4).
  // Tier A splits by channel because a single `own` value renders a merely
  // routed tag as "You worked together on X".
  // This enum is also what tagExplanation returns — there is no separate
  // ExplanationReason type; the four values already carry the distinction.
enum ProjectionSurface { forwardBand, profile }   // §3.4 / D22

@freezed class WitnessWeight        // one admitted-or-not witness for one ego
  { String witnessUserId; double m; bool admitted; }

@freezed class RawPeerFact
  { String peerId; double forwardMr; bool explicitlyTrusted; }

@freezed class RawWindowFacts       // input to the pure admission function
  { List<RawPeerFact> topPeers; List<double> trustedScores; }

@freezed class WitnessCellRow       // one cell joined to its witness weight
  { String observerUserId; String subjectUserId; String tagSlug;
    double eOut; double eSeed; double m; }
  // eOut/eSeed are SQL-COMPUTED effective strengths (cap_strength applied).
  // Raw s_out/s_seed/anchor_at must NOT be exposed: D1 would then have to
  // reimplement decay and saturation in Dart, violating "SQL owns arithmetic".

@freezed class CellRef              // addresses one cell
  { String observerUserId; String subjectUserId; String tagSlug; }

@freezed class OwnEvidenceRow       // ego's own ledger rows, for Tier A
  { String subjectUserId; String tagSlug; EvidenceChannel channel; }

@freezed class TombstoneRef         // ego's is_negative suppressions
  { String subjectUserId; String tagSlug; }

@freezed class ScoredProjection     // INTERNAL to D1/D2 — never crosses the API
  { String subjectUserId; String tagSlug; ProjectionTier tier;
    EvidenceChannel channel; double score; }

@freezed class TagProjection        // API-facing; carries NO score
  { String subjectUserId; String tagSlug; ProjectionTier tier; }

@freezed class ForwardBandRow
  { String userId; ProjectionTier? rowTier; List<TagProjection> labels;
    int rank; bool isExploration; }
  // rowTier is NULLABLE: exploration rows have no evidence and therefore no
  // tier. labels is empty for them.

@freezed class OutcomeEmission      // C2 -> emitOutcomeEvidenceBatch
  { String observerUserId; String subjectUserId; String tagSlug; }


enum PromptStateValue { pending, answered, skipped }

@freezed class PromptState          // C4 / F4
  { String inviterUserId; String inviteeUserId; PromptStateValue state; }

@freezed class BandCandidate        // D0 -> D2
  { String userId; double forwardMr; bool canForwardTo;
    bool alreadyForwarded; DateTime? lastForwardedAt; }
```

**Ports** (`domain/port/`) — complete signatures, no placeholders:

```dart
abstract interface class CapabilityEvidencePort {
  Future<void> reconcileForwardReasons({required String forwardEdgeId,
      required String observerId, required String subjectId,
      required List<String> slugs});
  Future<void> emitOutcomeEvidenceBatch({required String beaconId,
      required List<OutcomeEmission> emissions});          // C2: ONE batch call
  Future<void> revokeOutcomeEvidence({required String beaconId,
      required String observerId, required String subjectId, required String slug});
  /// Provenance is the (inviter, invitee) PAIR, not an invitation id — the
  /// invitation row is deleted during acceptance (C4).
  Future<void> upsertSeedAttestation({required String observerId,
      required String subjectId, required List<String> slugs});
}

abstract interface class CapabilityCellPort {
  Future<List<WitnessCellRow>> fetchCells({required List<String> subjectIds,
      required List<String> tagSlugs, required List<WitnessWeight> admittedWitnesses});
  Future<void> rebuildCell(CellRef ref);
  Future<List<CellRef>> claimExpiredCells({required int limit, required String leaseOwner});
}

abstract interface class WitnessWindowPort {
  /// Domain supplies the policy; the adapter only materializes it.
  /// Returns RAW facts, not decisions: the top-K peers AND the ego's full
  /// explicitly-trusted population (unbounded — needed for the floor).
  Future<RawWindowFacts> rawWindowFacts({required String egoId,
      required String normalizedContext, required int topK});
  /// Persists the domain's computed verdict.
  Future<void> storeWindow({required String egoId, required String normalizedContext,
      required List<WitnessWeight> weights});
  Future<List<WitnessWeight>> cachedWindow({required String egoId,
      required String normalizedContext});
  Future<void> invalidateFor({required String userId});
  Future<void> bumpMrEpoch();
}

abstract interface class CapabilityOwnEvidencePort {
  Future<List<OwnEvidenceRow>> fetchOwnEvidence({required String egoId,
      required List<String> subjectIds, required List<String> tagSlugs});
  Future<List<TombstoneRef>> fetchTombstones({required String egoId,
      required List<String> subjectIds});
}

abstract interface class RoutingMutePort {
  /// Subject-KEYED. rev 2 returned a flat Set<String>, which loses the subject:
  /// one person muting `transport` would have suppressed `transport` for every
  /// candidate in the band.
  Future<Map<String, Set<String>>> mutedSlugsFor({required List<String> subjectIds});
  Future<Set<String>> mutedSlugsForUser(String userId);
  Future<void> setMute({required String userId, required String tagSlug, required bool muted});
}

abstract interface class PairBlockQueryPort {
  /// BATCH. One call must answer every pair D1 needs: ego<->witness and
  /// witness<->subject across up to 200 witnesses and ~50 subjects.
  /// A per-user `blockedPeersOf` would make the projection an N+1 query
  /// and break the "one round trip per Forward screen" claim.
  Future<Set<(String, String)>> blockedPairsAmong({required Set<String> userIds});
}
```

**Acceptance:** `rg "package:tentura_server/data/repository" packages/server/lib/domain` is empty; everything compiles; `./scripts/check-custom-lints.sh packages/server` clean.

---

## UNIT B2 — Repositories

**Preconditions:** B1 ports exist.

Implement each port under `data/repository/`, `@Injectable(as: …Port)`.

**Write discipline:**
- Every ledger mutation: `cap_generation_bump` → mutate → `cap_cell_rebuild`, all inside one transaction, under `cap_cell_lock`.
- Multi-cell operations sort `(observer, subject, tag)` **lexicographically and acquire all locks before any mutation**. Unsorted acquisition deadlocks two concurrent finalizations with overlapping cells.
- `emitOutcomeEvidenceBatch` must **not** call `withMutatingUser` per observer — finalization already runs inside one UoW owned by the actor or the system, and re-entering with a different actor **throws**. Emit all rows under the ambient UoW; suppress realtime self-echo using the finalization's own actor.

**`windowFor` — the adapter fetches RAW peer facts; the domain computes `m` and `admitted`.**

Passing `floorPercentile` into SQL does not move policy to the domain — the predicate still lives in the query. Instead the adapter returns raw rows (`peer_id, forward_mr, viewer_explicitly_trusts_subject`) and a **pure Dart function** in `domain/capability/` computes `R_ego`, `floor`, `m` and `admitted`. That function is unit-testable without Postgres, which is the actual test of whether policy sits in the domain. At `topK = 200` the transfer cost is trivial.

The SQL below is therefore the **fetch**, not the decision:
```sql
WITH peers AS (
  SELECT peer_id, forward_mr, viewer_explicitly_trusts_subject
  FROM person_visibility_peers($ego, $ctx)
  WHERE forward_mr > 0                                  -- MANDATORY: excludes
                                                        -- explicitly-trusted zero-MR peers
  ORDER BY forward_mr DESC, peer_id ASC
  LIMIT $topK                                           -- MANDATORY: top-200
),
trusted AS (   -- UNBOUNDED by topK: an explicitly-trusted peer ranked 500th
               -- still belongs to the ego's revealed standard
  SELECT forward_mr
  FROM person_visibility_peers($ego, $ctx)
  WHERE viewer_explicitly_trusts_subject AND forward_mr > 0
)
-- Two raw result sets. NO percentile, NO median, NO admission decision here.
SELECT 'peer' AS kind, peer_id, forward_mr, viewer_explicitly_trusts_subject FROM peers
UNION ALL
SELECT 'trusted', NULL, forward_mr, true FROM trusted;
```
The **pure Dart function** then computes everything: `R_ego` (median of the top three peer scores, `max` when fewer than three), `floor` (the 33rd percentile of the *trusted* set), `m = min(1, forward_mr / R_ego)` guarding `R_ego = 0`, and `admitted = explicitly_trusted || (floor != null && forward_mr >= floor)`.

An earlier draft kept `ref`/`flr` CTEs computing the median rule and the floor percentile in SQL while the prose claimed Dart owned them — a literal worker implements the concrete artifact, so the policy stayed in the repository. The port must therefore also return the **unbounded trusted population**, which a `List<WitnessWeight>` alone cannot carry. Materialize the result into `ego_witness_window`; the cached `admitted` column is the domain's verdict, persisted — never a rule the repository invented (architecture §4.3).

Two corrections rev 2 got wrong: the floor was computed **after** `LIMIT topK`, silently dropping explicitly-trusted peers outside the top 200 from the very population that defines the ego's standard; and `percentile_cont(0.5)` over exactly two peers returns their *average*, where the architecture requires the maximum below three peers.

When the explicit-trust set is empty, `floor_mr` is NULL and no peer is admitted — correct: the ego gets Tier A only. In practice this is rare: invite consumption creates a mutual vote pair, so only accounts created outside that path (seed/admin/test, or `_acceptBeaconInviteOnly` with `bindFriendship: false`) reach it. **Do not "fix" the NULL case with a fallback constant** — the empty result is meaningful.

Cache into `ego_witness_window` with the current `mr_publish_epoch.epoch`; serve from cache only when `mr_epoch = current` **and** `computed_at > now() - kCapWindowTtlMinutes`.

**Acceptance (pg-tagged):** floor with empty vote list → nothing admitted; **`n = 1` vote list (the invite-only default) → floor equals that vouch's `forward_mr`, and the inviter is admitted**; single peer → `m = 1.0`; outlier case `0.5, 0.02, 0.015` → `r_ego = 0.02`, second peer `m = 1.0`; a peer with `forward_mr = 0` who is explicitly trusted is **excluded**, not admitted at `m = 0`.

---

## UNIT B3 — MR epoch ownership

**Preconditions:** B2 exists.

Nothing else increments the epoch, so without this unit every cached window looks fresh forever.

**Bump the epoch inside SQL, at the publish sites** — not from Dart. `mr_put_edge`'s epsilon gate and its `EXCEPTION WHEN OTHERS` both live inside the SQL function (`m0122:273-279`), so publication success is invisible to Dart and "increment only on success" is not implementable from there.

Cover **every** publisher, not just the trust rebuild path: the m0003 triggers that push edges on beacon / comment / opinion / `vote_beacon` writes, `m0114`'s resync, `m0137`, and `meritrank_repository.dart:~56-61`. A beacon creation or a beacon vote shifts `forward_mr` and can move a peer across the admission floor; if those do not bump the epoch, gating-relevant windows stay stale for the full TTL — exactly what architecture §15 says is intolerable. The simplest correct shape is a wrapper around `mr_put_edge` that bumps on success.

Also invalidate on `userVote`/`userUnsubscribe` and on block/unblock in `user_block_case.dart` (both parties, both directions). Block/unblock must additionally call `invalidateFor` on **both** users.

**Acceptance:** a test asserting the epoch rises after a vote and after a block, and that a cached window is treated as stale afterwards.

---

## UNIT C1 — Acknowledgement as evaluation state

**Preconditions:** B2 exists; `evaluationSubmit` still calls `recordCloseAcknowledgement`.

Migration `m0145` + Drift table:
```sql
CREATE TABLE public.beacon_evaluation_ack_tag (
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  evaluator_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  subject_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (beacon_id, evaluator_id, subject_id, tag_slug));
```

**Transactional shape** — `EvaluationCase` currently has no `MutatingUnitOfWorkPort`. Inject one, and add **one** port method that performs the whole submission atomically:

```dart
// EvaluationRepositoryPort
Future<void> submitEvaluationAtomic({
  required String beaconId, required String evaluatorId, required String evaluatedUserId,
  required int value, required List<String> reasonTags, required String note,
  required List<String> ackTags,
});
```
The implementation takes `pg_advisory_xact_lock(hashtextextended(beaconId, 4242))` **first**, then re-reads the window, then performs validation writes and the ack-set replacement — all in one transaction. A standalone "lock" port method would commit and release before the later writes, so the lock must live inside the same operation.

`ReviewFinalizationCase` (C2) must take the **same** beacon lock.

In `evaluationSubmit`:
1. **If and only if the reconciled acknowledgement set is non-empty**, validate evaluator role ∈ {`author`, `committer`, `formerCommitter`} (D21). A forwarder submitting an ordinary evaluation **with no ack tags must still succeed** — rev 2 stated this as an unconditional role check, which would have rejected valid forwarder evaluations and broken shipped behaviour.
2. Validate slugs against `beacon.needs ∪ activeHelpOffer(subject).helpTypes`. Help types must arrive as `List<String>` **decoded in the repository** — the entity's nullable JSON string must not reach the use case.
3. Enforce ≤ `kCapMaxTagsPerSubjectBeacon` tags **per `(evaluator, subject, beacon)`** — i.e. per submitter, checked inside the lock.

   **Not across all evaluators at submission time.** A beacon-wide cap checked here locks out honest evaluators: if committer A acknowledges Carol with three tags, committer B's *entire evaluation submission* is rejected the moment they pick a fourth distinct tag — and because evaluations are private, B cannot see why, cannot edit A's, and is simply blocked. The beacon-wide bound is applied instead at **finalization (C2)**, where all sets are visible at once.
4. Replace the set for `(beacon, evaluator, subject)` — delete then insert.
5. **Delete the `recordCloseAcknowledgement` call and its `try/catch`.**

**Acceptance:** no ledger row at submission; second submit replaces the first set; **a forwarder submitting with ack tags is rejected, and a forwarder submitting with an EMPTY ack set succeeds** (shipped behaviour must not regress); a 4th tag from the SAME evaluator is rejected; a different evaluator submitting their own 3 tags succeeds; concurrent submit + close do not interleave (pg test with two sessions).

---

## UNIT C2 — Finalization emission

**Preconditions:** C1 complete; `beacon_evaluation_ack_tag` populated on submit.

**Snapshot.** `ReviewCloseSnapshot` currently carries only `evaluator_id, evaluated_user_id, value`, produced by a transactional `UPDATE … RETURNING` in `evaluation_repository.dart:~486-519`. Extend **both** the entity and that query: join `beacon_evaluation_participant` for the evaluator's role and `beacon_evaluation_ack_tag` for its tags, inside the same atomic statement. Rows with no ack tags carry an empty list.

Those data-layer files are **owned by C2**.

**Ack tags are one-to-many**, so a naïve `UPDATE … FROM … RETURNING` cannot aggregate them and would return an arbitrary joined row per evaluation. Required shape, one statement:

```sql
WITH finalized AS (
  UPDATE public.beacon_evaluation SET status = ... WHERE ... RETURNING evaluator_id, evaluated_user_id, value
)
SELECT f.evaluator_id, f.evaluated_user_id, f.value,
       p.role,
       coalesce(array_agg(a.tag_slug ORDER BY a.tag_slug)
                FILTER (WHERE a.tag_slug IS NOT NULL), '{}') AS ack_tags
FROM finalized f
JOIN public.beacon_evaluation_participant p
  ON p.beacon_id = $beacon AND p.user_id = f.evaluator_id
LEFT JOIN public.beacon_evaluation_ack_tag a
  ON a.beacon_id = $beacon AND a.evaluator_id = f.evaluator_id
 AND a.subject_id = f.evaluated_user_id
GROUP BY f.evaluator_id, f.evaluated_user_id, f.value, p.role;
```
The `FILTER` is what keeps an evaluation with no acknowledgements from producing a one-element array of `NULL`.

**Emission**, inside the existing UoW, under the beacon lock:
```
// D12's beacon-wide cap is applied HERE, where every evaluator's set is visible
qualifying = snapshot rows where value ∈ {4,5}
             AND role ∈ {author, committer, formerCommitter}
             AND ackTags non-empty
for each (subject S, tag T):
    emissions += (observer=E, subject=S, tag=T) for each E   // weight 1.0 each, §3.2

// cap: for each subject S, keep at most kCapMaxTagsPerSubjectBeacon distinct
// tags, ranked by (number of acknowledging evaluators DESC, tag_slug ASC).
// Deterministic, and it drops the least-corroborated tags rather than
// whichever evaluator happened to submit last.
emitOutcomeEvidenceBatch(beaconId, emissions)   // sorts + locks all cells first
```

**Acceptance:** `zero`/`neg1`/`noBasis` emit nothing; forwarder emits nothing; three co-acknowledgers on one `(subject, tag)` produce three ledger rows and a cell strength of `3/(2+3) = 0.60` (no budget division — §3.2); re-running finalization is idempotent; no `withMutatingUser` nesting exception when three different observers emit in one finalization.

---

## UNIT C3 — Forward-reason reconciliation

**Preconditions:** B2 exists.

**This unit owns a port change:** `forwardEdgeRepository.createBatch` returns recipient IDs, not edge IDs, so reasons cannot be keyed by edge. Change it to return a typed `ForwardEdgeCreated { String edgeId; String recipientId; }` list, and update all call sites.

Rewrite both `ForwardCase` paths (update ≈ `:89-115`, create ≈ `:125-278`) so the forward edge, its reason set and the cell rebuild are **one transaction**. Remove both best-effort `try/catch` blocks.

**Null-vs-empty (rev 1 left this undefined):** the client sends `null` for an emptied set. Define `null` = *unchanged*, `[]` = *clear all*, and update the client cubit (`forward_cubit.dart:~333-347`) and the mutation resolver to send `[]` when the user removes the last reason. Without this, removing the last reason silently leaves stale evidence.

**Also owned by C3:** `cancelForward` (≈ `forward_case.dart:57`) and the block-cleanup path soft-cancel edges **without** reconciling their reason rows, so a cancelled forward keeps contributing seed evidence forever. Cancellation must reconcile the reason set to empty and rebuild the affected cells, atomically with the cancellation.

**Acceptance:** `[transport]` → `[pets]` leaves exactly one active row; cancelling a forward removes its seed evidence; `[transport]` → `[]` leaves none; `null` leaves the set untouched; cancel-then-re-forward to the same recipient yields a new edge whose reason set is independent, and the cancelled edge's rows are gone (`createBatch` skips recipients with an active edge, so two *concurrently active* edges are unreachable); a forced reason-write failure rolls back the edge.

---

## UNIT C4 — Invite seed attestation

**Preconditions:** A1's source type 4 exists.

Migration `m0146` + Drift:
```sql
CREATE TABLE public.invite_seed_prompt_state (
  inviter_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  invitee_user_id text PRIMARY KEY REFERENCES public."user"(id) ON DELETE CASCADE,
  state smallint NOT NULL DEFAULT 0,          -- 0 pending, 1 answered, 2 skipped
  updated_at timestamptz NOT NULL DEFAULT now());
```

**Keyed by the user pair, NOT by `invitation_id`.** `bindMutual` **deletes the invitation row** (`user_repository.dart:~845`) as part of ordinary acceptance, so an `invitation_id` FK is either cascaded away (insert before delete) or violated (insert after). The same deletion also destroys the fact needed to prove "direct inviter + accepted invitation" later.

The durable record of that relationship is **`invite_genealogy`** (`descendant_user_id` unique → `ancestor_user_id`), written by `recordSignupEdge` and surviving invitation deletion. Use it for both:
- insert the `pending` row from the same path that calls `recordSignupEdge`, **gated on `bindFriendship: true`** — `recordSignupEdge` also runs for `_acceptBeaconInviteOnly`, and prompting someone to seed a user who merely opened a beacon link (and is not a friend) would also let genealogy-based authorization admit that seeding;
- resolve C4/E1b's "actor is the direct inviter of subject" predicate as `invite_genealogy.descendant_user_id = subject AND ancestor_user_id = actor`.

**Prompt-state contracts (rev 2 defined none, so F4 could not implement its state machine):**
```dart
abstract interface class InviteSeedPromptPort {
  Future<PromptState?> stateFor({required String inviterId, required String inviteeId});
  Future<void> markAnswered({required String inviterId, required String inviteeId});
  Future<void> markSkipped({required String inviterId, required String inviteeId});
}

abstract interface class InviteRelationPort {          // durable inviter lookup
  Future<String?> inviterOf(String userId);            // invite_genealogy
}
```
plus use-case methods for read / answer / skip / withdraw. `PromptStateValue` and `PromptState` are defined in **B1** (not here — two units each believing the other owns the enum yields a double definition or a missing type). `seedRoutingAttestation(subjectId, slugs)` alone **cannot** distinguish *skipped* from *answered with zero tags* — the state transition must be explicit and atomic with the attestation write. E1b owns the corresponding GraphQL query and skip mutation.

Use case + port method for `upsertSeedAttestation`. **Validate every slug against `kAllowedCapabilitySlugs`, deduplicate, and reject payloads longer than the taxonomy (37)** — acknowledgement slugs are validated today but seed and mute writes are not, so an authenticated client could otherwise mint arbitrary ledger rows and force unbounded reconciliation. The same validation applies to `setRoutingMute`. Authorization (enforced in the domain, re-checked in E1): actor is the **direct inviter**, subject **accepted that invitation**, `actor != subject`, no block either way. Directional only.

**Acceptance:** non-inviter rejected; invitee-seeds-inviter rejected; re-answer replaces; skip records state 2 and writes no attestation.

---

## UNIT C5 — Retire `commitRole` reads

**Preconditions:** B2 exists.

In `person_capability_event_repository.dart`, remove `source_type = 2` from every read path. The exact locations:
- `fetchDeduplicatedCapabilities` — source 2 appears **only** in the main union at ≈ `:442-447`.
- `fetchTopCapabilitiesBatch` — the source-2 branch at ≈ `:526-529`.
- `fetchCues` — the commit-role query.

**Do not touch the self-view branch at ≈ `:404-415`.** It is `source_type = 3` (close acknowledgements), not source 2, and D22 requires it. rev 1 mislabelled it and would have deleted a valid path.

Keep `recordCommitRole` writing for audit.

**Acceptance:** `rg "commitRole" packages/server/lib/data/repository/person_capability_event_repository.dart` returns **only** the `recordCommitRole` write path, plus a behavioural test asserting a third party sees no commit-role slugs.

**Do not use a `source_type = 2` grep as the gate.** `fetchCues` binds the value as a parameter (`AND pce.source_type = $2` with `CapabilityEventSource.commitRole.dbValue`, `:265-271`), not as a literal — so removing the two literal sites at `:445` and `:529` passes such a grep while the subject-scoped leak survives in the cues path, which is precisely the bug this unit exists to fix.

---

## UNIT D0 — Band candidate facts port

**Preconditions:** B2b exists.

D2 needs the canonical candidate set with `forward_mr` and recent-forward history. The existing `person_visibility_repository_port` can only **filter an already-supplied peer list** — it cannot enumerate candidates and does not return `forward_mr`. Without this unit a literal D2 worker imports a data repository (breaking layering), trusts a client-supplied list (breaking authorization), or invents an interface.

```dart
abstract interface class BandCandidatePort {
  Future<List<BandCandidate>> candidatesFor({
    required String egoId, required String beaconId,
    required String normalizedContext});
  /// Includes CANCELLED and historical edges, keyed on
  /// `beacon_forward_edge.created_at`. `candidatesFor` already excludes
  /// active forwards, so an active-only implementation would always return
  /// empty and silently disable the exploration exclusion.
  Future<Set<String>> recentlyForwardedTo({
    required String egoId, required int withinDays});
}
```
`candidatesFor` applies the canonical server-side visibility projection and excludes author, declined, blocked, already-forwarded and `canForwardTo == false`. Lineage suggestions are excluded.

**Acceptance:** the returned set matches what the Forward screen's own candidate query yields for the same ego and context; a blocked peer is absent; `recentlyForwardedTo` respects the day window.

---

## UNIT D1 — Projection use case

**Preconditions:** C1–C5 complete.

`domain/use_case/capability_projection_case.dart`:

```dart
Future<List<ScoredProjection>> project({
  required String egoId,
  required List<String> subjectIds,
  required List<String> tagSlugs,
  required String normalizedContext,
  required ProjectionSurface surface,     // rev 1 omitted this and could serve neither consumer
});
```

Returns `ScoredProjection` (carrying channel + score) because D2 needs `max S` for deterministic ordering. The API layer maps to `TagProjection`, dropping the score. **The score must never leave the domain.**

Algorithm per architecture §5.5, with all filters:
- window → **admitted only** (D15); empty ⇒ own-evidence tiers only
- exclude `observer == ego`, `observer == subject`
- exclude rows muted by the subject, tombstoned by ego on `(ego, subject, tag)`
- exclude blocked pairs `(ego, observer)` **and** `(observer, subject)` (§16.2)
- `S_out ≥ θ_out` → `networkOutcome`; else `S_seed ≥ θ_seed` → `networkSeed`
- own evidence → `ownOutcome` (own close-ack) or `ownRouting` (own forward reason / seed attestation / private label), overriding, unless tombstoned by ego

**Surface filter (D22):** `ProjectionSurface.profile` returns the **outcome channel only** — `ownOutcome` and `networkOutcome`.

**D1 also owns the profile cap and ordering** (E1a's resolver only maps and drops scores, so if D1 omits this nobody applies it): at most **3** tags, ordered `ownOutcome` first, then `networkOutcome` by score descending, then `tag_slug` ascending for a total order. Acceptance must include a 4-tag fixture asserting exactly 3 come back in that order. It must exclude ego's own forward reasons, own seed attestations, private labels, and `networkSeed`. `forwardBand` returns all three tiers.

**Acceptance (unit tests, fake ports, no DB):** the §13.1 example → `networkOutcome`; Sybil case → nothing; an ineligible coalition summing 0.9 → nothing; muted → nothing; tombstoned → nothing including own; profile surface drops a seed-only tag that the band surface shows.

---

## UNIT D2 — Band composition

**Preconditions:** D1 exists and returns `ScoredProjection`.

`domain/use_case/forward_band_case.dart`, per architecture §8/§8.1/§9. Server owns ordering; the client receives `rank`.

Candidates come from **`BandCandidatePort.candidatesFor(egoId, beaconId, normalizedContext)`** (unit D0) — inject the port; do **not** query a repository, accept a client-supplied list, or reimplement candidate fetch. `PersonVisibilityRepositoryPort` cannot serve this: it only filters an already-supplied peer list and does not return `forward_mr`.

The recent-forward exclusion for exploration uses **`BandCandidatePort.recentlyForwardedTo(egoId, withinDays: kCapExplorationRecentForwardDays)`**.

Lineage suggestions do not participate.

Row reduction: `rowTier` = strongest tier, ordered **`ownOutcome > networkOutcome > ownRouting > networkSeed`** — **channel first, then origin**. Splitting Tier A by channel without re-deriving precedence would let an ego's own cheap *routing* tag outrank a *witnessed outcome*, and §8.1's same-tier label rule would then drop the witnessed outcome from the row entirely — inverting "seed is weaker than demonstrated outcome", which is the one precedence rule the whole design rests on. sort key `(rowTier, max S among tags AT that tier, forward_mr, userId)`; labels = up to 2 matched tags **sharing rowTier**, primary need first.

Exploration exactly as architecture §9, including empty-pool and singleton-pool behaviour. Implement `fnv1a64` in `domain/capability/` with unit tests pinning known vectors so client and server can never diverge.

**Acceptance:** deterministic output on a fixed fixture; empty and singleton pools; a candidate with `own` + `networkSeed` labels only the `own` tag; no band when no candidate has evidence.

---

## UNIT D3 — Expiry sweep

**Preconditions:** B2 exists.

`AttentionExpirySweepCase` is **not** a sufficient template — it has no bounded batch, no lease, no `SKIP LOCKED`, and does not hold its `FOR UPDATE` across processing. Specify explicitly:

```sql
-- claim, bounded, skip contended rows
SELECT observer_user_id, subject_user_id, tag_slug
FROM public.capability_evidence_edge
WHERE next_expiry_at IS NOT NULL AND next_expiry_at <= now()
ORDER BY next_expiry_at
LIMIT $batch
FOR UPDATE SKIP LOCKED;
```
**`FOR UPDATE SKIP LOCKED` alone is not a lease.** rev 2 returned claimed rows from one transaction and rebuilt them in later ones, so the row locks were released the moment the claim returned and two sweeps could process the same cells. Add persisted lease columns to `capability_evidence_edge` **in this unit's own migration (`m0147`)**:

```sql
ALTER TABLE public.capability_evidence_edge
  ADD COLUMN sweep_lease_owner text NULL,
  ADD COLUMN sweep_lease_until timestamptz NULL;
```
Claim atomically — the `UPDATE` is the lease:
```sql
WITH due AS (
  SELECT observer_user_id, subject_user_id, tag_slug
  FROM public.capability_evidence_edge
  WHERE next_expiry_at IS NOT NULL AND next_expiry_at <= now()
    AND (sweep_lease_until IS NULL OR sweep_lease_until < now())
  ORDER BY next_expiry_at
  LIMIT $batch FOR UPDATE SKIP LOCKED)
UPDATE public.capability_evidence_edge c
SET sweep_lease_owner = $owner, sweep_lease_until = now() + interval '5 minutes'
FROM due d WHERE (c.observer_user_id, c.subject_user_id, c.tag_slug)
                = (d.observer_user_id, d.subject_user_id, d.tag_slug)
RETURNING c.observer_user_id, c.subject_user_id, c.tag_slug;
```
Rebuild each claimed cell in its **own** transaction under `cap_cell_lock`, clearing the lease on completion. Record max observed lateness (`now() - next_expiry_at`) to logs.

Register with `TaskWorkerCase` (see `domain/use_case/task_worker_case.dart:~116-145` for the registration shape) at a 15-minute interval.

**Read-through staleness:** `fetchCells` must rebuild a cell before using it when `built_from_gen <> capability_evidence_generation.generation` **or** `next_expiry_at <= now()`. Without this the "hard window" is only as hard as the sweep interval.

Also GC, with actual `DELETE`s: `ego_witness_window` rows older than the TTL, and `capability_evidence_generation` rows whose ledger rows and cell are both absent (take the cell lock first).

**Acceptance:** a cell whose only row is 25 months old rebuilds to zero and is deleted; sweep is idempotent; two concurrent sweeps do not process the same row; a generation-stale cell is rebuilt on read.

---

## UNIT D4 — Model invariant suite

**Preconditions:** D1 and D2 exist and are exercisable through fake ports.

**Purpose.** The tag/trust model is deliberate, and its *constants* are hypotheses that will be retuned (`θ_out`, `θ_seed`, `K_o`, `K_s`, half-lives, the 33rd percentile). Its *ordering relations* are the design. This suite pins the orderings so a future calibration change cannot silently invert the model.

**The one rule that matters:** assert **inequalities and qualitative outcomes**, never magnitudes.

```dart
// WRONG — breaks on any recalibration, proves nothing about intent
expect(s, closeTo(0.4286, 0.001));

// RIGHT — survives recalibration, fails exactly when the design is violated
expect(standingOf(alice, carol, transport),
       greaterThan(standingOf(alice, carol, manualLabour)));
```

Pure domain tests with fake ports — **no Postgres, no server**. Run with `cd packages/server && dart test -x pg test/domain/capability/`.

### Fixture builder

Provide one small builder so each invariant is a two-or-three-line test:

```dart
final w = ModelWorld()
  ..ego('alice')
  ..vouches('alice', 'bob')            // explicit vote_user -> admitted
  ..reaches('alice', 'dylan', mr: 0.4) // in window, admission computed
  ..outcome(witness: 'bob', subject: 'carol', tag: transport, daysAgo: 10)
  ..seed(witness: 'dylan', subject: 'carol', tag: manualLabour, daysAgo: 10);

expect(w.standing('alice', 'carol', transport),
       greaterThan(w.standing('alice', 'carol', manualLabour)));
```

`standing()` returns the internal `ScoredProjection` ordering key (tier first, then score) — the same comparator D2 sorts by. Tests compare standings; they never read the score alone.

### The invariants

Implement **every** row. Each is one test named after its id.

**S — Subjectivity**
| id | Invariant |
|---|---|
| S1 | Two egos with different admitted sets can see different tag sets for the same subject. |
| S2 | An ego admitting nobody sees own-tier tags only, however much network evidence exists. |
| S3 | Nothing the subject does can *create* a tag for a viewer — only suppress one (mute). |
| S4 | A witness's evidence is invisible to an ego who cannot reach the witness at all. |

**C — Channel and precedence**
| id | Invariant |
|---|---|
| C1 | Outcome-derived standing > seed-derived standing for the same subject, **regardless of relative mass** — a seed with far more evidence still ranks below one outcome observation. |
| C2 | Row-tier order holds: `ownOutcome > networkOutcome > ownRouting > networkSeed`. |
| C3 | Profile projection contains outcome-channel tags only; a subject with seed evidence alone yields an empty profile but may still appear in the band. |
| C4 | **The user's worked case.** Alice vouches for Bob and Dylan; Bob close-acks Carol on `transport`; Dylan invite-seeds Carol for `manual_labour`. Then `transport > manual_labour` from Alice's standpoint. |
| C5 | **Phase-space border for C4:** the ordering is unchanged even when Dylan's `m` exceeds Bob's. Precedence is structural, not numeric. |
| C6 | **Border, other side:** age Bob's outcome past the 24-month window and the ordering flips — `manual_labour` now shows, `transport` does not. |
| C7 | **Border, admission:** if Alice stops admitting Dylan, `manual_labour` vanishes entirely while `transport` is untouched. |

**W — Witness weighting and monotonicity**
| id | Invariant |
|---|---|
| W1 | Any nonzero evidence from one admitted witness outranks **any quantity** of evidence from inadmissible witnesses. |
| W2 | For identical evidence, a higher-`m` admitted witness contributes more than a lower-`m` one. |
| W3 | **Adding a witness never decreases standing.** (The D23 defect, pinned. This must hold for *any* `m`, including very low, and whether or not the ego admits the new witness.) |
| W4 | Adding an observation never decreases standing. |
| W5 | Removing (revoking) an observation never increases standing. |

**A — Accumulation shape**
| id | Invariant |
|---|---|
| A1 | At equal witness weight, `k` witnesses with one observation each outrank one witness with `k` observations, for every `k > 1`. |
| A2 | One witness's contribution is bounded: no number of observations makes them outrank two equally-weighted witnesses with one observation each. |
| A3 | Diminishing returns per witness: the increment from observation `n+1` is smaller than from `n`. |
| A4 | Two witnesses each with one observation outrank one witness with one observation. |

**T — Time**
| id | Invariant |
|---|---|
| T1 | Identical evidence, more recent, outranks older. |
| T2 | Seed decays faster than outcome: given a seed and an outcome emitted together, the seed's share of their combined standing strictly declines with time. |
| T3 | Evidence beyond the window contributes nothing — a subject whose only evidence is out-of-window is indistinguishable from one with no evidence. |
| T4 | A fresh seed does not outrank a stale-but-in-window outcome (C1 holds across the whole window). |

**M — Mute and tombstone**
| id | Invariant |
|---|---|
| M1 | A subject's mute suppresses network tiers for **every** ego. |
| M2 | A subject's mute never suppresses an ego's **own** evidence. |
| M3 | **Mute is per `(subject, tag)`:** Carol muting `transport` leaves Alex's `transport` and Carol's `pets` untouched. *(This is the lossy-mute-key defect, pinned.)* |
| M4 | An ego's tombstone suppresses all tiers for that ego and changes nothing for any other ego. |

**X — Exclusions**
| id | Invariant |
|---|---|
| X1 | Self-witnessed evidence (`witness == subject`) contributes nothing to anyone. |
| X2 | `commitRole` contributes nothing to anyone, including the subject's own view. |
| X3 | A private label contributes only to its author's own tier and to no one else's projection. |
| X4 | A block between ego and witness removes that witness's contribution; a block between witness and subject removes that witness's evidence about that subject. |

**B — Band behaviour**
| id | Invariant |
|---|---|
| B1 | Tag evidence never removes a candidate from the underlying list — a candidate with zero evidence is still forwardable. |
| B2 | Band size is bounded regardless of how many candidates have evidence. |
| B3 | Only tags matching the request's needs appear; a subject's unrelated tags never surface in the band. |
| B4 | Whenever the band renders, exploration slots are present (subject to pool size). |
| B5 | Band ordering is deterministic and total — the same world yields the same order across runs. |

**Acceptance:** every id above has a named test; all pass; **no test asserts a bare numeric magnitude**. A reviewer must be able to change any constant in `capability_consts.dart` by a modest amount and see the suite still pass — add that as an explicit check by running the suite once with `θ_out` and `K_o` perturbed.

---

## UNIT E1 — GraphQL surface and authorization

**Preconditions:** D1, D2, D3 complete.

**`CapabilityRoutingCase` is created in E1a, not E1b.** It carries `revokeAcknowledgement`, `myRoutingTags` and `setRoutingMute`. E1a runs first and resolvers may only call use cases, so placing the case in E1b would leave E1a's resolvers with nothing legal to call.

Operations, registered in `_queries_all.dart` / `_mutations_all.dart` with types in `custom_types.dart`:

| Operation | Notes |
|---|---|
| `subjectiveTags(targetId)` | **No context argument** — uses the canonical default `''` (§3.4 / architecture D24). Profile surface. **D1 owns the top-3 cap and ordering** (own-outcome first, then `networkOutcome` by score, then slug); the resolver only maps and drops scores. |
| `forwardContext(beaconId, context)` | Returns the composed ranked band with `isExploration`. Never returns `S`. |
| `seedRoutingAttestation(subjectId, slugs)` | Invite-only. |
| `revokeAcknowledgement(beaconId, subjectId, slug)` | Original observer only; **permitted even when blocked** (else evidence can never be withdrawn, contradicting D14). |
| `myRoutingTags` / `setRoutingMute(slug, muted)` | Self only. |
| `tagExplanation(targetId, slug)` | Returns `ProjectionTier` — its four values already carry the own/network × outcome/routing distinction, so no separate enum is needed. |

Every operation implements its architecture §16.1 predicate. Actor is JWT-derived, never a parameter. Blocked pairs fail closed except revocation.

**Acceptance:** one negative authorization test per operation — non-inviter cannot seed, non-observer cannot revoke, blocked viewer gets nothing, non-participant cannot acknowledge, another user's mute cannot be set.

---

## UNIT F1 — Client data layer

**Preconditions:** E1b merged locally (no deploy required — the global rules forbid deploying).

Three mandatory steps rev 1 omitted, each of which silently breaks the feature:
1. **Update `packages/client/lib/data/gql/schema.graphql`** with the new types/operations. Ferry validates documents against this tracked file; without it codegen fails or emits wrong types.
2. **Add every new operation name to `_tenturaDirectOperationNames`** in `data/service/remote_api_client/build_client.dart`. That set contains **GraphQL *document* operation names (PascalCase), not server field names** — registering `subjectiveTags` instead of the `SubjectiveTags` document silently routes to Hasura and fails at runtime, and a test written from the field name confirms the same mistake. Required documents and operation names:

| File under `features/capability/data/gql/` | Operation name |
|---|---|
| `subjective_tags_fetch.graphql` | `SubjectiveTags` |
| `forward_context_fetch.graphql` | `ForwardContext` |
| `my_routing_tags_fetch.graphql` | `MyRoutingTags` |
| `tag_explanation_fetch.graphql` | `TagExplanation` |
| `seed_routing_attestation.graphql` | `SeedRoutingAttestation` |
| `revoke_acknowledgement.graphql` | `RevokeAcknowledgement` |
| `set_routing_mute.graphql` | `SetRoutingMute` |
| `invite_seed_prompt_fetch.graphql` | `InviteSeedPromptState` |
| `invite_seed_prompt_answer.graphql` | `InviteSeedPromptAnswer` |
| `invite_seed_prompt_skip.graphql` | `InviteSeedPromptSkip` |
3. Write the `.graphql` documents under `features/capability/data/gql/`, then run client codegen.

Repository returns client-domain entities mirroring B1's API-facing types. Ferry types must not escape the repository.

**Acceptance:** codegen clean; `flutter test` green; a test asserting each new operation name is present in `_tenturaDirectOperationNames`.

---

## UNIT F2 — Forward band UI

**Preconditions:** F1b complete.

Integrate into `features/forward/` — `forward_cubit.dart` / `forward_state.dart` gain the band; the screen renders it above the existing MR list. Band members are removed from the main list (dedupe by user id). **No band widget at all when the server returns an empty band** — the screen must then render byte-identically to today.

Styling through the design system only — invoke the `material-3-flutter` skill; no raw visual constants.

Copy — one key per tier value, **all four required**:
`ownOutcome` → "You worked together on {tag}"; `ownRouting` → "You've routed {tag} here"; `networkOutcome` → "Seen helping with {tag}"; `networkSeed` → "Suggested for {tag}". No scores, no "best match", no percentages.

**Acceptance:** widget tests per tier, empty-band case, exploration divider; `bash scripts/check-user-facing-terminology.sh` clean.

---

## UNIT F3 — Profile projection UI

**Preconditions:** F1b complete.

**Add a NEW state field for the outcome-only projection and render the strip from it. Do NOT repoint `viewerVisible`.**

`viewerVisible` also feeds the editable capability dialog (`profile_view_body.dart:~425`) and the Forward picker. Repointing it at witness-derived tags would make other people's observations user-editable — the exact hazard this feature exists to prevent. It stays exactly as it is, serving first-hand editable cues.

So: new field on the profile state, fed by `subjectiveTags`, rendered as the "Seen helping with" strip (max 3 tags). Separately, delete the two dead getters `profileBeaconCueSlugs` / `strongestNetworkCueSlugs` and their test references — they have no production call sites, so this is pure cleanup and changes no behaviour.

No counts, no numbers, no names. Absent entirely when empty.

**Acceptance:** a profile with only seed evidence shows no section; one with outcome evidence shows ≤ 3 tags; existing profile golden updated intentionally.

---

## UNIT F4 — Invite seeding prompt

**Preconditions:** F1b, C4 complete.

Extend the `invite_accepted` Updates receipt with an optional chip picker driven by `invite_seed_prompt_state`. Wire: fetch state, render `pending` only, submit → `answered`, skip → `skipped`, plus an edit/withdraw path from the invitee's profile as seen by the inviter.

Wording: *"What kinds of requests would you feel comfortable sending {name}?"* Never "skills", "endorse", "good at".

**Acceptance:** answered and skipped states each suppress re-prompting; withdrawing clears the attestation.

---

## UNIT F5 — Routing mute screen

**Preconditions:** F1b complete.

New screen rendering the **fixed 37-slug taxonomy** with a mute toggle each — nothing evidence-derived, no counts, no witnesses. Owns: the `@RoutePage()` screen, router registration, cubit + state, the settings entry point, its GraphQL operations, l10n keys, and widget tests.

**Acceptance:** toggling persists and round-trips; the screen renders all 37 slugs regardless of evidence.

---

## UNIT F6 — Client release checks

**Preconditions:** F2–F5 complete.

Per `AGENTS.md:33-34` and `.cursor/rules/versioning.mdc:17-25`: bump `packages/client/pubspec.yaml` semver, synchronize the web cache-buster in `packages/client/web/index.html:~132`, and decide/record the minimum-client-version implication of the new V2 operations. rev 1 left all three unowned, which violates repository release rules.

---

## UNIT G1 — Telemetry

**Preconditions:** F6 complete.

Architecture §21 calls these the minimum needed to know whether the feature works or is being gamed. rev 2 shipped none of them and logged only sweep lateness.

Emit: band fill rate and slot occupancy by tier; band conversion split by tier and by exploration slot; seed renewal rate before expiry; acknowledgement reciprocity between pairs with no third-party overlap (the §13.3 collusion detector) — emitted as **counts and histograms only, never user ids**, since a pair-shaped signal is identifying by construction; mute rate per tag; witness-window coverage (share of egos with an empty window, and separately with an empty vote list); floor margin against the 2-hop score band; eligible-witness coverage (pairs clearing θ from admitted witnesses vs pairs holding only inadmissible evidence).

Follow the repository's existing metrics/logging conventions — do not invent a new pipeline.

**Acceptance:** each signal is emitted and observable locally; no signal exposes an identifiable user pair.

---

## UNIT G2 — Docs and ADR

Rewrite `docs/features/trust_edges.md` for the m0122 architecture (`user_trust_source_edge` accumulators, `user_trust_edge` as effective projection, `trust_apply_evidence` / `meritrank_sweep` / `trust_recompute_all` dropped, `trust_resync_source` re-created with a new signature). It is currently wrong and was cited as authority during design.

Add an ADR under `docs/adr/` recording D1–D24 (noting D23 withdrawn) and the §3 deviations. Update `docs/README.md`. Run `scripts/check-doc-drift.sh`.

---

## UNIT G3 — Integration tests

**Split:** G3a proves the mechanism at the Postgres/server level (fast, deterministic, and where admission is actually decided); G3b proves the rendered result in the browser harness. Combining them made one unit that had to construct four users, orchestrate Postgres + server + client, and assert causality — too much for one session.

**Three distinct users minimum** — witness projection requires `ego ≠ witness ≠ subject`; a two-user fixture can only produce Tier A or self-witnessing and cannot prove admission at all.

Fixture: **Alice** (ego), **Bob** (witness, explicitly trusted by Alice), **Carol** (subject), **Eve** (second ego, *not* trusting Bob). Bob authors a request, Carol commits, Bob closes with `pos1` + ack tag, finalization runs.

**Carol must be an equally visible forward candidate for both Alice and Eve**, and the test must assert that precondition *before* asserting the band. rev 2's fixture never established it, so Eve's negative result could have been caused by candidate visibility rather than witness admission, and Alice's positive assertion could fail before projection ever ran. The only variable between the two egos must be Alice→Bob admission.

**Assert the witness-window preconditions directly before asserting the band** — that Bob is `admitted` in Alice's window and not in Eve's. Without that, a passing test proves only that the two egos differ, not *why*.

Then assert: Alice's band shows "Seen helping with …" for Carol; Eve's does not; Carol muting the tag removes it from Alice's band.

Extend `scripts/run_client_integration_web_local.sh`; see the `local-debug` and `integration-tests-web-e2e` conventions.

---

## 5. Rollback

Migrations are additive. Reconstruction sources differ per table and rebuild order matters:

| Table | Rebuilt from |
|---|---|
| `capability_evidence_edge` | the ledger (`cap_cell_rebuild` per triple) |
| `capability_evidence_generation` | reinitialize to 0 **only together with** a full cell rebuild |
| `ego_witness_window` | MeritRank / `person_visibility_peers` — **not** the ledger |
| `mr_publish_epoch` | any monotonically increasing value; bump invalidates all windows |

The ledger is never rebuilt from cells.
