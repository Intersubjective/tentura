---
status: draft
kind: implementation-plan
revision: 3
issues: [162, 180]
related: [142, 76, 184, 186]
review_record: docs/plans/issue-162-180-review-astra.md
branch: fix/162-180-review-package-state
---

# Issues #162 + #180 — Review package state and optional reviewers

Two issues, one defect seen from two sides: **the reviewer's package has a state,
and nothing in the UI shows it.**

- **#162** — the CTA cycles "Review contributions" → "Submit and finish" →
  "Review contributions", because the checklist screen never reads the package
  status and the HUD re-offers the same action after a successful send. (In the
  reported session the labels were the Russian
  `beaconHudActReviewContributions` and `evaluationSubmitFinish`.)
- **#180** — reviews owed **to** people who left the request block everybody
  else's package, because `canFinalize` demands an answer for every visible
  target.

Revision 3 is written for a **literal executor**: a small model that edits one
unit at a time, cannot make product decisions, and must not infer anything the
text does not state. Revision 2's design is unchanged; the units are expanded
into exact files, exact symbols, exact code and exact test names.

The independent review that produced revision 2 is archived in
[`issue-162-180-review-astra.md`](issue-162-180-review-astra.md). That file is a
record, not an instruction — it is written in Russian and **must not** be
executed. This plan is the only normative document.

---

## 0. How to use this document

1. Work through §5 units in order. Never skip, never reorder, never merge.
2. Each unit has the same shape:
   - **Owns** — the only files the unit may change. `new` marks a file to create.
   - **Read first** — open these before editing; they contain the shapes you copy.
   - **Steps** — numbered edits. Code blocks are literal unless the block says
     `sketch`.
   - **Tests** — exact test names to add.
   - **Verify** — copy each command as one line.
   - **Acceptance** — a binary check. If you cannot demonstrate it, the unit is
     not complete.
   - **Do not** — the mistakes that have been made here before.
3. **Stop and write `BLOCKED` in the journal** instead of improvising when:
   - a symbol named in a Step does not exist, or has a different signature;
   - a Step's literal code does not compile after an honest attempt;
   - a file in **Owns** has unrelated uncommitted changes you would destroy;
   - a frozen decision in §1 contradicts the live code.
   Line numbers drifting by a few lines is **not** a contradiction. Names are.
4. Never edit a file outside the current unit's **Owns**. If a change seems to
   require it, that is a `BLOCKED`.
5. Never invent a user-facing string. Every string comes from the §2 copy table
   through an l10n key.
6. Never rename, reformat or "tidy" code the unit does not touch.
7. One unit → Verify → journal entry → one local commit. Do not push.

---

## 1. Frozen decisions

Product decisions are made. They are inputs, not topics.

**D1 — Explicit send.** The package is sent by an explicit button. No auto-send on
checklist completeness. Documented contract:
`docs/beacon-evaluation-principles.md:28`.

**D2 — Auto-close on the last send is removed.** `evaluationFinalize` confirms
only the sender's own package. The window closes on exactly two paths: the author
presses close (`closeNow`, gated on all *required* packages sent), or the deadline
sweep runs (`attention_expiry_sweep_case.dart:43`).
`evaluationFinalize` starts with `_ensureExpiredClosed()`
(`evaluation_case.dart:1449` → `:148`), so a `finalize` made **after** the
deadline can still close the window through the sweep. That is intended.

**D3 — The author may not close early before all required packages are sent.** A
safety property: unsent rows are deleted at close
(`evaluation_repository.dart:729`), so a free early close would let an author
suppress a negative review in flight.

**D4 — Editing after send keeps the current demotion**
(`evaluation_repository.dart:392`) and makes it visible: the package returns to
"changed, not sent" with a re-send CTA. Never tell the user that edits after a
send are counted automatically — they are not, and at close they are deleted.

