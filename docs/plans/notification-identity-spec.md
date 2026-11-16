# Notification identity: every notification names the Request/Post and the person

Status: draft spec (2026-11-16), awaiting owner answers in §11. No code yet.
Scope: push (web FCM), immediate email, email digest, in-app Updates / Activity / My Work rows.
Vocabulary: user-facing **Request** / «запрос», **Post** / «пост», **discussion** / «обсуждение», **Questions** / «вопросы»; code keeps `beacon*` (see `.cursor/rules/terminology.mdc`).

## 1. Problem

Many notifications do not say which Request or Post they are about, or who acted. Examples from today's server:

| Channel | What the user gets today |
|---|---|
| Digest line | «Your request has gone quiet — Close it, extend it or post an update.» (no Request; English even for RU users) |
| Digest subject | «Your Tentura summary» / «Сводка Tentura» (names nothing) |
| Immediate email subject | «Deadline reminder», or just «Anna» (the subject is the push title) |
| Push body | «Deadline changed from 2026-11-16T10:00:00.000Z to 2026-11-20T…» (raw UTC ISO, English) |
| Collapsed push | title = latest event title, body «3 coordination updates» (English, no Request) |
| In-app | «Your post is about to expire» with no Post identity; «Linked request status changed» without saying which one |

### Root causes (verified in code)

1. **Text is frozen in English when the event is written, and push/email reuse it.** `AttentionIntentCase` builds title/body with `BeaconNotificationCopyBuilder.build(locale: 'en')` or literal English (`attention_intent_case.dart:116-129, 267-315, 486-536, 593-623, 1075-1207, 1269-1307`). The dispatch repository copies that text into the channel job (`attention_dispatch_repository.dart:525-543`). Push and email then call `localizeStored` (`beacon_notification_copy_builder.dart:158-189`). That method translates a string only when it exactly equals a fixed English fallback, so anything with a title, excerpt, date, status or literal text stays English.
2. **The Request title is in the text only when the producer passed `intent.beaconTitle`.** Only offer accepted, plan events and forward helped pass it. `relay_received`, `help_offer_submitted`, deadline, status, room messages, coordination, closure and stale rows do not. The send path never looks it up.
3. **Two SQL writers bypass the copy builder completely.** `closure_reminder_repository.dart:28-30, 82-84` (`closure_draft_reminder`, `request_stale`) and `closure_receipts_repository.dart:21-99` (`closure_opened`, `closure_finalized`, `closure_cancelled`) store fixed English with no title or actor. They create no channel job, so they reach users only in-app and in the digest.
4. **Push batching drops the title.** `FcmBatchQueue._flush` passes `beaconTitle: null` to the aggregator (`fcm_batch_queue.dart:97-105`), and the plural bodies are English only.
5. **Email templates name nothing by design.** The digest subject is a constant, and the immediate email subject is the push title (`email_template_renderer.dart:12-63`). Digest rows are one line per outbox row, with no grouping by Request.
6. **The in-app side is mostly fine.** The feed gets a live, read-gated `beaconTitle` and `postRootExcerpt` (`attention_repository.dart:1087-1160`), and `UpdatesFeedTile` shows the title as a muted line. The gaps are listed in §5.3.

## 2. Principles (the rule set)

- **N1 Who · what · which.** Every push, email line and in-app row says **which** entity (Request title or Post label), **who** acted (live display name), and **what** happened (one verb phrase). It may drop a part only when that part does not exist (for example, a sweep has no actor) or when the recipient may not see it (N4).
- **N2 Entity first.** The entity label goes in the most prominent slot: the push title, the start of the email subject, the digest group heading, and the in-app title line. The event sentence comes second.
- **N3 Render at delivery, per recipient, in their locale.** Push, immediate email and digest text is rendered when it is sent, from structured facts plus a live identity lookup. It is never translated from stored English. Stored `title`/`body` columns stay as the in-app legacy fallback only (`docs/notification-attention-convergence-plan.md` §3 forbids dropping them). Push and email never read them.
- **N4 Never show what the recipient cannot read now.** The entity label is shown only if `beacon_can_read_content(beacon, recipient)` is true at render time. The actor name is shown only if `block_hides(actor, recipient)` is false at render time. Otherwise the generic fallback in §4 applies. This also covers drafts (status 3, author-only), deleted entities (status 2), blocks, and lost access.
- **N5 One copy table.** A single pure server renderer owns EN and RU text for every `AttentionEventType`, with an exhaustive `switch`, so adding an event type without copy fails to compile. The client keeps its own l10n for in-app rows, and the wording must match (§8 tests).
- **N6 Safe text.** Every interpolated string is normalized and truncated by graphemes (§4). Email HTML is escaped (it already is), and push text is plain text.
- **N7 Russian without guessing gender or case.** Names stay in the nominative, as the subject or before a colon; they are never declined. Prefer present tense or noun forms («Анна предлагает помощь», «Анна: новое сообщение»). When a past-tense verb is unavoidable, use the existing «(а)» convention. Counts use real one/few/many forms.
- **N8 No new leaks, no new nouns.** Use only the vocabulary in `terminology.mdc`, and no clock times in plan copy (plan rule K16: relative minutes). `scripts/check-user-facing-terminology.sh` must stay green.