**D5 — No review-window generation id.** Deferred to
[#186](https://github.com/Intersubjective/tentura/issues/186). Do not introduce
`reviewRoundId`. Races *within one live window* and idempotency of the new
notifications are **not** covered by that deferral; they belong to this plan.

**D6 — Optional = `formerCommitter` (db role `3`), in both directions.** Their own
package never gates close (already true: `_canCloseNow:591`,
`_requiredPackagesAllSentLocked:808`); a review **about** them is optional in
everyone else's package.

The predicate is exactly the graph builder's
(`evaluation_participant_graph_builder.dart:43`, `:106` over
`commitment_state.dart`), and it is *not* a synonym for every everyday sense of
"left":

| Case | Classification today |
|---|---|
| ever acknowledged, current stake, active offer | `committer` — required |
| acknowledged then withdrawn / released / blocked / softened | `formerCommitter` — optional |
| withdrawn inside the grace period with no intermediate event | may never enter the ever-acknowledged graph |
| removed from the discussion room only | stake unchanged → still `committer` |
| forwarder | subject only, no package of their own |

This plan changes **none** of that classification.

**D7 — `canFinalize` counts required targets only**, client and server.

**D8 — "Skip" on an optional card is local only.** No server write, not persisted,
and it does **not** remove an already stored row from the package — it only hides
the card in this screen instance.

**D9 — Participant context is localized on the client.** The server stops emitting
English prose in the fields the new UI reads. The legacy
`contributionSummary` / `causalHint` columns stay and keep being written; only the
new UI stops reading them.

**D10 — Package state is the UI's primary variable; completeness is only
progress.** The nine states and their derivation order are frozen in UNIT 08.

**D11 — `userReviewStatus == 1` does NOT mean "sent, then edited".** The table
defines `1` as `in_progress` (`beacon_review_statuses.dart:14`) and the **first**
saved answer already moves `0 → 1` (`evaluation_case.dart:1355`). Sent-then-edited
is distinguished by the new `sent_at` column (UNIT 02), never by the status code.
Legacy `3` (`skipped`) is treated by the UI as "enrolled, not sent".

**D12 — `reviewWindowNotOpen` is ambiguous and must not be mapped directly.** The
server raises the same code after a reopen and after a final close
(`evaluation_case.dart:1072`; test at
`packages/server/test/domain/evaluation/evaluation_case_test.dart:1030`). On that
error the client re-reads authoritative state and classifies.

**D13 — There is no read-only checklist after close.** `evaluationParticipants`
requires a live window (`evaluation_case.dart:613`) and this plan does not change
that endpoint's authorization.

**D14 — Removing auto-close must not create dead air.** When the last required
package lands, the author is notified, transactionally and exactly once.

**D15 — Reopen is an announced event.** The author's confirm states how many
people already sent; previously enrolled reviewers get a cancellation notice.

**D16 — `sent_at` is the only source of the "reviews sent {date}" copy.** The
status DTO carries an integer and the window timestamps only
(`evaluation_case.dart:1029`). Never substitute `openedAt` or a local clock.

**D17 — Additive first, removal last.** Schema, DTO and l10n keys land before
consumers change; a legacy API is deleted in the same unit as its last consumer.
Every unit must leave the tree compiling.

**D18 — Generated code is not committed.** `**_g/` and `**.g.dart` are gitignored
(`packages/client/.gitignore:51`). Commit sources — `schema.graphql`, `.graphql`
documents, Dart, `.arb` — and run codegen locally. Never `git add -f` a generated
file. Client ferry codegen reads `packages/client/lib/data/gql/schema.graphql`
(`build.yaml:32`), which is **not** generated from the server: edit it by hand or
refresh it per `DEVELOPMENT.md:197`.

**D19 — Out of scope.** The review sheet's content (#76) — but adapting the sheet
to the new DTO **is** in scope; the null-check crash (#184) — and in-place send is
not evidence of a fix; window generation ids (#186); trust math; retiring the
legacy context columns.

---

## 2. Copy contract

Russian is authoritative, English mirrors it. These are the **only** strings this
plan introduces. In unit steps, strings are referenced by key, never by text.
`scripts/check-user-facing-terminology.sh` must pass. It enforces the
user-facing vocabulary: the Russian copy says "запрос" and "оценка", never
"beacon" or a transliteration of it, even though the code paths keep the
`beacon_*` names.

| Key | RU | EN | Placeholders |
|---|---|---|---|
| `evaluationSubmitFinish` *(changed)* | `Отправить оценки` | `Send reviews` | — |
| `evaluationSubmitChanges` | `Отправить изменения` | `Send changes` | — |
| `evaluationPackageSentAt` | `Оценки отправлены {date}` | `Reviews sent {date}` | `date: String` |
| `evaluationPackageSentHint` | `Изменить можно, пока запрос не закрыт. После изменения пакет придётся отправить заново.` | `You can change them until the request closes. After a change the package must be sent again.` | — |
| `evaluationPackageDirtyTitle` | `Изменения не отправлены` | `Changes not sent` | — |
| `evaluationPackageDirtyBody` | `Пока пакет не отправлен, ваши оценки не будут учтены при закрытии запроса.` | `Until the package is sent, your reviews are not counted when the request closes.` | — |
| `evaluationPackageDone` | `Готово` | `Done` | — |
| `evaluationPausedTitle` | `Автор вернул запрос в работу` | `The author reopened the request` | — |
| `evaluationPausedBody` | `Оценки никому не переданы. Сохранённые ответы остались черновиками — отправить их можно будет, когда автор снова свернёт запрос.` | `Nothing was shared. Your saved answers stayed drafts — you can send them when the author wraps the request up again.` | — |
| `evaluationPausedAction` | `К запросу` | `Open the request` | — |
| `evaluationClosedSentBody` | `Запрос закрыт. Ваши оценки отправлены и учтены.` | `The request is closed. Your reviews were sent and counted.` | — |
| `evaluationClosedUnsentBody` | `Запрос закрыт до того, как вы отправили пакет. Незавершённые оценки не сохранились.` | `The request closed before you sent your package. Unsent reviews were not kept.` | — |
| `evaluationSectionRequired` | `Обязательные` | `Required` | — |
| `evaluationSectionOptional` | `Необязательные · участие завершилось` | `Optional · participation ended` | — |
| `evaluationOptionalHint` | `Эти оценки не обязательны и не задерживают закрытие запроса.` | `These reviews are optional and do not hold up closing.` | — |
| `evaluationOptionalSkip` | `Пропустить` | `Skip` | — |
| `evaluationProgressSplit` | `{req} из {reqTotal} обязательных · {opt} из {optTotal} необязательных` | `{req} of {reqTotal} required · {opt} of {optTotal} optional` | four `int` |
| `evaluationOwnPackageOptional` | `Вы больше не участвуете в этом запросе. Оценку можно оставить, но она не обязательна. Если не отправите до закрытия, она не сохранится.` | `You no longer take part in this request. A review is welcome but not required. If you do not send it before the request closes, it is discarded.` | — |
| `evaluationContextCommitted` | `Помогал(а) с {date}` | `Helping since {date}` | `date: String` |
| `evaluationContextCommittedVia` | `Помогал(а) с {date} · через {name}` | `Helping since {date} · via {name}` | `date`, `name: String` |
| `evaluationContextCommittedNoDate` | `Помогал(а) с этим запросом` | `Helped with this request` | — |
| `evaluationContextEnded` | `Участие завершилось` | `Participation ended` | — |
| `evaluationContextForwarder` | `Передал(а) запрос дальше` | `Forwarded the request` | — |
| `evaluationContextOffer` | `«{message}»` | `“{message}”` | `message: String` |
| `beaconHudActReviewContributions` *(changed)* | `Оценить вклад` | `Review contributions` | — |
| `beaconHudActEffectReviewProgress` | `Осталось {count} из {total}` | `{count} of {total} left` | two `int` |
| `beaconHudReviewSent` | `Ваши оценки отправлены` | `Your reviews are sent` | — |
| `beaconHudReviewEdit` | `Изменить` | `Edit` | — |
| `beaconHudWaitingForRequiredReviews` | `Ждём оценки от остальных участников` | `Waiting for the other participants' reviews` | — |
| `beaconHudWaitingForAuthorClose` | `Ждём, пока автор закроет запрос` | `Waiting for the author to close the request` | — |
| `beaconReviewCloseNowBody` | `Оценки станут видны адресатам, изменить их будет нельзя.` | `Reviews become visible to their recipients and can no longer be changed.` | — |
| `beaconReviewCloseNowDiscardNote` | `{count} участников начали оценку и не отправили её — она не сохранится.` | `{count} people started a review and did not send it — it will not be kept.` | `count: int` |
| `beaconReviewReopenBody` *(changed)* | `Окно оценки закроется. {sent} участников уже отправили оценки — их отправка будет отменена, и отправить придётся заново. Открыть снова можно только один раз.` | `The review window closes. {sent} people already sent their reviews — their send is undone and they must send again. A request can be reopened only once.` | `sent: int` |
| `beaconReviewReopenBodyNoSent` | `Окно оценки закроется, сохранённые ответы останутся черновиками. Открыть снова можно только один раз.` | `The review window closes; saved answers stay drafts. A request can be reopened only once.` | — |
| `updatesFallbackTitleReviewAllIn` | `Все оценки собраны` | `All reviews are in` | — |
| `updatesFallbackBodyReviewAllIn` | `Запрос «{title}» можно закрыть.` | `The request “{title}” can be closed.` | `title: String` |
| `updatesFallbackTitleReviewCancelled` | `Окно оценки отменено` | `Review window cancelled` | — |
| `updatesFallbackBodyReviewCancelled` | `Автор вернул запрос «{title}» в работу.` | `The author reopened the request “{title}”.` | `title: String` |

### 2.1 Surface copy matrix

HUD and banner copy is chosen by (viewer role × package state ×
`allRequiredSent`) — never by package state alone.

| Viewer | State | `allRequiredSent` | Surface |
|---|---|---|---|
| any | `inProgress` | — | primary CTA `beaconHudActReviewContributions` + effect `beaconHudActEffectReviewProgress` |
| any | `readyToSend`, `changedNotSent` | — | primary CTA `beaconHudActReviewContributions`, no effect line |
| author | `sent` | false | status `beaconHudReviewSent` + `beaconHudWaitingForRequiredReviews` + text button `beaconHudReviewEdit` |
| author | `sent` | true | primary CTA close-now + status `beaconHudReviewSent` + text button `beaconHudReviewEdit` |
| non-author | `sent` | — | status `beaconHudReviewSent` + `beaconHudWaitingForAuthorClose` + text button `beaconHudReviewEdit` |
| any | `paused`, `closed`, `closedUnsent`, `notEnrolled`, `empty` | — | no review CTA |

"No primary CTA in `sent`" always means **no primary _review_ CTA**. The author's
close-now action is different and may be primary.

---

## 3. Live baseline and stop conditions

Verified at plan-writing time (2026-09-17):

```text
latest registered migration     m0175            (_migrations.dart:363)
client version                  7.15.0           (packages/client/pubspec.yaml:5)
web bootstrap                   ?v=7.15.0        (packages/client/web/index.html:132)
kDefaultMinClientVersion        7.10.0           (packages/server/lib/env.dart:67)
kMaxReviewReopens               1                (commitment_consts.dart:2)
_maxReviewExtensions            2                (evaluation_case.dart:146)
formerCommitter db value        3                (evaluation_participant_role.dart)
server evaluation tests live in packages/server/test/domain/evaluation/
client evaluation tests live in packages/client/test/features/evaluation/
```

UNIT 00 re-reads all of these. Stop with `BLOCKED` when:

- a migration `m0176` already exists **and** this plan would add another;
- `evaluationFinalize` no longer calls `_autoCloseReviewWindow`;
- `submitEvaluationAtomic` no longer demotes `2 → 1`, or the first save no longer
  moves `0 → 1`;
- `EvaluationParticipantRole.formerCommitter` is gone, or the client no longer
  collapses it at `packages/client/lib/features/evaluation/data/repository/evaluation_repository.dart:497`;
- a file in the current unit's **Owns** has unrelated uncommitted changes.

A changed Git HEAD alone is not a blocker.

---

## 4. Executor contract

1. Branch: `fix/162-180-review-package-state`. Commit locally per unit. Do not
   push, do not open a PR.
2. Preserve pre-existing modified/untracked files. Never `git reset`, `git stash`
   or stage paths outside the unit.
3. Create `docs/plans/issue-162-180-review-package-state-journal.md` in UNIT 00
   and append one entry per unit:

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
REMAINING: <specific work, or none>
```

4. Architecture rules that override convenience:
   - server use cases depend on ports only, never on repositories directly;
   - client `lib/domain/` must not import `data/` or `ui/`;
   - cubits must not import `data/service/`.
5. After Dart edits under `lib/`, run the custom-lint script for that package and
   re-read `scripts/custom-lint-baseline.txt` first — the baseline drifts down:

```bash
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client
```

6. Every local test run goes through `scripts/run_with_test_cleanup.sh`. Each
   Verify command below is already one line; keep it one line.
7. After touching `schema.graphql`, a `.graphql` document or a Drift table, run
   codegen locally and commit **sources only** (D18):

```bash
cd packages/client && dart run build_runner build --delete-conflicting-outputs
```

8. Tests tagged `pg` use a disposable database. Never reset the shared `postgres`.
9. Do not run `flutter analyze` to check custom lints — it silently reports clean.

---

## 5. Unit manifest

| Unit | Purpose | Depends on | Commit subject |
|------|---------|------------|----------------|
| 00 | Journal and baseline | — | `docs: start issue 162/180 journal` |
| 01 | Server: drop auto-close on the last send | 00 | `fix(server): stop closing the review window on the last send` |
| 02 | Server: m0176 — `sent_at` + structured participant context | 01 | `feat(server): record send time and structured review context` |
| 03 | Server: optional targets, viewer optionality, counters | 02 | `feat(server): make leaver reviews optional for the package` |
| 04 | Server: GraphQL surface + client `schema.graphql` | 03 | `feat(server): expose review package state on the API` |
| 05 | Server: author nudge when required packages are complete | 01, 04 | `feat(server): notify the author when reviews are complete` |
| 06 | Server: reopen announces itself | 04 | `feat(server): tell reviewers when a review window is cancelled` |
| 07 | Client: l10n keys (additive) | 00 | `chore(client): review package copy` |
| 08 | Client domain: `ReviewPackageState` (pure) | 07 | `feat(client): derive review package state` |
| 09 | Client data: role, optionality, counters, context, sheet | 04, 08 | `feat(client): plumb optional reviewers and package status` |
| 10 | Checklist: sections, progress, sent states | 09 | `fix(client): show whether the review package was sent` |
| 11 | Checklist: paused / closed classification | 10 | `fix(client): explain a review window cancelled by the author` |
| 12 | HUD + banner by package state | 09 | `fix(client): stop re-offering a review that was already sent` |
| 13 | My Work: package state on review cards | 09, 12 | `fix(client): stop re-offering a sent review in My Work` |
| 14 | Author dialogs + Updates rows | 05, 06, 09 | `feat(client): state the consequences of closing and reopening` |
| 15 | Release metadata 7.16.0 | 07–14 | `chore: release review-package client 7.16.0` |
| 16 | Closeout | 01–15 | `test: close issues 162 and 180` |

Never parallelize 02/03/04 (one DTO round trip) or 09/10 (entity and screen).

---

## UNIT 00 — Journal and baseline

**Owns**

```text
docs/plans/issue-162-180-review-package-state-journal.md          new
```

**Steps**

1. Create the journal with a `# Issue 162/180 implementation journal` heading.
2. Run and record, verbatim:

```bash
cd /home/vader/MY_SRC/tentura && git rev-parse HEAD && git branch --show-current && git status --short
```
```bash
cd /home/vader/MY_SRC/tentura && ls packages/server/lib/data/database/migration/ | sort -V | tail -3 && grep -n "^version:" packages/client/pubspec.yaml && grep -o 'flutter_bootstrap.js?v=[0-9.]*' packages/client/web/index.html && grep -n "kDefaultMinClientVersion = " packages/server/lib/env.dart
```

3. Compare each value with §3. Record every difference; do not "fix" anything.
4. Copy the §5 manifest into the journal as an unchecked list.
5. Record `plan revision 3, decisions D1–D19 acknowledged`.

**Acceptance** — the journal exists, the baseline block is filled from real
command output, and any drift from §3 is written down rather than silently
accepted.

**Do not** — do not modify, stage or revert any pre-existing file in the
worktree.

---

## UNIT 01 — Server: no auto-close on the last send

**Owns**

```text
packages/server/lib/domain/use_case/evaluation_case.dart
packages/server/test/domain/evaluation/evaluation_case_test.dart
packages/client/integration_test/support/e2e_test_helpers.dart
packages/server/test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart
docs/beacon-evaluation-principles.md
```

**Read first**

- `packages/server/lib/domain/use_case/evaluation_case.dart` — `evaluationFinalize`
  (around `:1445`), `_autoCloseReviewWindow` (around `:1497`), `closeNow`
  (around `:499`), `_ensureExpiredClosed` (`:148`).

**Steps**

1. In `evaluationFinalize`, delete exactly this trailing block:

```dart
    if (await _canCloseNow(beaconId: beaconId)) {
      await _autoCloseReviewWindow(beaconId: beaconId, actorUserId: userId);
    }
```

   `return true;` stays. Everything above it — `_ensureExpiredClosed`,
   `_requireLiveReview`, the readiness loop, the status write and
   `settleReviewerObligationOnPackageSend` — is untouched in this unit.
2. Delete the whole `_autoCloseReviewWindow` method and its doc comment. After
   step 1 it has no caller: `closeNow` (`:543`) and the expiry sweep
   (`attention_expiry_sweep_case.dart:43`) call `closeAndFinalize` directly.
   Confirm with:

```bash
cd /home/vader/MY_SRC/tentura && grep -rn "_autoCloseReviewWindow" packages/server/lib packages/server/test
```

   If that prints any line after your edit, you deleted the wrong thing — restore
   and record `BLOCKED`.
3. Do not touch `closeNow`. Its `_canCloseNow` gate is D3.
4. `packages/client/integration_test/support/e2e_test_helpers.dart` around
   `:1015` currently accepts a finished/archived request as an alternative to an
   explicit close. Change it to: assert the request is still in review after the
   last send, then perform the explicit author close, then assert closed.
5. `packages/server/test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart`
   around `:313` returns a constant `finalizeStatus: closed` without reading the
   real outcome. Make it read the actual status and perform an explicit close.
6. In `docs/beacon-evaluation-principles.md`, update the sentence that describes a
   window closing when the last package is sent. The close paths are now: author
   close-now, or deadline. Keep the sentence about unsent rows being discarded —
   that is still true.

**Tests** — in `packages/server/test/domain/evaluation/evaluation_case_test.dart`,
add to the existing finalize group:

- `finalize by the last required reviewer leaves the window open` — beacon stays
  `reviewOpen`, the window row keeps `status == 0`, no trust pairs written.
- `canCloseNow becomes true after the last required package` — assert
  `reviewWindowStatus(author).canCloseNow == true` right after that send.
- `author closeNow still closes and finalizes` — unchanged behaviour.
- `finalize after the deadline still closes through the expiry sweep` — advance
  the clock past `closesAt`, call `evaluationFinalize`, assert the window closed.
  This is intended (D2), not a bug.

**Verify**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg
```

**Acceptance** — a successful send before the deadline never closes the window;
deadline finalization, including a sweep triggered by an API call, still works;
`grep -rn "_autoCloseReviewWindow"` finds nothing.

**Do not** — do not add a "close" parameter to `evaluationFinalize`; do not touch
`_canCloseNow`; do not change `closeAndFinalize`.

---

## UNIT 02 — Server: m0176 (`sent_at` + structured participant context)

**Owns**

```text
packages/server/lib/data/database/migration/m0176.dart                                    new
packages/server/lib/data/database/migration/_migrations.dart
packages/server/lib/data/database/table/beacon_review_statuses.dart
packages/server/lib/data/database/table/beacon_evaluation_participants.dart
packages/server/lib/domain/port/evaluation_repository_port.dart
packages/server/lib/domain/entity/evaluation/beacon_evaluation_record.dart
packages/server/lib/data/mapper/evaluation_mapper.dart
packages/server/lib/data/repository/evaluation_repository.dart
packages/server/lib/data/repository/mock/evaluation_repository_mock.dart
packages/server/lib/domain/use_case/evaluation/evaluation_participant_draft.dart
packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart
packages/server/lib/domain/use_case/evaluation_case.dart
packages/server/test/domain/evaluation/evaluation_participant_graph_builder_test.dart
packages/server/test/data/repository/evaluation_repository_review_status_pg_test.dart     new
```

**Read first**

- `packages/server/lib/data/database/migration/m0175.dart` — the migration file
  shape (`part of '_migrations.dart';` then `final m0175 = Migration('0175', [...]);`).
- `packages/server/lib/data/database/migration/_migrations.dart:180` (the `part`
  list) and `:361` (the migration list).
- `packages/server/lib/data/mapper/evaluation_mapper.dart:19` —
  `beaconEvaluationParticipantToRecord`.
- `packages/server/lib/domain/port/evaluation_repository_port.dart:38` —
  `insertParticipant`.
- `packages/server/lib/data/repository/evaluation_repository.dart:389` — the
  `2 → 1` demotion inside `submitEvaluationAtomic`.
- An existing `*_pg_test.dart` under `packages/server/test/data/repository/` for
  the PG test harness shape.

**Steps**

1. Create `packages/server/lib/data/database/migration/m0176.dart`:

```dart
part of '_migrations.dart';

/// Issues #162/#180: a review package must be able to say whether it was ever
/// sent (`sent_at`), and participant context must be structured so the client
/// can localize it instead of printing server-built English.
final m0176 = Migration('0176', [
  '''
ALTER TABLE public.beacon_review_status
  ADD COLUMN IF NOT EXISTS sent_at timestamptz;
''',
  '''
UPDATE public.beacon_review_status
   SET sent_at = updated_at
 WHERE status = 2 AND sent_at IS NULL;
''',
  '''
ALTER TABLE public.beacon_evaluation_participant
  ADD COLUMN IF NOT EXISTS committed_at timestamptz,
  ADD COLUMN IF NOT EXISTS offer_message text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS forwarder_display_name text;
''',
]);
```

2. Register it in `_migrations.dart`: add `part 'm0176.dart';` after
   `part 'm0175.dart';`, and `m0176,` after `m0175,` in the migration list. Both
   edits are required; one alone leaves the migration unreachable.
3. Add the columns to the two Drift tables:

```dart
// beacon_review_statuses.dart, inside the class
late final sentAt = customType(PgTypes.timestampWithTimezone).nullable()();
```

```dart
// beacon_evaluation_participants.dart, inside the class
late final committedAt =
    customType(PgTypes.timestampWithTimezone).nullable()();
late final offerMessage = text().withDefault(const Constant(''))();
late final forwarderDisplayName = text().nullable()();
```

   Copy the exact `customType(PgTypes.timestampWithTimezone)` spelling from the
   existing `createdAt` in `beacon_review_statuses.dart`. Then run the server
   Drift codegen:

```bash
cd packages/server && dart run build_runner build --delete-conflicting-outputs
```

4. Write `sent_at` **only** on the finalize path. In
   `packages/server/lib/data/repository/evaluation_repository.dart`, extend
   `setReviewUserStatus` with an optional named parameter and update the port:

```dart
// port: evaluation_repository_port.dart
Future<void> setReviewUserStatus({
  required String beaconId,
  required String userId,
  required int status,
  bool markSent = false,
});
```

```dart
// repository: pass sentAt only when markSent is true
.update(
  (o) => o(
    status: Value(status),
    updatedAt: Value(PgDateTime(DateTime.timestamp())),
    sentAt: markSent
        ? Value(PgDateTime(DateTime.timestamp()))
        : const Value.absent(),
  ),
);
```

   In `evaluationFinalize`, the existing call becomes
   `setReviewUserStatus(..., status: 2, markSent: true)`.
   **`sent_at` is never cleared.** The `2 → 1` demotion at
   `evaluation_repository.dart:392` must keep touching `status` only — do not add
   `sent_at` to that statement. That is exactly what makes "sent, then edited"
   distinguishable (D11).
5. Structured participant context. In
   `evaluation_participant_draft.dart`, add three fields to the draft:
   `DateTime? committedAt`, `String offerMessage` (default `''`),
   `String? forwarderDisplayName`. In
   `evaluation_participant_graph_builder.dart`, `_committerParticipant` fills them
   from the help offer (`offer.createdAt`, `offer.message`) and the resolved
   forwarder name; forwarder drafts leave `committedAt` null and
   `offerMessage` empty. **Keep writing `contributionSummary` and `causalHint`
   exactly as today**, including the ` — participation ended` suffix — the legacy
   columns stay (D9). Do not copy that suffix into the new fields.
6. Plumb the round trip. Every hop must be updated or the new fields silently
   vanish:
   - `insertParticipant` in the port and the repository gains
     `DateTime? committedAt`, `String offerMessage = ''`,
     `String? forwarderDisplayName`;
   - `BeaconEvaluationParticipantRecord`
     (`beacon_evaluation_record.dart:31`) gains the same three fields;
   - `beaconEvaluationParticipantToRecord` (`evaluation_mapper.dart:19`) maps
     them, converting `r.committedAt?.dateTime`;
   - the participant insert loop inside `beaconClose`
     (`evaluation_case.dart:294`) passes the draft's new fields;
   - `evaluation_repository_mock.dart` and any other implementation of the port
     compile against the new signature.

**Tests**

- `packages/server/test/domain/evaluation/evaluation_participant_graph_builder_test.dart`:
  - `committer draft carries the offer date and message`;
  - `former committer keeps the original offer date, not the reopen time`;
  - `offer without a message yields an empty offerMessage`;
  - `forwarder draft has no committedAt`.
- New `packages/server/test/data/repository/evaluation_repository_review_status_pg_test.dart`,
  tagged `pg`:
  - `finalize stamps sent_at`;
  - `editing a card after send demotes status to 1 and keeps sent_at`;
  - `reopen deletes the review status row entirely`.

**Verify**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation --exclude-tags pg
```
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/data/repository/evaluation_repository_review_status_pg_test.dart --tags pg
```

**Acceptance** — the database can answer "was this package ever sent, and when",
which nothing in the system could answer before; the legacy context columns are
still written.

**Do not** — do not drop or stop writing `contribution_summary` / `causal_hint`;
do not clear `sent_at` anywhere; do not add a new status code.

---

## UNIT 03 — Server: optional targets, viewer optionality, counters

**Owns**

```text
packages/server/lib/domain/use_case/evaluation_case.dart
packages/server/lib/domain/entity/gql_public/evaluation_participant_result.dart
packages/server/lib/domain/entity/gql_public/review_window_status_result.dart
packages/server/test/domain/evaluation/evaluation_case_test.dart
```

**Read first**

- `evaluation_case.dart:609` `evaluationParticipants`, `:759`
  `evaluationDraftParticipants` (its result constructor is around `:810`),
  `:1014` `reviewWindowStatus`, `:1445` `evaluationFinalize`, `:591`
  `_canCloseNow`.
- `packages/server/lib/domain/evaluation/beacon_evaluation_row_status.dart` —
  `draft = 0, submitted = 1, final_ = 2, responded = 3`.

**Steps**

1. `EvaluationParticipantResult` gains:

```dart
/// True when this target's role is formerCommitter: reviewing them is optional
/// and never gates the package (#180).
final bool isOptional;

/// BeaconEvaluationRowStatus of the stored row, or -1 when there is no row.
final int rowStatus;
```

   Leave `isSubmitted` untouched; the client stops reading it in UNIT 09.
2. Fill both fields in **both** endpoints — they publish the same GraphQL type
   (`query_evaluation.dart:25`), and a weak executor typically updates only the
   first:
   - `evaluationParticipants` (`:609`): `isOptional` from
     `EvaluationParticipantRole.fromDb(row.role) == EvaluationParticipantRole.formerCommitter`,
     `rowStatus` from `ev?.status ?? -1`;
   - `evaluationDraftParticipants` (`:759`, constructor `:810`): the same
     `isOptional` predicate, `rowStatus` from the draft row it already loads.
3. In `evaluationFinalize`, skip optional targets in the readiness loop. Replace
   the existing loop with:

```dart
    final participantRows =
        await _evaluationRepository.listParticipants(beaconId);
    final partByUser = {for (final p in participantRows) p.userId: p};
    for (final v in vis) {
      final target = partByUser[v.participantId];
      if (target == null) {
        continue; // stale visibility row: nothing to require
      }
      if (EvaluationParticipantRole.fromDb(target.role) ==
          EvaluationParticipantRole.formerCommitter) {
        continue; // D6/D7: optional target never gates the package
      }
      final ev = byTarget[v.participantId];
      final ready = ev != null &&
          (ev.status == BeaconEvaluationRowStatus.draft ||
              ev.status == BeaconEvaluationRowStatus.submitted);
      if (!ready) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.notEligible,
          description: 'All review targets must be ready before send',
        );
      }
    }
```

   Optionality gates the **button**, never the data: an optional row that exists
   in a sent package is still counted at close.
4. `ReviewWindowStatusResult` gains nine fields with exactly these meanings.
   Viewer-scoped fields are computed from `listVisibilityForEvaluator` like
   today's counters (`:1033`); beacon-scoped fields from
   `listReviewStatusesForBeacon` and `listParticipants`:

```text
requiredTotal          viewer-scoped  visible targets whose role != formerCommitter
requiredReviewed       viewer-scoped  of those, targets with a stored row
optionalTotal          viewer-scoped  visible targets whose role == formerCommitter
optionalReviewed       viewer-scoped  of those, targets with a stored row
viewerPackageOptional  viewer-scoped  the VIEWER's own role == formerCommitter
sentAt                 viewer-scoped  ISO-8601 of the viewer's own send, or null
allRequiredSent        beacon-scoped  author + current committers all at status 2
unsentStartedPackages  beacon-scoped  count of reviewers at status 1
sentReviewerCount      beacon-scoped  count of reviewers at status 2
```

   `viewerPackageOptional` cannot be derived on the client: self pairs are
   excluded from visibility (`evaluation_visibility_rules.dart:36`), so the target
   list never reveals the viewer's own role.
   **Keep `reviewedCount` and `totalCount`** — `ReviewWindowMenuSnapshot` still
   reads them (`beacon_view_status_bottom_sheet.dart:40`).

**Tests** — in `packages/server/test/domain/evaluation/evaluation_case_test.dart`:

- `finalize succeeds with an untouched former committer`;
- `finalize still fails with an untouched current committer`;
- `former committer finalize does not change canCloseNow`;
- `a softened committer is optional` — build the fixture through the same
  commitment events the graph builder reads, then assert `isOptional == true`;
- `counters split required and optional` — 2 required / 1 optional with one
  optional answered → `requiredTotal 2, requiredReviewed 2, optionalTotal 1,
  optionalReviewed 1`;
- `viewerPackageOptional is true only for the former committer`;
- `draft participants carry isOptional and rowStatus`.

**Verify**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg
```

**Acceptance** — a package with an untouched leaver can be sent; a package with an
untouched current committer cannot; both participant endpoints return the new
fields.

**Do not** — do not change `_canCloseNow` or
`_requiredPackagesAllSentLocked`; they already exclude former committers. Do not
delete `reviewedCount` / `totalCount`.

---

## UNIT 04 — Server: GraphQL surface and the client schema

**Owns**

```text
packages/server/lib/api/controllers/graphql/custom_types.dart
packages/server/lib/api/controllers/graphql/mappers/gql_v2_dto_maps.dart
packages/client/lib/data/gql/schema.graphql
```

**Read first**

- `custom_types.dart:925` `gqlTypeEvaluationParticipant`, `:971`
  `gqlTypeReviewWindowStatus`.
- `gql_v2_dto_maps.dart:130` `reviewWindowStatusToGqlMap`.

**Steps**

1. On `gqlTypeEvaluationParticipant` add:

```dart
field('isOptional', graphQLBoolean.nonNullable()),
field('rowStatus', graphQLInt.nonNullable()),
field('committedAt', graphQLString),
field('offerMessage', graphQLString.nonNullable()),
field('forwarderDisplayName', graphQLString),
```

2. On `gqlTypeReviewWindowStatus` add the nine fields from UNIT 03 §4:
   `requiredTotal`, `requiredReviewed`, `optionalTotal`, `optionalReviewed`,
   `unsentStartedPackages`, `sentReviewerCount` as `graphQLInt`;
   `viewerPackageOptional`, `allRequiredSent` as `graphQLBoolean`; `sentAt` as
   `graphQLString`.
3. Mirror every field in the DTO maps. `committedAt` and `sentAt` are written as
   `dto.x?.toUtc().toIso8601String()`, matching `openedAt` / `closesAt`.
4. Update `packages/client/lib/data/gql/schema.graphql` by hand so ferry can see
   the new fields — nothing propagates the server's custom types into that file
   (D18). Add the same fields to the `EvaluationParticipant` and
   `ReviewWindowStatus` types there, with GraphQL nullability matching step 1–2.
5. Do not change any client `.graphql` document yet. This unit only makes them
   possible.

**Verify**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg
```
```bash
cd /home/vader/MY_SRC/tentura && grep -n "viewerPackageOptional\|unsentStartedPackages\|rowStatus" packages/client/lib/data/gql/schema.graphql
```

**Acceptance** — server tests green and the grep prints the new fields from the
client schema file.

---

## UNIT 05 — Server: author nudge when required packages are complete

**Owns**

```text
packages/server/lib/domain/attention/attention_models.dart
packages/server/lib/domain/attention/attention_policy.dart
packages/server/lib/domain/use_case/attention_intent_case.dart
packages/server/lib/domain/use_case/evaluation_case.dart
docs/contracts/updates-event-contract.json
packages/server/test/architecture/updates_event_contract_test.dart
packages/server/test/domain/evaluation/evaluation_case_test.dart
```

**Read first**

- `attention_models.dart:9` — the `AttentionEventType` enum. The wire name is the
  enum's `name`, resolved by `attentionEventTypeFromWireName`.
- `attention_policy.dart` — the six switches that must all get a case. Follow
  `AttentionEventType.reviewOpened` through the file: `:65` suppression, `:120`
  category, `:160` access policy, `:231` destination, `:274` requiresAction,
  `:312` presentation key.
- `attention_intent_case.dart:322` — `reviewOpened`, the builder shape to copy.
- `docs/contracts/updates-event-contract.json` — the `eventTypes` and `producers`
  arrays; `updates_event_contract_test.dart:148` asserts them as an exact set.
- `transactional_attention_case.dart:14` — the transaction boundary.

**Steps**

1. Add `reviewAllPackagesIn` to `AttentionEventType` (after `reviewOpened`). Its
   wire name is `reviewAllPackagesIn`.
2. Add a case in every switch in `attention_policy.dart`. A missing case is a
   compile error for exhaustive switches and a wrong default for the others —
   check all six:

```text
_suppression      → AttentionSuppressionClass.standard
_category         → NotificationCategory.unblocksMe
_accessPolicy     → the same branch as reviewOpened (beacon content list at :160)
_destination      → AttentionDestination(kind: AttentionDestinationKind.review,
                                         targetEntityId: role.beaconId)
_requiresAction   → false                      // information, not an obligation
_presentationKey  → 'review_all_packages_in'
```

3. Add the intent builder in `attention_intent_case.dart`, modelled on
   `reviewOpened` (`:322`) but addressed to one recipient:

```dart
  Future<AttentionDispatchIntent> reviewAllPackagesIn({
    required String beaconId,
    required String beaconTitle,
    required String authorUserId,
    required String sourceEventKey,
  }) => fromBeaconNotification(
    notification: BeaconNotificationIntent(
      kind: NotificationKind.reviewReady,
      priority: NotificationPriority.normal,
      beaconId: beaconId,
      actorUserId: authorUserId,
      beaconTitle: beaconTitle,
      admittedUserIds: [authorUserId],
    ),
    eventType: AttentionEventType.reviewAllPackagesIn,
    sourceEventKey: sourceEventKey,
    resolveContext: false,
  );
```

4. Emit it from `evaluationFinalize`, inside the existing transactional attention
   boundary together with the status write, so a crash cannot leave a sent package
   without its notification:
   - **before** writing status `2`, evaluate `_canCloseNow(beaconId)` and keep the
     result as `wasCloseableBefore`;
   - after the status write, evaluate it again as `isCloseableNow`;
   - emit only when `!wasCloseableBefore && isCloseableNow` — the transition,
     never the state. A re-send after an edit must not emit a second time;
   - recipient: the request author, including when the author is the last sender;
   - `sourceEventKey`: `'review_all_in:$beaconId:${window.openedAt.toUtc().toIso8601String()}'`.
     Deterministic, and unique per window because a reopen deletes the window row
     — no generation id needed (D5);
   - payload: beacon id and title only. **No last-sender identity, no timestamp of
     the triggering send.** The dispatch layer rejects a repeated key whose actor
     or payload differs (`attention_dispatch_repository.dart:40`), so an unstable
     payload turns a harmless retry into an error.
5. Add the event to `docs/contracts/updates-event-contract.json` in both the
   `eventTypes` and `producers` arrays, copying the `reviewOpened` entries' shape
   (`:70` and `:388`):

```json
{
  "eventType": "reviewAllPackagesIn",
  "producer": "EvaluationCase.evaluationFinalize",
  "recipientCategory": "beacon_author",
  "destinationFamily": "review",
  "muteability": "standard",
  "coveringTest": "packages/server/test/domain/evaluation/evaluation_case_test.dart"
}
```

   Use the `recipientCategory` spelling the contract test accepts; if
   `beacon_author` is not an accepted value, use the one the test's allowed set
   contains and record the choice in the journal.

**Tests** — in `evaluation_case_test.dart`:

- `the last required package notifies the author exactly once`;
- `an edit and re-send after that emits no second notification`;
- `the author as last sender still gets the notification`;
- `a required reviewer editing after the nudge makes canCloseNow false again`
  (the historical notification is not retracted).

Plus a `pg`-tagged concurrency test (serial transactions, in the new PG file from
UNIT 02 or a sibling): `two simultaneous last sends emit one notification`.

**Verify**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart test/architecture/updates_event_contract_test.dart --exclude-tags pg
```

**Acceptance** — removing auto-close (UNIT 01) no longer leaves the author
unaware, and the nudge is emitted exactly once per window.

**Do not** — do not set `requiresAction: true`; do not reuse the `reviewOpened`
event type; do not put the triggering send's time in the payload.

---

## UNIT 06 — Server: reopen announces itself

**Owns**

```text
packages/server/lib/domain/attention/attention_models.dart
packages/server/lib/domain/attention/attention_policy.dart
packages/server/lib/domain/use_case/attention_intent_case.dart
packages/server/lib/domain/use_case/evaluation_case.dart
docs/contracts/updates-event-contract.json
packages/server/test/architecture/updates_event_contract_test.dart
packages/server/test/domain/evaluation/evaluation_case_test.dart
```

**Read first**

- `evaluation_case.dart:394` `reopenFromReview`, in particular the order:
  `downgradeSubmittedReviewsToDraft` → `deleteReviewScaffoldingForBeacon` →
  `supersedeReviewObligationsOnReopen`.
- UNIT 05's steps: this unit repeats them for a second event type.

**Steps**

1. Add `reviewWindowCancelled` to `AttentionEventType` and give it a case in all
   six policy switches, with `_requiresAction → false`,
   `_presentationKey → 'review_window_cancelled'`, destination
   `AttentionDestinationKind.beacon` with `role.beaconId`, category
   `NotificationCategory.unblocksMe`, suppression `standard`, and the same access
   branch as `reviewOpened`.
2. Add a `reviewWindowCancelled` intent builder taking
   `Set<String> recipientUserIds`, modelled on `reviewOpened`.
3. In `reopenFromReview`, **before** `deleteReviewScaffoldingForBeacon` deletes
   the rows, read the enrolled reviewer ids with
   `listReviewStatusesForBeacon(beaconId)`. Emit the event to all of them except
   the acting author, inside the same transaction that already records the status
   change intent. Reading after the delete returns an empty set — that is the
   mistake this step exists to prevent.
4. Keep `supersedeReviewObligationsOnReopen`. Reviewers whose receipt was already
   `resolved` are exactly the case this event covers; the existing query only
   touches outstanding ones
   (`attention_system_settlement_repository.dart:115`).
5. Add the contract entry as in UNIT 05, producer
   `EvaluationCase.reopenFromReview`.

**Tests** — in `evaluation_case_test.dart`:

- `reopen notifies every enrolled reviewer` — one reviewer sent, one not: two
  events;
- `reopen does not notify the acting author`;
- `reopen still supersedes the one outstanding obligation`.

**Verify**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart test/architecture/updates_event_contract_test.dart --exclude-tags pg
```

**Acceptance** — nobody's completed work disappears silently.

---

## UNIT 07 — Client: l10n keys

**Owns**

```text
packages/client/l10n/app_ru.arb
packages/client/l10n/app_en.arb
```

**Read first**

- `packages/client/l10n/app_en.arb` — an entry with placeholders, e.g.
  `evaluationProgress` and its `@evaluationProgress` metadata block.

**Steps**

1. Add every key from §2 to **both** arb files with the RU and EN values from the
   table. Every key with placeholders also needs its `@key` metadata block:

```json
"evaluationProgressSplit": "{req} of {reqTotal} required · {opt} of {optTotal} optional",
"@evaluationProgressSplit": {
  "placeholders": {
    "req": {"type": "int"},
    "reqTotal": {"type": "int"},
    "opt": {"type": "int"},
    "optTotal": {"type": "int"}
  }
}
```

   `date`, `name`, `message` and `title` are `{"type": "String"}`; `count`,
   `total`, `sent` and the four progress numbers are `{"type": "int"}`.
2. Change the three existing keys marked *(changed)* in §2:
   `evaluationSubmitFinish`, `beaconHudActReviewContributions`,
   `beaconReviewReopenBody` (which gains a `sent` placeholder).
3. **Additive only.** Delete no key here, even one you believe is now unused;
   deletions happen in UNIT 16 after the consumers have moved (D17).
4. Regenerate l10n (the client build step that produces `lib/ui/l10n/**`).

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/ui --dart-define=ENV=test --dart-define-from-file=env/test.env
```
```bash
bash scripts/check-user-facing-terminology.sh
```

**Acceptance** — the new keys compile with their placeholders and the terminology
script passes.

**Do not** — do not hand-edit generated `lib/ui/l10n/l10n_*.dart`; edit the arb
files and regenerate.

---

## UNIT 08 — Client domain: `ReviewPackageState`

**Owns**

```text
packages/client/lib/features/evaluation/domain/review_package_state.dart      new
packages/client/test/features/evaluation/review_package_state_test.dart       new
```

**Steps**

1. Create the file with exactly this content (comments included — they encode the
   decisions):

```dart
/// The state of one reviewer's package in one review window.
///
/// This is the primary variable of every review surface (#162). Checklist
/// completeness is only progress and never decides which action is offered.
enum ReviewPackageState {
  /// No window, or the viewer is not a reviewer in it.
  notEnrolled,

  /// Enrolled, but the window has no targets for this viewer.
  empty,

  /// Not sent, some required target still unanswered.
  inProgress,

  /// Not sent, every required target answered.
  readyToSend,

  /// Sent and unchanged since.
  sent,

  /// Sent once, then edited: the server demoted the package and it must be sent
  /// again or it is discarded when the request closes.
  changedNotSent,

  /// The window disappeared while the viewer was enrolled (the author reopened
  /// the request).
  paused,

  /// The window closed and the viewer had sent.
  closed,

  /// The window closed and the viewer had not sent; the rows were deleted.
  closedUnsent,
}

/// Derives the package state.
///
/// [userReviewStatus] is the server's per-user code: -1 not enrolled,
/// 0 not started, 1 in progress, 2 sent, 3 legacy skipped, 4 expired unsent.
/// It cannot distinguish "never sent" from "sent then edited" on its own —
/// [sentAt] does that (see issue #162).
ReviewPackageState deriveReviewPackageState({
  required bool beaconIsInReview,
  required bool beaconIsClosed,
  required bool hasWindow,
  required bool windowComplete,
  required int? userReviewStatus,
  required DateTime? sentAt,
  required int requiredTotal,
  required int requiredAnswered,
  required int totalTargets,
}) {
  if (windowComplete || beaconIsClosed) {
    return sentAt != null
        ? ReviewPackageState.closed
        : ReviewPackageState.closedUnsent;
  }
  if (userReviewStatus == 4) {
    return ReviewPackageState.closedUnsent;
  }
  if (!hasWindow) {
    // A request that never had a window is not "paused" for a first-time
    // visitor; only a viewer who is in review can have lost one.
    return beaconIsInReview
        ? ReviewPackageState.notEnrolled
        : ReviewPackageState.paused;
  }
  if (userReviewStatus == null || userReviewStatus < 0) {
    return ReviewPackageState.notEnrolled;
  }
  if (userReviewStatus == 2) {
    return ReviewPackageState.sent;
  }
  if (totalTargets == 0) {
    return ReviewPackageState.empty;
  }
  final allRequiredAnswered = requiredAnswered >= requiredTotal;
  if (sentAt != null) {
    return allRequiredAnswered
        ? ReviewPackageState.changedNotSent
        : ReviewPackageState.inProgress;
  }
  return allRequiredAnswered
      ? ReviewPackageState.readyToSend
      : ReviewPackageState.inProgress;
}
```

2. The order of the checks is frozen. Do not reorder them, do not "simplify" them
   into a `switch`, and do not add inputs.

**Tests** — table-driven in the new test file, one expectation per row:

- all nine states reachable;
- `status 1 with sentAt == null` → `readyToSend` or `inProgress` by completeness,
  **never** `changedNotSent` (this is the regression the unit exists for);
- `status 3` behaves like `status 0`;
- `requiredTotal == 0` with `totalTargets > 0` (all targets optional) →
  `readyToSend`;
- `totalTargets == 0` → `empty`, never `readyToSend`;
- `sentAt != null` and a required answer removed → `inProgress`;
- `!hasWindow && beaconIsInReview` → `notEnrolled`;
- `!hasWindow && !beaconIsInReview` → `paused`;
- `windowComplete` with and without `sentAt` → `closed` / `closedUnsent`.

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test test/features/evaluation/review_package_state_test.dart --dart-define=ENV=test --dart-define-from-file=env/test.env
```

**Acceptance** — the file has no Flutter import and every UI decision about the
package can be written as a switch over this enum.

---

## UNIT 09 — Client data: role, optionality, context, sheet

**Owns**

```text
packages/client/lib/features/evaluation/data/gql/evaluation_participants.graphql
packages/client/lib/features/evaluation/data/gql/evaluation_draft_participants.graphql
packages/client/lib/features/evaluation/data/gql/review_window_status.graphql
packages/client/lib/features/evaluation/data/repository/evaluation_repository.dart
packages/client/lib/features/evaluation/domain/entity/evaluation_participant.dart
packages/client/lib/features/evaluation/domain/entity/review_window_info.dart
packages/client/lib/features/evaluation/ui/bloc/evaluation_state.dart
packages/client/lib/features/evaluation/ui/presenter/evaluation_participant_context.dart   new
packages/client/lib/features/evaluation/ui/widget/evaluation_detail_sheet.dart
packages/client/test/features/evaluation/evaluation_state_test.dart
packages/client/test/features/evaluation/evaluation_participant_context_test.dart          new
packages/client/test/features/evaluation/evaluation_detail_sheet_test.dart
```

**Read first**

- `evaluation_repository.dart:494` — the role mapping switch.
- `evaluation_detail_sheet.dart:140` and `:151` — two exhaustive role switches;
  `:238` — the only other reader of `contributionSummary`.
- `evaluation_participant.dart` and `review_window_info.dart` — freezed entities.

**Steps**

1. Add `formerCommitter` to the client `EvaluationParticipantRole` enum and map
   db `3` to it:

```dart
      3 => EvaluationParticipantRole.formerCommitter,
      _ => EvaluationParticipantRole.committer,
```

   Adding the enum case breaks the two exhaustive switches in
   `evaluation_detail_sheet.dart`. Handle `formerCommitter` there in **this**
   unit, with the same prompt copy as `committer`. The sheet's redesign is #76 and
   is not in scope.
2. `EvaluationParticipant` gains `isOptional` (`bool`, default `false`),
   `rowStatus` (`int`, default `-1`), `committedAt` (`DateTime?`), `offerMessage`
   (`String`, default `''`), `forwarderDisplayName` (`String?`), and:

```dart
  /// A stored row exists for this target, in any state the server counts as an
  /// answer. Mirrors evaluationFinalize's readiness predicate: draft(0),
  /// submitted(1), final(2). Do not widen this to `rowStatus >= 0`.
  bool get hasAnswer =>
      rowStatus == 0 || rowStatus == 1 || rowStatus == 2;
```

   Remove `contributionSummary` and `causalHint` from the entity, from the two
   `.graphql` participant documents and from the repository mapping. `causalHint`
   has no other reader; `contributionSummary`'s two readers are handled in step 4
   and UNIT 10.
3. `ReviewWindowInfo` gains the nine fields from UNIT 03 §4, with `sentAt` parsed
   into a `DateTime?`. **Keep** `viewerHasOutstandingReviewWork` and
   `viewerCanOpenReviewScreen` for now — UNIT 12 deletes them together with their
   last consumer (D17).
4. Create `evaluation_participant_context.dart`, a pure presenter used by **both**
   the list card and the detail sheet:

```dart
typedef EvaluationParticipantContext = ({
  /// Main line: who this person was in the request.
  String line,
  /// Second line when their participation ended, else null.
  String? endedLine,
  /// Their help-offer message in quotes, else null.
  String? offerLine,
});

EvaluationParticipantContext presentParticipantContext({
  required L10n l10n,
  required Locale locale,
  required EvaluationParticipant participant,
});
```

   Rules, in order:
   - forwarder → `line = evaluationContextForwarder`;
   - otherwise with `committedAt != null` and `forwarderDisplayName != null` →
     `evaluationContextCommittedVia(date, name)`;
   - otherwise with `committedAt != null` → `evaluationContextCommitted(date)`;
   - otherwise → `evaluationContextCommittedNoDate`. This is the row materialized
     before m0176; **never** fall back to a server string (D9);
   - `date` is `committedAt!.toLocal()` formatted with `DateFormat.yMMMd(locale.toLanguageTag())`;
   - `isOptional` → `endedLine = evaluationContextEnded`;
   - non-empty `offerMessage` → `offerLine = evaluationContextOffer(message)`.
5. `EvaluationState` gains:

```dart
  Iterable<EvaluationParticipant> get requiredParticipants =>
      participants.where((p) => !p.isOptional);

  Iterable<EvaluationParticipant> get optionalParticipants =>
      participants.where((p) => p.isOptional);

  bool get canFinalize {
    if (participants.isEmpty) return false;
    if (isDraftMode) return participants.every((p) => p.hasAnswered);
    return requiredParticipants.every((p) => p.hasAnswer);
  }
```

   A package whose targets are all optional is finalizable with nothing answered:
   intended, because sending settles the reviewer's own obligation.
6. Add the new fields to the three `.graphql` documents, then run client codegen.
   Commit sources only (D18).

**Tests**

- `evaluation_state_test.dart`: `canFinalize ignores optional targets`;
  `canFinalize still requires every required target`; `empty participants are not
  finalizable`.
- `evaluation_participant_context_test.dart`: one case per rule in step 4, in both
  RU and EN, including the null-`committedAt` fallback and the optional ended
  line.
- `evaluation_detail_sheet_test.dart`: `renders a former committer without
  crashing` (the role switch).

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

**Acceptance** — the client distinguishes a leaver from an active helper, and no
user-facing English string arrives from the server.

**Do not** — do not delete the two `ReviewWindowInfo` getters in this unit; do not
commit anything under `_g/`.

---

## UNIT 10 — Checklist: sections, progress, sent states

**Owns**

```text
packages/client/lib/features/evaluation/ui/screen/review_contributions_screen.dart
packages/client/lib/features/evaluation/ui/bloc/evaluation_cubit.dart
packages/client/lib/features/evaluation/ui/bloc/evaluation_state.dart
packages/client/lib/ui/test_ids.dart
packages/client/test/features/evaluation/review_contributions_screen_test.dart
packages/client/test/features/evaluation/evaluation_cubit_lifecycle_test.dart
```

**Read first**

- `review_contributions_screen.dart` — the bottom bar (around `:113`), the
  `_participantItems` builder (`:160`), `_ParticipantTile` (`:360`),
  `_ReviewActions` (`:460`).
- `evaluation_cubit.dart:248` `finalize`, `:56` `_emitNavigateBack`.
- `packages/client/lib/ui/test_ids.dart:140` — the evaluation ids.

**Steps**

1. `EvaluationState` exposes the package state:

```dart
  ReviewPackageState get packageState => deriveReviewPackageState(
    beaconIsInReview: beaconIsInReview,
    beaconIsClosed: beaconIsClosed,
    hasWindow: windowInfo?.hasWindow ?? false,
    windowComplete: windowInfo?.windowComplete ?? false,
    userReviewStatus: windowInfo?.userReviewStatus,
    sentAt: windowInfo?.sentAt,
    requiredTotal: requiredParticipants.length,
    requiredAnswered: requiredParticipants.where((p) => p.hasAnswer).length,
    totalTargets: participants.length,
  );
```

   `beaconIsInReview` / `beaconIsClosed` are two new `bool` fields on the state,
   defaulting to `true` / `false`, set from the window read. Do not reach into
   another feature's cubit for them.
2. `finalize()` stops navigating away on the live path:

```dart
  Future<void> finalize() async {
    if (state.isDraftMode) {
      _emitNavigateBack();      // draft mode is unchanged
      return;
    }
    if (!state.canFinalize) return;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _evaluationCase.finalize(state.beaconId);
      if (isClosed) return;
      await _refreshAfterSend();
    } catch (e) {
      if (isClosed) return;
      _emitSnackError(e);
    }
  }
```

   `_refreshAfterSend()` re-reads participants and the window and emits the new
   state. **If that refresh throws, do not fall back to the pre-send state**: the
   send succeeded. Keep the previous participants, set the window's
   `userReviewStatus` to `2` locally, and surface the refresh failure as a
   snackbar only.
3. Bottom bar by `state.packageState`:

```text
inProgress      evaluationProgressSplit + the existing remaining hint; CTA disabled
readyToSend     evaluationProgressSplit; CTA evaluationSubmitFinish; below it
                evaluationPackageSentHint as a muted hint
sent            evaluationPackageSentAt(date from windowInfo.sentAt) +
                evaluationPackageSentHint; one tonal button evaluationPackageDone
changedNotSent  evaluationPackageDirtyTitle + evaluationPackageDirtyBody;
                CTA evaluationSubmitChanges
empty           the existing evaluationEmptyTargets body; no CTA
```

   Test ids: keep `TestIds.evaluationSubmit` on the primary CTA in `readyToSend`
   and `changedNotSent`; add `evaluation.package_status` for the status text and
   `evaluation.done` for the tonal button, following the existing `TestIds` style.
   `evaluationPackageDone` pops to the request route; when the navigation stack
   has nothing to pop (deep-link entry), navigate to the request by
   `state.beaconId`.
4. Sections. Build the list as: the existing title and privacy rows, then the
   own-package notice, then the required section, then the optional section.

```text
if (windowInfo.viewerPackageOptional) → one muted paragraph
                                        evaluationOwnPackageOptional
Semantics(header: true) evaluationSectionRequired
  → the existing author / helper / forwarder grouping, over requiredParticipants
Semantics(header: true) evaluationSectionOptional        (omit when empty)
  → evaluationOptionalHint as a muted line under the header
  → optionalParticipants, minus locally skipped ids
```

5. Local skip (D8). The screen becomes a `StatefulWidget` holding
   `final _skipped = <String>{}`. An optional card's secondary action is
   `evaluationOptionalSkip`, which calls `setState(() => _skipped.add(userId))`
   and nothing else. Required cards keep `evaluationCannotEvaluate` unchanged.
   Skipping must not call the cubit and must not remove a stored row from the
   package.
6. Card subtitles come from `presentParticipantContext` (UNIT 09) — the three
   lines in order: `line`, `offerLine`, `endedLine`. Delete the direct
   `participant.contributionSummary` read.

**Tests** — in `review_contributions_screen_test.dart`:

- `first fill offers Send reviews, not Send changes` — the D11 regression;
- `required complete and optional untouched enables the CTA`;
- `after a send the screen stays and shows the sent status` — `evaluation.submit`
  is gone or disabled, `evaluation.package_status` shows the `sentAt` date;
- `editing a card after a send offers Send changes`;
- `skip hides an optional card without calling the cubit`;
- `skipping an optional card with a stored row keeps it in the package`;
- `viewerPackageOptional renders the own-package notice`;
- `sections render at 360px and textScaler 2.0` — pump at
  `MediaQuery(size: Size(360, 800), textScaler: TextScaler.linear(2))` and assert
  a participant card below the headers is actually built. A long header block can
  silently unbuild list items at that combination; assert the item, not the
  absence of an overflow error.

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

**Acceptance** — #162's criterion holds on this screen: after a complete checklist
the button submits and stays submitted, or names the real next step.

**Do not** — do not call `_emitNavigateBack()` on the live path; do not persist
the skip set; do not compare `userReviewStatus` to a number anywhere in the
screen — use `packageState`.

---

## UNIT 11 — Checklist: paused / closed classification

**Owns**

```text
packages/client/lib/features/evaluation/ui/bloc/evaluation_cubit.dart
packages/client/lib/features/evaluation/ui/bloc/evaluation_state.dart
packages/client/lib/features/evaluation/ui/screen/review_contributions_screen.dart
packages/client/test/features/evaluation/evaluation_cubit_lifecycle_test.dart
```

**Read first**

- `packages/client/lib/features/evaluation/data/model/evaluation_error_mapper.dart:6`
  — the existing mapper, already wired at
  `packages/client/lib/data/service/remote_api_client/build_client.dart:19`.
- `packages/client/lib/features/evaluation/domain/evaluation_exception.dart:16`
  — `EvaluationReviewWindowNotOpenException` (code 1401) and `:54`
  `EvaluationReviewWindowExpiredException` (1405). Both already exist.

**Steps**

1. Do **not** add a second error mapper. The typed exceptions already arrive.
2. The server raises `reviewWindowNotOpen` both after a reopen and after a final
   close (D12), so the cubit must classify by re-reading, not by code. Add:

```dart
  Future<void> _classifyLifecycleError() async {
    try {
      final window = await _evaluationCase.fetchReviewWindowStatus(
        state.beaconId,
      );
      if (isClosed) return;
      emit(state.copyWith(
        windowInfo: window,
        beaconIsInReview: /* from the window read */,
        beaconIsClosed: /* from the window read */,
        status: StateStatus.isSuccess,
      ));
    } catch (_) {
      // The classifying read failed: keep what we had and report normally.
      if (!isClosed) _emitSnackError(/* the original error */);
    }
  }
```

   Call it from the `on EvaluationReviewWindowNotOpenException` and
   `on EvaluationReviewWindowExpiredException` branches of
   `loadParticipantsOnly`, `submitOne`, `clearOne` and `finalize`, instead of
   `_emitSnackError`. `deriveReviewPackageState` then yields `paused`, `closed` or
   `closedUnsent` on its own.
3. The screen renders, replacing the whole body:

```text
paused        evaluationPausedTitle + evaluationPausedBody +
              one button evaluationPausedAction (to the request)
closed        evaluationClosedSentBody + a link to received reviews
closedUnsent  evaluationClosedUnsentBody + the same link
```

   No list, no CTA in any of the three. There is no read-only checklist (D13).
4. Scope the promise honestly: an idle screen learns about a reopen on the next
   user action or refresh, not spontaneously. Do not add polling, and do not write
   a test that asserts a spontaneous transition.

**Tests** — in `evaluation_cubit_lifecycle_test.dart`:

- `submitOne on a vanished window yields paused, not a snackbar`;
- `a completed window with sentAt yields closed`;
- `a completed window without sentAt yields closedUnsent`;
- `a failing classification read keeps the previous state and shows the error`;
- `the stale participant list is not rebuilt in paused`.

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

**Acceptance** — a reopen landing on an open checklist explains itself instead of
showing a raw error over a stale list.

---

## UNIT 12 — HUD and banner by package state

**Owns**

```text
packages/client/lib/features/beacon_view/ui/presenter/beacon_hud_author_action.dart
packages/client/lib/features/evaluation/ui/widget/review_window_banner_host.dart
packages/client/lib/features/evaluation/ui/widget/review_banner.dart
packages/client/lib/features/evaluation/domain/entity/review_window_info.dart
packages/client/test/features/beacon_view/beacon_hud_author_action_test.dart
packages/client/test/features/evaluation/review_window_banner_host_test.dart
```

**Read first**

- `beacon_hud_author_action.dart:138` `_reviewOpenAuthorAction` — the function
  that produces the #162 loop.
- `review_window_banner_host.dart:58` and `:84` — the two branches.

**Steps**

1. Replace `_reviewOpenAuthorAction` with a switch on the package state:

```dart
BeaconHudAuthorAction? _reviewOpenAuthorAction(BeaconViewState state) {
  final review = state.reviewWindowInfo;
  if (review == null || !review.hasWindow || review.windowComplete) return null;

  // The author's close action outranks any review action.
  if (review.canCloseNow == true) return BeaconHudAuthorAction.closeNow;

  return switch (reviewPackageStateOf(state)) {
    ReviewPackageState.inProgress ||
    ReviewPackageState.readyToSend ||
    ReviewPackageState.changedNotSent =>
      BeaconHudAuthorAction.reviewContributions,
    // Sent: the entry point must change shape, or #162 comes back.
    ReviewPackageState.sent ||
    ReviewPackageState.paused ||
    ReviewPackageState.closed ||
    ReviewPackageState.closedUnsent ||
    ReviewPackageState.notEnrolled ||
    ReviewPackageState.empty => null,
  };
}
```

   `reviewPackageStateOf(state)` is a small local helper that calls
   `deriveReviewPackageState` with the fields `BeaconViewState` already carries.
2. Delete `viewerHasOutstandingReviewWork` and `viewerCanOpenReviewScreen` from
   `ReviewWindowInfo`. This unit is their last consumer (D17). Confirm:

```bash
cd /home/vader/MY_SRC/tentura && grep -rn "viewerHasOutstandingReviewWork\|viewerCanOpenReviewScreen" packages/client/lib packages/client/test
```

3. Effect line: in `inProgress`, `beaconHudActEffectReviewProgress(count, total)`
   from the required counters; in `readyToSend` / `changedNotSent`, keep the
   existing neutral effect copy.
4. `ReviewWindowBannerHost` follows the §2.1 matrix. For a viewer in `sent`, the
   row is status text plus a **text** button `beaconHudReviewEdit` — never a
   filled button. The author waiting on other people sees
   `beaconHudWaitingForRequiredReviews`; a non-author who has sent sees
   `beaconHudWaitingForAuthorClose`.

**Tests** — table-driven over the nine states × (author, non-author) ×
`allRequiredSent`:

- `at most one primary review CTA per state`;
- `no primary review CTA in sent`;
- `the author keeps close-now in sent when allRequiredSent`;
- `the author waiting on others does not see the author-waiting copy`.

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/beacon_view test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

**Acceptance** — the #162 loop is impossible on the request screen, and the grep
in step 2 prints nothing.

---

## UNIT 13 — My Work: package state on review cards

**Owns**

```text
packages/client/lib/features/my_work/domain/derive_my_work_cards.dart
packages/client/lib/features/my_work/domain/use_case/my_work_case.dart
packages/client/lib/features/my_work/data/gql/my_work_review_windows.graphql
packages/client/lib/features/my_work/ui/widget/my_work_cards.dart
packages/client/lib/features/my_work/ui/widget/my_work_obligation_block.dart
packages/client/lib/domain/coordination/derive_beacon_coordination_phase.dart
packages/client/test/features/my_work/
```

**Read first**

- `derive_my_work_cards.dart:171` — `showReviewCta`, currently true for every
  `reviewOpen` card regardless of whether the viewer already sent.
- `my_work_case.dart:134` `loadReviewWindows` — today it fetches windows only for
  **authored** cards, only to set `showCloseNowCta`.
- `my_work_cards.dart:419` and `my_work_obligation_block.dart:96` — the two
  surfaces that render the review action.
- `derive_beacon_coordination_phase.dart:61` — the shared phase model also
  proposes `reviewContributions` for `reviewOpen`.

**Steps**

1. Widen `loadReviewWindows` to fetch for every card where the viewer may be a
   reviewer, not only authored ones, and select the new fields in
   `my_work_review_windows.graphql` (`userReviewStatus`, `sentAt`,
   `requiredTotal`, `requiredReviewed`, `optionalTotal`, `optionalReviewed`,
   `windowComplete`, `canCloseNow`, `allRequiredSent`).
2. Carry the resulting `ReviewPackageState` onto the card view model.
3. Drive both surfaces from it:

```text
inProgress | readyToSend | changedNotSent  → primary review CTA (as today)
sent                                       → demoted beaconHudReviewEdit +
                                             beaconHudReviewSent status