## 3. Privacy invariants (what a recipient may see)

All rows below are evaluated **at render time**: when the push is handed off, when the immediate email is built, and when the digest is assembled.

| Situation | Source of truth | Entity label | Actor name | Excerpt (user words) |
|---|---|---|---|---|
| Recipient can read the content | `beacon_can_read_content` (latest body: `m0309.dart:12-135`) | yes | yes, unless blocked | yes (already gated at write time in `attention_policy.dart:787-793`) |
| Recipient cannot read now, row is `beacon_content` | same | no → generic fallback | yes, unless blocked | no |
| `recipient_safe` row (offer declined/removed, participation ended, closure bookmark) | `access_policy` | **owner question Q1**; default below | yes, unless blocked | reason key only (`withdrawReason` allow-list) |
| Entity deleted (status 2), tombstone readable | `beacon_can_read_tombstone` (`m0193.dart:758`) | «Deleted request» / «Удалённый запрос» (Post: «Deleted post» / «Удалённый пост») | yes, unless blocked | no |
| Entity deleted, tombstone not readable | same | the row is not sent (digest already drops it, `filter_beacon_notifications.dart:10-42`) | – | – |
| Draft (status 3) | `can_read_content`: author only | author only; producers never notify others about drafts | – | – |
| Actor and recipient blocked (either direction) now | `block_hides` (`m0193.dart:1312`) | – | **no**: push and immediate email are skipped, and the digest drops the row (the same rule Post shares already follow, `notification_outbox_repository.dart:122-135`) | – |
| Actor erased or empty display name | live `user.display_name` | yes | «Someone» / «Кто-то» | yes |
| Post expired (TTL → status 6, read-only archive) | `can_read_content` (members keep access) | yes (label from the root message) | yes | yes |
| `postExpiringSoon` already past expiry | `beacon.expires_at` | the row is dropped from the digest (stale fact) | – | – |
| Questions (lobby) message | `questions_access_levels` decided the audience at write time | yes (Request) | yes | no (unchanged: Questions text is never in notifications) |
| Lock-screen-safe preference on | `notification_preference.lock_screen_safe` | no | no | no. The copy is generic but **localized** (today it is English only, `beacon_notification_copy_builder.dart:601-633`) |

Default for **Q1** if the owner does not answer: a `recipient_safe` row may name the Request using the event-time snapshot `presentation_payload.beaconTitle`. That snapshot was written only when the recipient could read the Request at event time (`attention_policy.dart:763-765`). The row may not name it if a block exists now. Without this, «Your offer was declined» stays anonymous for exactly the people who most need to know which Request it was.

**Stored-text leak, fixed as a side effect.** Today the stored body of plan events contains the Request title for every recipient, readable or not (`attention_dispatch_repository.dart:278-279`, one text per intent). After N3, push and email no longer read stored text. In-app, `beacon_content` rows are already hidden from non-readers (`m0310.dart:97-114`). Producers are not changed for this; see §10.

## 4. Text rules: labels, fallbacks, truncation, locale

### 4.1 Entity label