paused | closed | closedUnsent | empty     → no review affordance
```

   `showCloseNowCta` keeps its current meaning and stays independent.
4. If `derive_beacon_coordination_phase.dart` is used for this decision, gate its
   `reviewContributions` proposal on the same state rather than on the lifecycle
   alone. Do not change the phase model's other outputs.

**Tests** — in `packages/client/test/features/my_work/`:

- `a sent package shows no primary review CTA on the card`;
- `an edited package shows the send-changes affordance`;
- `an authored card with canCloseNow still shows close now`;
- `a card whose window is gone shows no review affordance`.

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/my_work --dart-define=ENV=test --dart-define-from-file=env/test.env
```

**Acceptance** — "no repeated primary review CTA" holds on **every** surface:
checklist, HUD, banner and My Work.

---

## UNIT 14 — Author dialogs and Updates rows

**Owns**

```text
packages/client/lib/features/beacon_view/ui/widget/beacon_hud_author_confirm_sheets.dart
packages/client/lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart
packages/client/lib/features/my_work/ui/widget/my_work_cards.dart
packages/client/lib/features/updates/updates_receipt_display_copy.dart
packages/client/test/features/beacon_view/
packages/client/test/features/updates/
```

**Read first**

- `beacon_hud_author_confirm_sheets.dart:72` — the HUD close confirm.
- `beacon_view_status_bottom_sheet.dart:292` — close executed **without** a
  confirm; `:296` — the reopen confirm.