| Entity | Label | Inside a sentence |
|---|---|---|
| Request (`kind 0`), readable | `title`, normalized. Titles are 3–32 characters (`kTitleMinLength`/`kTitleMaxLength`, `lib/consts.dart`), so truncation is only a defensive cap. | `«{title}»` in both locales (matches existing copy such as `updatesForwardHelpedAcceptedBody`) |
| Post (`kind 1`), readable, root text non-empty | EN `Post: {root text ≤ 40}`, RU `Пост: {root text ≤ 40}` (the root message is the Post's description; same source as `postRootExcerpt`) | `post «{root text ≤ 40}»` / `пост «{…}»` |
| Post, root message has only an image | `Post with a photo` / `Пост с фото` | same words |
| Post, root message empty | `Post · {author}` / `Пост · {author}` | `{author}'s post` → RU `пост · {author}` |
| Not readable now | none; the event headline takes the title slot | the sentence is phrased without a label: «Your offer was declined» |
| Deleted, tombstone readable | `Deleted request` / `Удалённый запрос`, `Deleted post` / `Удалённый пост` | same words |
| Related Request (hierarchy notice) | the related Request's own label, under its own `can_read_content` check; unreadable → «a linked request» / «связанный запрос» | |

### 4.2 Actor name
The **live** `user.display_name`, normalized and capped at 32 graphemes. An empty or erased name becomes «Someone» / «Кто-то». A blocked pair means no send (§3). The event-time snapshot `payload.actorName` is used only when the live user row is gone.

### 4.3 Normalization and truncation (one helper: `NotificationText`)
1. Strip C0/C1 control characters, Unicode bidi controls (U+202A–202E, U+2066–2069, U+200E/200F) and zero-width spaces/joiners **outside** emoji ZWJ sequences.
2. Collapse every whitespace run, newlines included, to one space, then trim.
3. Truncate by **grapheme clusters** (`package:characters`; already in `pubspec.lock` transitively, so add it as a direct dependency of `packages/server`). Cut at the last word boundary within the limit when one exists in the last 30% of the limit; otherwise cut hard. Append `…`. Never split a surrogate pair, ZWJ emoji or combining sequence.
4. Never truncate inside the quotes of a label. Truncate the label itself, then quote it.

| Slot | Limit (graphemes) | Shortening order |
|---|---|---|
| Push title | 50 | label |
| Push body | 140 | excerpt first (min 20), then sentence |
| Email subject | 78 | label first (min 16), then headline |
| Digest group heading | 80 | label |
| Digest event line | 160 | excerpt first |
| Excerpt (user words) | 80 (existing `notificationExcerpt`) | – |
| Post root text in a label | 40 | – |

### 4.4 Locale, dates, plurals, statuses
- **Locale.** Use `notification_preference.locale`: `ru*` → RU, anything else → EN. This is unchanged and applies to every channel, including the tombstone, lock-screen and aggregator text that is English-only today.
- **Dates (deadlines).** Never print raw ISO. Format in the recipient's `tzOffsetMinutes`: EN `21 Nov, 18:00`, RU `21 ноября, 18:00`. Add the year only when it differs from the current year. Plan copy keeps relative minutes (K16).
- **Plurals.** `NotificationText.plural(n, locale, one:, few:, many:)` implements the CLDR rules for `ru` and `en`. It is used by the push aggregator and the digest subject.
- **Status names.** Use a server table with the same words as the client's status labels (a `repo-files` test compares the two). It replaces the raw enum names in «moved the request from open to closed».

## 5. Per-kind copy

### 5.1 Channel templates

Notation: **{E}** entity label (§4.1), **{A}** actor (§4.2), **{x}** excerpt, **{S}** step title (the plan step's excerpt), **H** headline (used when there is no readable label), **L** event sentence.

| Channel | Readable entity | Entity not readable / none |
|---|---|---|
| Push | title `{E}`; body `L` + `: {x}` when an excerpt exists | title `H`; body `L` with no label |
| Immediate email | subject `L — «{E}»` (Post: `L — {E}`); body: `<h2>` link `{E}`, `<p>L</p>`, quoted `{x}`, CTA | subject `H`; body `L` |
| Digest | section → group heading `{E}` (link) → one bullet `L[: {x}]` per event, newest first | ungrouped bullet `H — L` (entity-less items such as connections go under «People» / «Люди») |
| Collapsed push (n > 1, same Request) | title `{E}`; body EN `{n} updates · latest: L`, RU `{n} {обновление/обновления/обновлений} · последнее: L`. If one actionable kind dominates, use its plural phrase (`beacon_notification_batch_aggregator.dart:34-79`), localized | title `Tentura`; body plural only |
| Lock-screen safe | localized generic per category (today's EN text plus RU) | same |
| Digest subject | EN `Tentura: «{E1}» and {n} more`, RU `Tentura: «{E1}» и ещё {n}`; `{E1}` is the first group of the first non-empty section. With one group: `Tentura: «{E1}»` | no readable group, or lock-screen safe on: `Your Tentura summary` / `Сводка Tentura` |

### 5.2 Event sentences (server renderer, keyed by `presentation_key`)

The "Now" column shows the stored EN title → body; RU appears today only where `localizeStored` matches. Facts marked **new** must be added to `presentation_payload` (§6). Everything else is already there or is resolved by identity.

| presentation_key | Now (push/email) | New H (EN / RU) | New L (EN / RU) | Facts needed (source) |
|---|---|---|---|---|
| `relay_received` (Request) | «{A}» → «{A} forwarded a request to you» | Request forwarded / Запрос переслан | {A} forwarded you a request / {A} пересылает вам запрос | beaconId, actorUserId, excerpt (note) |
| `relay_received` (Post) | «{A}» → «{A} shared a post with you» | Post shared / Поделились постом | {A} shared a post with you / {A} делится с вами постом | same + beaconKind |
| `help_offer_submitted` | «{A}» → offer text or «{A} offered help» | Help offered / Предложена помощь | {A} offered help / {A} предлагает помощь; backup: {A} offered to help as backup / {A} предлагает помощь как запасной вариант | excerpt; **new** `isBackupOffer` (intent has it) |
| `help_withdrawn` | «{A}» → note or «{A} withdrew their help» (EN only) | Help offer withdrawn / Предложение помощи отозвано | {A} withdrew their help offer / {A} отозвал(а) предложение помощи; with reason: + ` ({reason})` from the allow-listed reason key, localized | withdrawReason, leftDiscussion |
| `forward_declined` | «{A}» → «{A} can't help[: note]» (EN only) | Can't help / Не может помочь | {A} can't help / {A} не может помочь | excerpt |
| `offer_accepted` | «{A} accepted your offer» → «{title} — {msg}» | Offer accepted / Предложение принято | {A} accepted your offer / {A} принял(а) ваше предложение | – |
| `offer_declined` | «Offer declined» → reason | Offer declined / Предложение отклонено | {A} declined your offer / {A} отклонил(а) ваше предложение | Q1 snapshot title |
| `offer_removed` | «Removed from the discussion» → reason | Removed from the discussion / Вас убрали из обсуждения | {A} removed you from the discussion / {A} убрал(а) вас из обсуждения | Q1 |
| `commitment_released` | «Participation ended» → reason | Participation ended / Участие завершено | {A} ended your participation / {A} завершил(а) ваше участие | Q1 |
| `room_message_posted` (discussion) | «{A}» → message excerpt | New message / Новое сообщение | `{A}: {x}`; no text: {A} sent a message / {A}: новое сообщение | excerpt **new in payload**: the producer has the message text, but `role.excerpt` is null, so payload `excerpt` is always `''` for this key today |
| `room_message_posted` (Questions, `coordinationItemId` set) | «{A}» → «New message in Questions» (EN only) | New message in Questions / Новое сообщение в вопросах | {A} wrote in Questions / {A} пишет в вопросах | – (no text, unchanged) |
| `room_message_posted` (mention, kind `roomMention`) | «{A}» → excerpt or «{A} mentioned you» | You were mentioned / Вас упомянули | {A} mentioned you: {x} / {A} упоминает вас: {x} | kind is in the job |
| `post_first_response` | «{A}» → reply or «{A} replied to your post» | Reply to your post / Ответ на ваш пост | {A} replied to your post / {A} отвечает на ваш пост (+ `: {x}`) | excerpt |
| `post_expiring_soon` | «Your post is about to expire» → «…under 3 hours» | Your post expires soon / Ваш пост скоро исчезнет | Expires in {h} h. Turn it into a request to keep it going / Исчезнет через {h} ч. Оформите запрос, чтобы продолжить | **new** `expiresAt` → whole hours |
| `request_status_changed` | «Request status changed» → «{A} moved the request from open to closed» (EN, raw enum) | Status changed / Статус изменён | {A} changed the status to «{status}» / {A}: статус «{status}» | toStatus; **new** `fromStatus` (only for the digest's «from»; optional) |
| `beacon_hierarchy_status_changed` | «Child request status changed» → «A child request was closed on 2026-11-16» (EN) | Linked request updated / Связанный запрос изменён | Linked request «{E2}» {was closed / was cancelled / entered Final check / was deleted} / Связанный запрос «{E2}» {закрыт / отменён / на подведении итогов / удалён}; unreadable E2: «A linked request …» / «Связанный запрос …» | **new** `relatedBeaconId`, `direction` (ancestor/child); toStatus |
| `deadline_changed` | «Deadline changed» → «…from ISO to ISO» (EN) | Deadline changed / Срок изменён | {A} moved the deadline to {date} / {A}: новый срок — {date}; removed: {A} removed the deadline / {A} убрал(а) срок | **new** `newEndAt` (ISO, null when removed) |
| `deadline_reminder` | «Deadline reminder» → «Deadline: ISO» (EN) | Deadline tomorrow / Срок завтра | Deadline: {date} / Срок: {date} | **new** `newEndAt` |
| `coordination_changed` | «Plan updated» → excerpt or «Coordination changed» | Coordination changed / Договорённости изменились | {A} updated the coordination: {x} / {A}: договорённости изменились — {x} | excerpt |
| `baton_asked` | «{A}» → excerpt or «{A} asks if you can help» | Who'll take it? / Кто возьмётся? | {A} asks if you can help: {x} / {A} спрашивает, сможете ли вы помочь: {x} | excerpt |
| `baton_taken` | «You took it» → «You took it: {x}» (EN body) | You took it / Вы взялись | You took it: {x} / Вы взялись: {x} | excerpt |
| `baton_all_answered` | «Everyone answered» → … | Everyone answered / Все ответили | Everyone answered your «Who'll take it?» / Все ответили на ваше «Кто возьмётся?» | – |
| `author_invite_received` | «{A}» → note or «{A} asks you to help» | Invitation to help / Приглашение помочь | {A} asks you to help / {A} зовёт вас помочь (+ `: {x}`) | excerpt |
| `author_invite_accepted` | in-app only | Invitation accepted / Приглашение принято | {A} accepted your invitation / {A} принял(а) ваше приглашение | – |
| `author_invite_declined` | in-app only | Can't make it / Не сможет | {A} can't make it / {A} не сможет помочь | – |
| `plan_step_due` | «Your step has started» → «{title} — {S}» | Your step has started / Ваш шаг начался | Your step «{S}» has started / Ваш шаг «{S}» начался | excerpt = S |
| `plan_step_turn` | «Your turn» → … | Your turn / Ваш ход | Your turn: «{S}» / Ваш ход: «{S}» | S |
| `plan_change_pending` | «Your step changed» → … | Your step changed / Ваш шаг изменён | {A} changed your step «{S}» / {A} изменил(а) ваш шаг «{S}» | S |
| `plan_step_reminder` | «Your step starts in N min» (EN title) | Step soon / Скоро ваш шаг | Your step «{S}» starts in {m} / Ваш шаг «{S}» через {m} | **new** `relativeMinutes` (intent field, not in payload today) |
| `plan_step_overdue` | «Your step is overdue» | Step overdue / Шаг просрочен | Your step «{S}» is overdue / Ваш шаг «{S}» просрочен | S |
| `plan_step_late` | «A step is N min late» (EN) | Step running late / Шаг опаздывает | «{S}» is {m} late / «{S}» опаздывает на {m} | S, **new** `relativeMinutes` |
| `plan_cant_make` | «{A} can't make it» | Can't make it / Не успевает | {A} can't make «{S}» / {A} не успевает к шагу «{S}» | S |
| `plan_step_unassigned` | «A step has no one» | Step has no one / Шаг без исполнителя | «{S}» has no one / У шага «{S}» нет исполнителя | S |
| `plan_edited` (never pushed or digested) | «Plan updated» | Plan updated / План изменён | {A} edited the plan / {A} изменил(а) план | – |
| `plan_step_done` (never pushed or digested) | «A step is done» | Step done / Шаг выполнен | {A} finished «{S}» / {A}: шаг «{S}» выполнен | S |
| `forward_helped` | «Your forward helped» → «{path} offered help with «{title}»» (already EN+RU) | Your forward helped / Ваша пересылка помогла | unchanged sentences (`beacon_notification_copy_builder.dart:113-155`); title slot becomes `{E}` | path, helperId, done |
| `closure_opened` | in-app/digest only: «Time to sum up» → «The closing window is open.» (EN SQL text) | Time to sum up / Пора подвести итоги | Closing is open: mark who helped / Подведение итогов открыто: отметьте, кто помог | epoch |
| `closure_opened_bookmark_only` | same | same H | Closing is open / Подведение итогов открыто | Q1 snapshot |
| `closure_draft_reminder` | «Finish your review» → «…closes within a day.» (EN SQL) | Finish your review / Завершите свою оценку | Your review isn't sent yet; closing ends within a day / Ваша оценка ещё не отправлена; итоги закроются в течение суток | epoch |
| `closure_finalized` | «Request closed» → «The results are in.» (EN SQL) | Request closed / Запрос закрыт | The results are in / Итоги подведены | outcome (already) |
| `closure_cancelled` | «Evaluation cancelled» → «The closing was cancelled.» (EN SQL) | Closing cancelled / Подведение итогов отменено | {A} cancelled the closing / {A} отменил(а) подведение итогов (no actor: «Closing was cancelled» / «Подведение итогов отменено») | **new** `actorUserId` column when known |
| `request_stale` | «Your request has gone quiet» → «Close it, extend it or post an update.» (EN SQL) | Your request has gone quiet / В вашем запросе стало тихо | quiet: No activity for {n} days. Close it, extend it or post an update / {n} {день/дня/дней} без движения. Закройте, продлите или напишите новости. Deadline passed: The deadline passed on {date}. Close it or extend it / Срок прошёл {date}. Закройте или продлите запрос | **new** `staleReason` (`quiet` / `deadlinePassed`), `quietDays`, `endAt` (SQL already computes the inputs) |
| `mutual_connection_formed` | «New connection» → «You and {A} are now connected.» (EN) | New connection / Новая связь | You and {A} are now connected / Вы и {A} теперь на связи | – (no entity; title slot = {A}) |
| `invite_accepted` | «{A} · @handle» → `InviteAcceptedCopy` (EN+RU) | Invitation accepted / Приглашение принято | {A} accepted your invitation. {origin sentence} / {A} принял(а) ваше приглашение. {…} | inviteOrigin |

**Declared but never written** (`needs_me`, `blocker_opened`, `blocker_resolved`, `promise_made`, `promise_withdrawn`, `stale_reminder`, `obligation_ended`, `commitment_accepted/resolved/cancelled/redirected`): the exhaustive renderer gives each one `H` from today's copy and `L = {A} · H`. No more work here; their removal is a separate cleanup.

### 5.3 In-app (client) changes

The Request title already reaches Updates rows through the live `beaconTitle` column, which `UpdatesFeedTile` shows as a muted line (`updates_feed_tile.dart:284-357`). The remaining gaps:

| Surface / key | Gap | Change |
|---|---|---|
| Generic keys (`offer_declined`, `offer_removed`, `commitment_released`, `request_status_changed`, `deadline_*`, `coordination_changed`, plan rows) | the headline has no name; the name appears only via the tile's «Name · » prefix | headline uses the §5.2 sentence with `{name}` (new ARB keys in EN+RU); deadline/status rows show the formatted date and localized status from the new facts |
| `room_message_posted` | the body is the Request title, so the message words are dropped (`updates_receipt_display_copy.dart:937-944`, pinned by `updates_receipt_display_copy_test.dart:91-104`) | body = excerpt; the Request stays in the tile's title line. Update that test |
| `post_first_response`, `post_expiring_soon`, Post reply/mention rows (`post_attention_row.dart:96-129`) | no Post identity, no actor | Post label from `postRootExcerpt` (§4.1); reply/mention variants name the actor |
| `beacon_hierarchy_status_changed` | which linked Request is not said | the feed exposes `relatedBeaconTitle` (live, gated); the row says «Linked request «{E2}» was closed» |
| `closure_*`, `request_stale` | fixed text; the title appears only as the tile line in Updates | headline/body as in §5.2 (quiet days, deadline date) |
| `trust_*_changed_*` rows | «You trust them more»: «them» is never named | use `{name}` |
| My Work (`my_work_attention.graphql`) | no `beaconTitle`, `beaconKind` or `postRootExcerpt` | add the fields; rows show the entity label |
| Timeline sheet (`request_attention_timeline_sheet.dart:200`), My Work block (`my_work_obligation_block.dart:232`) | actor name never passed | pass the resolved actor profile name |

The client keeps reading the structured payload. It does not parse server titles for new keys.

## 6. Payload and schema changes

**No SQL migration.** Every new fact goes into existing `jsonb` columns, and identity is joined at render time.

1. **Facts added to `presentation_payload`** (written by `AttentionPolicy._presentationPayload` from new `AttentionRecipientRoleFacts` fields, or by the two SQL writers):
   - `isBackupOffer`, `newEndAt`, `fromStatus`, `relatedBeaconId`, `direction`, `relativeMinutes`, `expiresAt`, `staleReason`, `quietDays`, `endAt`.
   - The room-message `excerpt`: today the intent carries it but `role.excerpt` is null.
   - All values are ids, enums, ISO timestamps or small integers. They never carry free text beyond the existing gated `excerpt`.
2. **Allow-list.** The `attentionFeed` payload filter (`query_attention.dart:422-466`) admits the new keys, plus the closure fields it drops today (`epoch`, `outcome`, `band`, `draftFlag`).
3. **Channel job payload** (`attention_dispatch_repository.dart:525-543 _decisionPayload`, and the SQL in `attention_system_settlement_repository.dart:71-86`) gains `presentationKey` and the recipient's `presentationPayload` for **every** job, not just forward helped. `AttentionChannelDecision` gets the matching fields. The stored `title`/`body` stay in the job only for logs.
4. **Feed enrichment.** `_attachBeaconTitles` (`attention_repository.dart:1087-1160`) also resolves `relatedBeaconTitle` for `relatedBeaconId` under the same `beacon_can_read_content` gate. GraphQL `AttentionReceipt` gets one new nullable field, `relatedBeaconTitle`.
5. **Identity port.** `NotificationIdentityPort.resolve(recipientId, List<IdentityRequest{beaconId?, actorUserId?, relatedBeaconId?}>)` runs one SQL query per call:
   - `beacon_can_read_content`, `beacon_can_read_tombstone`, `block_hides`
   - `b.kind`, `b.status`, `b.expires_at`, `b.title`, the Post root text (`left(root.body, 200)`) and whether the root has an image
   - `user.display_name`

   Push calls it per decision. Immediate email and the digest call it once per recipient batch.
6. **Removed:** `BeaconNotificationCopyBuilder.localizeStored`, the English-only `lockScreenSafe` strings, `InviteAcceptedCopy.forStoredBody` (the renderer chooses the variant from `inviteOrigin`), and the `beaconTitle: null` call in `FcmBatchQueue`. Under the no-legacy-client rule there are no compatibility shims: server and client ship in one release.

## 7. Server design (pure core, thin adapters)

- `domain/notification/notification_text.dart`: normalize, truncate, quote, plural, date and status formatting (§4). Pure.
- `domain/notification/notification_identity.dart`: value object `{entityKind, label?, tombstone, readable, actorName?, actorHidden, relatedLabel?, expired}` plus `NotificationIdentityPort`.
- `domain/notification/notification_copy_renderer.dart`: `render({presentationKey, kind, facts, identity, locale, tzOffsetMinutes}) → NotificationCopy{headline, sentence, excerpt, entityLabel?}`, plus channel composers `forPush`, `forEmailSubject`, `forDigestLine`, `lockScreenSafe(category, locale)`. Pure; replaces `BeaconNotificationCopyBuilder.build`, `localizeStored` and the title logic of `digestPostItem`.
- `data/repository/notification_identity_repository.dart`: the SQL behind the port.
- Adapters: `BeaconNotificationService.handOffChannels`, `FcmBatchQueue` (uses the `entityLabel` carried on the message and the localized plural), `EmailNotificationService`, `EmailDigestCase`, `EmailTemplateRenderer` (grouped digest, new subject).

## 8. Test strategy

> The project forbids pixel golden tests (`.cursor/rules/no-golden-tests.mdc`). "Golden text" here means **exact expected strings** checked into test fixtures. No images are involved.

- **Renderer table test (unit, server):** one table row per `presentation_key` × variant × {en, ru} × {readable, unreadable, tombstone}, asserting exact `headline`/`sentence`/`entityLabel`. A guard test fails when an `AttentionEventType` value has no row.
- **Leak property test (unit):** for every key and locale, render with identity `readable=false` and sentinel title `SECRET-TITLE-Ж`; no output may contain the sentinel. Repeat with `actorHidden=true` and sentinel name.
- **Russian test (unit):** reuse `beacon_notification_copy_builder_ru_test.dart`'s Cyrillic/Latin checks on every RU output (names and labels removed first); plural forms for 1, 2, 5, 11, 21, 22, 25.
- **Text helper tests (unit):** ZWJ emoji, combining marks, bidi controls, CRLF, exact-limit and limit+1, word-boundary cut, quote placement, `tzOffsetMinutes` across midnight and year change.
- **Identity resolver (pg):** fixtures for readable, unreadable, blocked each way, deleted with and without tombstone, draft, Post (text / image-only / empty root), expired Post, erased actor, related Request unreadable.
- **Real path, push (pg):** create a Request «Fix the roof», submit an offer as Anna; the channel job is handed off to the fake FCM, which receives title `Fix the roof` and body `Anna offered help: …` (EN), and `Anna предлагает помощь…` (RU). The same setup with access revoked before hand-off yields title `Help offered` and no title anywhere.
- **Digest expected-text fixtures (pg):** seed a recipient with a Request offer, a deadline change, a stale reminder, a Post share and a connection. Run `EmailDigestCase` with the file-sink sender (`EMAIL_DEBUG_SINK_DIR`). Compare the **text/plain part and subject exactly** against `test/fixtures/email/digest_en.txt` and `digest_ru.txt`. HTML is checked structurally (one `<h3>` per section, one group per entity, escaped titles).
- **Immediate email (unit + pg):** exact subject for `offer_accepted`, `deadline_reminder` and the Post share; subject length ≤ 78 with a 32-character title and a 32-character name.
- **Client:** copy tests per changed key in EN and RU (extend `issue_736_event_headline_coverage_test.dart` and the per-mapper tests); a real-path test from a GraphQL feed response through the repository to the Updates row for `relatedBeaconTitle` and the My Work title; 375×667 RU check of the Updates, My Work and Post rows (fix-completeness rule).
- **Terminology:** `scripts/check-user-facing-terminology.sh` and `request_terminology_contract_test.dart` stay green.

## 9. Work breakdown

Each unit is independently testable. "Done" means its acceptance tests exist, fail without the change, and pass with it. Dependencies are in brackets.

| # | Unit | Side | Size | Acceptance (test-assertable) |
|---|---|---|---|---|
| U1 | `NotificationText` helpers: normalize, grapheme truncate, quote, RU/EN plural, date in tz offset, status labels; add `characters` as a direct server dependency | server | simple | §8 helper tests; status-label `repo-files` test matches client ARB words |
| U2 | `NotificationIdentity` + port + SQL repository (batch resolve) | server | medium | identity pg fixtures in §8 all pass; one query per call (asserted by a query counter or explain test) |
| U3 | New facts in `presentation_payload`: producers (`AttentionIntentCase`, `AttentionPolicy`, closure/stale SQL writers) + feed allow-list | server | medium | pg tests: a deadline change writes `newEndAt`; a stale sweep writes `staleReason`/`quietDays`; a hierarchy notice writes `relatedBeaconId`; a room message writes `excerpt`; `attentionFeed` returns the new keys and the closure `epoch`/`outcome` |
| U4 | Channel job carries `presentationKey` + `presentationPayload` for all jobs; `AttentionChannelDecision` fields [U3] | server | simple | dispatch pg test: a job row for `help_offer_submitted` has both keys; decode round-trip unit test |
| U5 | `NotificationCopyRenderer` with the full §5.2 table, lock-screen-safe localized [U1, U2 types] | server | complex | renderer table test, leak property test, RU test, exhaustive-key guard |
| U6 | Push: `handOffChannels` resolves identity and renders; blocked pair → no send; aggregator localized and fed the label; delete `localizeStored` [U2, U4, U5] | server | medium | real-path push pg test (EN, RU, revoked access, blocked actor); aggregator tests for RU plurals and title = label |
| U7 | Immediate email: subject/body per §5.1 [U5, U6] | server | simple | exact subjects for `offer_accepted`, `deadline_reminder` and a Post share; length cap test |
| U8 | Digest: render every row with batch identity; group by entity per section; new subject; localized tombstone; drop expired `postExpiringSoon` and blocked-actor rows [U2, U3, U5] | server | complex | `digest_en.txt` / `digest_ru.txt` exact fixtures; tombstone RU test; expired Post warning absent; blocked-actor row absent from the email (the existing pending/`markEmailed` rule for filtered rows stays as it is) |
| U9 | Feed: `relatedBeaconTitle` (gated) in `_attachBeaconTitles` + field on the custom `AttentionReceipt` type (`api/controllers/graphql/custom_types.dart`, `query_attention.dart`) [U3] | server | simple | pg: readable related title returned; unreadable → null |
| U10 | Client Updates/Activity copy: §5.3 rows (generic keys with name, room-message excerpt, Post identity, hierarchy, closure/stale, trust); ARB EN+RU [U3, U9] | client | medium | per-key copy tests EN/RU; real-path feed→row test for hierarchy; updated `updates_receipt_display_copy_test.dart:91` |
| U11 | Client My Work + Timeline: query fields, label, actor names | client | simple | widget test from a GraphQL fixture: My Work row shows «Fix the roof» and «Anna»; Timeline row shows the name |
| U12 | Docs: `docs/features/request-attention.md` gets a «Notification copy» section with the §2 rules and §4 limits; `DEV_GUIDELINES.md` points to the renderer as the only place for channel copy | docs | simple | terminology script green; a `repo-files` test asserts the doc section exists and lists every `presentation_key` |
| U13 | Ship: client version bump + raise `kDefaultMinClientVersion` to that version (per `versioning.mdc`, no numbers in this plan); `server-gates` + `server-pg` + `client-gates` + `client-affected`; local stack check with `EMAIL_DEBUG_SINK_DIR` and a QA push in EN and RU; 375×667 RU screenshots | both | medium | all suites green; captured digest and push text in RU/EN attached to the bead |

Order: U1 → U2 → U3 → U4 → U5 → U6 → U7 → U8 (server block) → U9 → U10 → U11 → U12 → U13. Server and client blocks are not interleaved (epics-in-blocks rule).

## 10. Out of scope (found while surveying; separate issues)

- **In-app filter bug:** `recipient_safe` closure rows are never shown. `m0203:223` lets `closure_opened_bookmark_only`, `closure_finalized` and `closure_cancelled` be written as `recipient_safe`, but the read filter (`m0310.dart:97-114`) only admits `room_member_removed`, `offer_declined` and `offer_removed`. Fixing it needs a migration.
- **Unsent pushes:** there is no foreground `onMessage` handler on the client, and FCM messages are data-only, so native builds probably display nothing. Web only today.
- **Magic-link email:** the «X invited you to Tentura» line is never filled (`resend_email_sender.dart:107`, no caller passes `inviterName`). The account and deletion emails are English only.
- **Stored per-intent text:** stored `title`/`body` still embed the title for every recipient of plan events. They are hidden in-app by `access_policy`, and channels stop reading them after U6. Leave them as they are (deferred read-side hardening).
- **Declared but unwritten presentation keys** (§5.2): cleanup.

## 11. Open questions for the owner

- **Q1. `recipient_safe` rows.** May «offer declined / removed / participation ended / closing opened (bookmark)» name the Request with the title the recipient could read when the event happened, even if they can no longer read it? Default: **yes, unless a block exists now.**
- **Q2. Push layout.** Should the title be the Request/Post name with «who did what» in the body (messenger style, chosen here)? Or should the title be «who did what» with the name in the body?
- **Q3. Email subjects.** Is a Request title acceptable in email subjects, which show in inbox previews? Should the `lock_screen_safe` preference also make email subjects generic? Default: titles in subjects; `lock_screen_safe` also hides them in subjects.
- **Q4. Deadline text.** Use an absolute date and time in the recipient's timezone offset («21 ноября, 18:00»), or a relative form («через 2 дня»)? Default: absolute.