- `my_work_cards.dart:395` — close executed **without** a confirm.
- `updates_receipt_display_copy.dart:166` and `:203` — presentation key → l10n.

**Steps**

1. There are **four** entries into close/reopen, not one. Route all four through a
   single shared confirm function so the new warnings cannot be bypassed. Put it
   next to the existing HUD confirm sheet and call it from the other three.
2. Close confirm body: `beaconReviewCloseNowBody`, plus
   `beaconReviewCloseNowDiscardNote(unsentStartedPackages)` when that
   **beacon-scoped** count is greater than zero. Do **not** compute it as
   `optionalTotal - optionalReviewed`: those are the viewer's own untouched
   optional targets, not other people's unsent packages.
3. Reopen confirm body: `beaconReviewReopenBody(sentReviewerCount)` when that
   count is greater than zero, otherwise `beaconReviewReopenBodyNoSent`.
4. Updates rows: add the two new presentation keys to
   `updates_receipt_display_copy.dart`:

```dart
  'review_all_packages_in' => l10n.updatesFallbackTitleReviewAllIn,
  'review_window_cancelled' => l10n.updatesFallbackTitleReviewCancelled,
```

   and the matching bodies in the body switch. `review_all_packages_in` navigates
   to the request; `review_window_cancelled` has no action. Neither is an
   obligation — do not add them to the obligation grouping in
   `group_my_work_obligations.dart`.

**Tests**

- one test per entry point: the close confirm appears and carries the body;
- `the discard note appears only when a package was started and not sent`;
- `the reopen confirm names the number of people who already sent`;
- `the reopen confirm without senders uses the short body`;
- Updates: both new rows render their title and body and neither is grouped as an
  obligation.

**Verify**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/beacon_view test/features/updates test/features/my_work --dart-define=ENV=test --dart-define-from-file=env/test.env
```

---

## UNIT 15 — Release metadata

**Owns**

```text
packages/client/pubspec.yaml
packages/client/web/index.html
packages/server/lib/env.dart
```

**Steps**

1. `packages/client/pubspec.yaml`: `version: 7.15.0` → `7.16.0`.
2. `packages/client/web/index.html`: `flutter_bootstrap.js?v=7.15.0` →
   `?v=7.16.0`.
3. `packages/server/lib/env.dart:67`:
   `kDefaultMinClientVersion = '7.10.0'` → `'7.16.0'`. The client is web-only with
   no users, so there are no legacy clients to support.

**Verify**

```bash
cd /home/vader/MY_SRC/tentura && grep -n "^version:" packages/client/pubspec.yaml && grep -o 'flutter_bootstrap.js?v=[0-9.]*' packages/client/web/index.html && grep -n "kDefaultMinClientVersion = " packages/server/lib/env.dart
```

**Acceptance** — all three values read `7.16.0`.

---

## UNIT 16 — Closeout

**Owns** — the journal, the l10n deletions deferred from UNIT 07, and any narrow
fix the suites demand.

**Steps**

1. Delete l10n keys whose last consumer is gone. Check each candidate first:

```bash
cd /home/vader/MY_SRC/tentura && grep -rn "evaluationListIntro" packages/client/lib packages/client/test
```

   Delete only keys where that prints nothing outside the arb and generated files.
2. Run every suite. Each command is one line:

```bash
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client
```
```bash
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
```
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg
```
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test --tags pg
```
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env
```
```bash
bash scripts/check-user-facing-terminology.sh
```

   The `pg` run is **mandatory**. The acceptance of UNITs 02, 03 and 05 rests on
   SQL behaviour (`sent_at`, close-time deletion, single-nudge concurrency) that a
   mock suite cannot prove.
3. Web e2e — run unwrapped, it manages its own processes:

```bash
./scripts/run_client_integration_web_local.sh
```

   It must cover: open a request in review → answer every required card → send →
   the screen stays and shows the sent status → leave and re-enter from My Work →
   still sent, no primary review CTA on either surface → edit one card → both
   surfaces say changes are unsent.
4. Journal closeout entry: for each acceptance criterion of #162 and #180, name
   the test that proves it.

---

## 6. Scenario matrix

Every row needs a test with a named oracle. Rows marked **PG** must run against
the disposable database; a mock cannot prove them.

| # | Scenario | Oracle | Unit |
|---|---|---|---|
| 1 | First-ever fill, never sent | CTA is send-reviews, never send-changes | 08, 10 |
| 2 | Send → back → re-enter → app restart | checklist, HUD, banner and My Work all show sent | 10, 12, 13, 16 |
| 3 | Edit a card after a send | all surfaces show changes-not-sent; **PG**: status 1, `sent_at` intact | 02, 10, 12, 13 |
| 4 | Edit that empties the last required answer | `inProgress`, send disabled | 08, 10 |
| 5 | Successful send, then a failing refresh | still reads as sent; error shown separately | 10 |
| 6 | Leaver untouched, all required answered | send succeeds, client and server | 03, 09 |
| 7 | Current committer untouched | send refused with the existing error | 03 |
| 8 | Softened committer | classified optional | 03 |
| 9 | Viewer is the leaver | own-package notice; never affects `canCloseNow` | 03, 10 |
| 10 | Optional row stored, then skipped locally | card hidden, row still in the package; **PG**: counted at close | 10 |
| 11 | Optional package unsent at close | **PG**: rows and ack tags deleted, trust math unchanged | 16 |
| 12 | Last required package lands | exactly one nudge; window stays open | 01, 05 |
| 13 | Two simultaneous last sends | **PG**, serial transactions: one nudge, no close | 05 |
| 14 | Nudge emitted, then a required reviewer edits | `canCloseNow` false again, no retraction | 05 |
| 15 | Author closes now | closes; discard note from `unsentStartedPackages` | 14 |
| 16 | Author close races an edit / re-send | **PG**: assert one outcome, either order | 16 |
| 17 | `finalize` after the deadline | closes through `_ensureExpiredClosed` (D2) | 01 |
| 18 | Deadline sweep | closes; unsent rows discarded | 01 |
| 19 | Reopen while a reviewer is on the checklist | `paused` after the next action or refresh | 11 |
| 20 | Reopen after someone sent | cancellation event; dialog named the count | 06, 14 |
| 21 | Second window, drafts restored | answers shown, status 0, `sentAt` null → explicit send | 08, 10 |
| 22 | Second window, participants changed | new required target unanswered; softened one optional | 03 |
| 23 | Statuses `-1`, `3`, `4`, null | `notEnrolled` / not-sent / `closedUnsent` / `notEnrolled` | 08 |
| 24 | Zero targets | `empty`, no send CTA | 08, 10 |
| 25 | All targets optional | `readyToSend` with nothing answered | 08, 09 |
| 26 | Reload after close, sent and unsent | `closed` / `closedUnsent` copy, no checklist | 11 |
| 27 | Window predating m0176 | no-date context copy, never English legacy text | 09 |
| 28 | Draft route after the enum and DTO change | draft mode unchanged, its Done still pops | 09, 10 |
| 29 | 360 px × textScaler 2.0 | sections, status line and bar render; no item unbuilt | 10 |

Stale commands crossing window generations stay in #186. Races **inside one live
window** and the idempotency of the two new events do not.

---

## 7. What this plan does not fix

- **#76** — the review sheet's content. UNIT 09 only keeps it compiling and
  localized against the new DTO.
- **#184** — the null-check crash. Keeping the screen in place after a send
  removes the pop→Home→re-enter path it was observed on; that is not evidence of a
  fix, and #184 must not be closed on that basis.
- **#186** — window generation ids; every stale-command scenario stays open.
- Legacy `contribution_summary` / `causal_hint` columns stay, written and unread
  by the new UI. Retiring them is a separate cleanup, unrelated to #186.
