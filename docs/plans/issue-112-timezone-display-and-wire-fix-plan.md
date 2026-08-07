---
status: complete
kind: plan
---

# Fix naive-datetime wire bug and UTC-leak display bugs in beacon schedule (issue #112)

**Status:** complete — all 6 phases (P1-P6) implemented, reviewed, and
verified 2026-08-07. See
[`issue-112-timezone-fix-journal.md`](issue-112-timezone-fix-journal.md) for
the full evidence trail.
**Date:** 2026-08-07.
**Scope:** client + server fix for
[Intersubjective/tentura#112](https://github.com/Intersubjective/tentura/issues/112)
("Отчёт: время и таймзоны"). Fixes the naive-datetime wire-format bug for
beacon `startAt`/`endAt` and the UTC-leak display bugs identified in the
issue's audit. Deliberately **does not** add an author-timezone column, a
timezone/time picker, or "your time vs. author's time" dual-label UI — see
§0.4 for why, and §6 for what stays deferred.
**Journal:** [`issue-112-timezone-fix-journal.md`](issue-112-timezone-fix-journal.md)
(create on first run; not itself a work unit).

---

## 0. Why this plan exists

### 0.1 The reported symptom

Issue #112's audit (Russian-language report, quoted in full in the originating
conversation) found that beacon `startAt`/`endAt` ("дедлайн"/"событие") pass
through the client → server → database pipeline with an undefined timezone,
and that several client UI surfaces format a `DateTime` for display without
first converting it to the viewer's local time — producing "wrong time"
symptoms that vary by which screen you're looking at.

### 0.2 Root cause #1 (P0, wire format) — verified against live code

The picker in `packages/client/lib/features/beacon_create/ui/widget/info_tab.dart:517-519`
builds a **local, non-UTC** `DateTime` at calendar midnight:

```dart
static DateTime _calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);
```

This is correct and must not change — it feeds `showDatePicker`/
`showDateRangePicker`'s own local-midnight comparisons (`firstDate`,
`lastDate`, `initialDate`), and Flutter's Material date pickers return
local-midnight `DateTime`s themselves, so everything inside `info_tab.dart`
must stay in the same (local) frame.

The bug is at the wire boundary. `packages/client/lib/features/beacon/data/repository/beacon_repository.dart`
serializes the picked value directly:

```dart
136:  ..startAt = beacon.startAt?.toIso8601String()   // create()
137:  ..endAt = beacon.endAt?.toIso8601String()
170-171: // updateDraft() — identical
201-202: // update() — identical
```

**`DateTime.toIso8601String()` on a non-UTC `DateTime` omits the offset
entirely** — no `Z`, no `+02:00`, nothing. For a local-midnight value picked
in, say, Amsterdam in summer, this produces `"2026-08-10T00:00:00.000"`, a
string with no timezone information at all.

On the server, `packages/server/lib/api/controllers/graphql/input/_input_types.dart:109-115`
parses it with no normalization:

```dart
DateTime? fromArgs(Map<String, dynamic> args) => switch (args[field.name]) {
  final String field when field.isNotEmpty => DateTime.tryParse(field),
  _ => null,
};
```

`DateTime.tryParse` on an offset-less string returns a `DateTime` with
`isUtc == false`, i.e. Dart treats the digits as **local wall-clock time in
whatever timezone the server process happens to be running in** — a value
that has nothing to do with either the author's or any viewer's timezone, and
can silently differ between prod/staging/dev deployments. This is then wrapped
directly in `PgDateTime(startAt)`
(`packages/server/lib/data/repository/beacon_repository.dart:79-80, 213-214, 273-274`)
and written to the `timestamptz` column as whatever instant that
ambiguous interpretation produces.

This is the one genuine correctness bug in the pipeline — not a display
inconsistency, a wrong stored instant.

### 0.3 Root cause #2 (display) — verified against live code

Independently of §0.2, several client formatters render a `DateTime` without
first calling `.toLocal()`:

- `packages/client/lib/ui/utils/ui_utils.dart:78-82` — `dateFormatYMD`/
  `timeFormatHm` call `DateFormat.format(dateTime)` directly, with no
  `.toLocal()`. Correctness depends entirely on the caller.
- Three call sites pass an un-converted value into these helpers:
  `packages/client/lib/features/beacon/ui/widget/beacon_tile.dart:40-43`,
  `packages/client/lib/features/inbox/ui/widget/inbox_item_tile.dart:121-125`
  (both format `beacon.updatedAt`), and
  `packages/client/lib/ui/widget/beacon_hud_metadata_composer.dart:268-270`
  (formats `beacon.startAt`/`beacon.endAt`).
- Four other call sites already convert correctly before calling these same
  helpers or do their own local diffing:
  `packages/client/lib/ui/utils/schedule_date_format.dart:10-11,29-30`,
  `packages/client/lib/ui/utils/relative_time.dart:9`,
  `packages/client/lib/ui/widget/coordination_log_row_chrome.dart:97`,
  `packages/client/lib/features/beacon_view/ui/widget/help_offer_tile.dart:179`,
  `packages/client/lib/features/updates/ui/widget/updates_receipt_card.dart:48`.

Since `.toLocal()` on an already-local `DateTime` is a no-op, **moving the
`.toLocal()` call inside `dateFormatYMD`/`timeFormatHm` themselves fixes the
three broken call sites without touching them**, and is strictly safe for the
four call sites that already convert (idempotent). `dateFormatYMD`/
`timeFormatHm` are display-only formatters; there is no legitimate caller that
wants raw, unconverted digits. Verified no existing test asserts on their
un-converted behavior (`grep` for both symbols across `packages/client/test`
found no hits; the one golden test that constructs a UTC `updatedAt`,
`packages/client/test/features/inbox/inbox_item_tile_golden_test.dart`, sets
`createdAt == updatedAt`, so `beaconHasRealUpdate` — `packages/client/lib/ui/widget/beacon_card_primitives.dart:403-410`
— is `false` and the date text never renders in that golden; confirmed safe).

Separately, `packages/client/lib/features/evaluation/ui/widget/review_window_banner_host.dart:55-61,79-85`
interpolates `review.closesAt` — a raw `String?` (not a `DateTime`; see
`packages/client/lib/features/evaluation/domain/entity/review_window_info.dart:12`)
— directly into `l10n.beaconReviewWindowClosesAt(review.closesAt!)`, showing
the bare server ISO string. The correct pattern already exists elsewhere in
the same feature —
`packages/client/lib/features/evaluation/ui/screen/review_contributions_screen.dart:285-297`
parses the raw string, calls `.toLocal()`, and formats with
`DateFormat.yMMMd(locale)` — and should be reused here.

### 0.4 Scope decision: no author-timezone storage (confirmed with the user)

The issue's acceptance criteria ask for both (a) consistent instant
conversion for viewers and (b) an explicit author-intended-timezone model for
deadlines with a "your time vs. original" UI. Discussed with the user before
writing this plan: (a) is a pure bug — once the wire format always carries an
explicit UTC offset (§0.2) and every display formatter converts to viewer
local (§0.3), any two viewers see the correct, consistent instant with no
timezone storage required. (b) only matters if the product wants "deadline:
10 August" to mean *the calendar day in the author's timezone specifically*
(so a viewer far away might legitimately see "9 August" or "11 August" for
what the author picked as a single date) — that is a product/UX decision, not
a bug, and the user chose **not** to build it now. This plan fixes (a) in
full and explicitly leaves (b) as a documented, accepted limitation — see §6.

## 1. Rules (repo-wide invariants — read before editing)

- Never hand-edit generated files: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, `packages/client/lib/ui/l10n/**`, `**/_g/**`. Only run
  codegen.
- After editing `packages/client/l10n/*.arb`: `cd packages/client && flutter
  gen-l10n` (before any client `build_runner`). This plan does not add or
  change any `.arb` keys — `beaconReviewWindowClosesAt`'s `{date}` placeholder
  already accepts any string, including a properly formatted one — so this
  should not be needed, but re-check after P4 in case wording changes.
- No raw visual constants in client UI. None of the phases below add new
  visual constants.
- Do not widen scope into an author-timezone model, timezone/time picker, or
  dual-label "your time" UI — see §0.4 and §6. If a phase's investigation
  surfaces a need for one of these to make the assigned fix correct, stop and
  flag it in the journal rather than building it.
- Preserve all pre-existing uncommitted changes in the working tree
  (`CONTEXT.md`, `docs/README.md`, two docs/archive files,
  `docs/audits/room-coordination-audit.md`, `packages/client/web/index.html`,
  `packages/server/lib/data/database/table/beacon_commitment_events.dart`,
  `packages/server/lib/env.dart`, plus several untracked files — none
  overlap with files this plan touches; diff first, edit around them, never
  revert them).
- Server: never write `PgDateTime` from a `DateTime` whose `isUtc` is `false`
  for a client-supplied instant — that is exactly the bug this plan fixes
  (§0.2). Server-generated timestamps (`DateTime.timestamp()`,
  `DateTime.now().toUtc()`) are already correct and out of scope.

## 2. Verification commands

```bash
cd packages/client && flutter analyze
cd packages/client && flutter test
cd packages/server && dart analyze
cd packages/server && dart test
```

Run the relevant subset after each phase (see each phase's **Verification**);
run the full set in Phase P6.

---

## Phase P1 — Client: always send an explicit-UTC ISO string for beacon schedule dates

**File:** `packages/client/lib/features/beacon/data/repository/beacon_repository.dart`

Add a small top-level helper near the top of the file (after the imports,
before the class), annotated `@visibleForTesting` so it can be unit-tested
directly without building a `RemoteApiService` test double (none exists in
this codebase today — see P1 Verification):

```dart
import 'package:meta/meta.dart';
```

```dart
/// GraphQL `startAt`/`endAt` inputs must always carry an explicit UTC offset.
/// [DateTime.toIso8601String] omits any offset entirely for a non-UTC
/// (local) instance — the picker in `info_tab.dart` intentionally builds
/// local-midnight values — so every wire write must force UTC first, or the
/// server has no way to know what instant was meant (issue #112).
@visibleForTesting
String? scheduleDateTimeToIso(DateTime? dateTime) =>
    dateTime?.toUtc().toIso8601String();
```

Replace all six occurrences of `beacon.startAt?.toIso8601String()` /
`beacon.endAt?.toIso8601String()` (lines 136-137 in `create()`, 170-171 in
`updateDraft()`, 201-202 in `update()`) with
`scheduleDateTimeToIso(beacon.startAt)` / `scheduleDateTimeToIso(beacon.endAt)`.

Do not touch `info_tab.dart`, `beacon_create_cubit.dart`, or any other part of
the picker flow — the local-midnight semantics there are correct and must stay
self-consistent (see §0.2).

**Acceptance:** every beacon create/update/updateDraft mutation sends
`startAt`/`endAt` as a `Z`-suffixed UTC ISO 8601 string, never an offset-less
local string, regardless of the device's local timezone.

**Verification:** new test
`packages/client/test/features/beacon/data/repository/beacon_repository_schedule_serialization_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';

void main() {
  group('scheduleDateTimeToIso', () {
    test('null passes through', () {
      expect(scheduleDateTimeToIso(null), isNull);
    });

    test('local midnight always serializes with an explicit UTC offset', () {
      final localMidnight = DateTime(2026, 6, 20); // built local, no .utc()
      final iso = scheduleDateTimeToIso(localMidnight)!;
      expect(iso, endsWith('Z'));
      expect(DateTime.parse(iso).isUtc, isTrue);
      // Round-trips to the same instant the picker meant, not a shifted one.
      expect(DateTime.parse(iso), localMidnight.toUtc());
    });

    test('an already-UTC value is unchanged in meaning', () {
      final utcValue = DateTime.utc(2026, 6, 20, 14, 30);
      final iso = scheduleDateTimeToIso(utcValue)!;
      expect(DateTime.parse(iso), utcValue);
    });
  });
}
```

`cd packages/client && flutter test test/features/beacon/data/repository/beacon_repository_schedule_serialization_test.dart`

Commit this phase's change on its own before moving to P2.

---

## Phase P2 — Server: defensive UTC normalization for `InputFieldDatetime`

**File:** `packages/server/lib/api/controllers/graphql/input/_input_types.dart`

After P1, every current caller (beacon `startAt`/`endAt`, the only fields
built from `InputFieldDatetime` today — confirmed via `grep -rn
"InputFieldDatetime(" packages/server/lib`) will always receive a
`Z`-suffixed string, which `DateTime.tryParse`/`DateTime.parse` already parse
correctly (`isUtc == true`, correct instant). This phase is a defensive
normalization for any input that arrives without an offset regardless — a
malformed/legacy caller, or any future field built on this same input type —
so the server never silently reinterprets ambiguous digits using its own
process-local timezone.

Replace lines 109-115:

```dart
DateTime? fromArgs(Map<String, dynamic> args) => switch (args[field.name]) {
  final String field when field.isNotEmpty => DateTime.tryParse(field),
  _ => null,
};

DateTime fromArgsNonNullable(Map<String, dynamic> args) =>
    DateTime.parse(args[field.name]! as String);
```

with:

```dart
DateTime? fromArgs(Map<String, dynamic> args) => switch (args[field.name]) {
  final String field when field.isNotEmpty => _parseAsUtc(field),
  _ => null,
};

DateTime fromArgsNonNullable(Map<String, dynamic> args) =>
    _forceUtc(DateTime.parse(args[field.name]! as String));

/// An offset-less ISO string (no trailing `Z`/`+HH:MM`) has no defined
/// timezone. Rather than let [DateTime.tryParse] silently interpret it as
/// wall-clock time in whatever zone this server process happens to run in
/// (issue #112), treat the digits themselves as already being UTC — the
/// same effect as if the caller had appended `Z`. This only changes
/// behavior for malformed/offset-less input; a correctly UTC-tagged string
/// (the only kind any current caller sends, after the client-side fix in
/// this same issue) parses identically to before.
DateTime? _parseAsUtc(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : _forceUtc(parsed);
}

DateTime _forceUtc(DateTime parsed) => parsed.isUtc
    ? parsed
    : DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      );
```

**Acceptance:** `InputFieldDatetime.fromArgs`/`fromArgsNonNullable` always
return a `DateTime` with `isUtc == true`. A `Z`-suffixed input parses to the
identical instant as before this change (no regression for the normal path).
An offset-less input parses its digits as UTC instead of as server-local time.

**Verification:** new test
`packages/server/test/api/controllers/graphql/input/input_field_datetime_test.dart`
(check the exact class/library import path used by sibling input-type tests
in `packages/server/test/api/controllers/graphql/`, if any exist, and match
it; otherwise import `_input_types.dart` directly via its package path):

```dart
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';

void main() {
  group('InputFieldDatetime', () {
    final field = InputFieldDatetime(fieldName: 'startAt');

    test('Z-suffixed input parses as UTC, instant unchanged', () {
      final result = field.fromArgs({'startAt': '2026-08-10T14:30:00.000Z'});
      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result, DateTime.utc(2026, 8, 10, 14, 30));
    });

    test('offset-less input is treated as UTC digits, not server-local', () {
      final result = field.fromArgs({'startAt': '2026-08-10T00:00:00.000'});
      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result, DateTime.utc(2026, 8, 10));
    });

    test('empty/absent input is null', () {
      expect(field.fromArgs({'startAt': ''}), isNull);
      expect(field.fromArgs({}), isNull);
    });

    test('fromArgsNonNullable also forces UTC', () {
      final result = field.fromArgsNonNullable({
        'startAt': '2026-08-10T00:00:00.000',
      });
      expect(result.isUtc, isTrue);
    });
  });
}
```

`cd packages/server && dart test test/api/controllers/graphql/input/input_field_datetime_test.dart`

Commit this phase's change on its own before moving to P3.

---

## Phase P3 — Client: `dateFormatYMD`/`timeFormatHm` always render viewer-local time

**File:** `packages/client/lib/ui/utils/ui_utils.dart`

Replace lines 78-82:

```dart
String dateFormatYMD(DateTime? dateTime) =>
    dateTime == null ? '' : _fmtYMd.format(dateTime);

String timeFormatHm(DateTime? dateTime) =>
    dateTime == null ? '' : _fmtHm.format(dateTime);
```

with:

```dart
/// Display-only formatters: always render the viewer's local wall-clock
/// time, regardless of whether [dateTime] is UTC or already local
/// (`.toLocal()` on an already-local value is a no-op). Do not bypass these
/// with a raw `DateFormat` call on an unconverted `DateTime` — that was the
/// bug behind issue #112's beacon_tile/inbox_item_tile/HUD-composer leaks.
String dateFormatYMD(DateTime? dateTime) =>
    dateTime == null ? '' : _fmtYMd.format(dateTime.toLocal());

String timeFormatHm(DateTime? dateTime) =>
    dateTime == null ? '' : _fmtHm.format(dateTime.toLocal());
```

No other file needs to change for this phase — `beacon_tile.dart:40-43`,
`inbox_item_tile.dart:121-125`, and `beacon_hud_metadata_composer.dart:268-270`
all call these two helpers and are fixed transitively. The four call sites
that already convert before calling (`schedule_date_format.dart`,
`relative_time.dart`, `coordination_log_row_chrome.dart`, `help_offer_tile.dart`,
`updates_receipt_card.dart`) are unaffected (idempotent double-conversion).

**Acceptance:** `dateFormatYMD(x)`/`timeFormatHm(x)` for any `DateTime x`
(UTC or local) produce the same text as calling `DateFormat.yMd()`/
`DateFormat.Hm()` on `x.toLocal()` directly.

**Verification:** new test `packages/client/test/ui/utils/ui_utils_datetime_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  test('dateFormatYMD/timeFormatHm always render viewer-local time', () {
    final utcInstant = DateTime.utc(2026, 6, 20, 23, 30);
    final local = utcInstant.toLocal();
    expect(dateFormatYMD(utcInstant), DateFormat.yMd().format(local));
    expect(timeFormatHm(utcInstant), DateFormat.Hm().format(local));
  });

  test('null input is empty string', () {
    expect(dateFormatYMD(null), '');
    expect(timeFormatHm(null), '');
  });
}
```

This test is written to pass under any timezone the runner happens to use
(it compares against `.toLocal()` computed the same way, not a hardcoded
string) — it exists to prove the conversion happens at all, and would have
failed before this fix on any machine whose local timezone isn't UTC. The
cross-formatter, multi-timezone regression net is Phase P5.

`cd packages/client && flutter test test/ui/utils/ui_utils_datetime_test.dart`

Commit this phase's change on its own before moving to P4.

---

## Phase P4 — Client: format `review.closesAt` instead of showing the raw ISO string

**File:** `packages/client/lib/features/evaluation/ui/widget/review_window_banner_host.dart`

Add the `intl` import:

```dart
import 'package:intl/intl.dart';
```

Add a private helper, following the exact pattern already used in
`review_contributions_screen.dart:285-297` (parse → `.toLocal()` →
`DateFormat.yMMMd(locale)`):

```dart
/// [ReviewWindowInfo.closesAt] is a raw server ISO string, not a [DateTime]
/// — format it the same way `review_contributions_screen.dart` does instead
/// of interpolating the raw wire value (issue #112).
String? _formatClosesAt(BuildContext context, String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateFormat.yMMMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(parsed.toLocal());
}
```

In `build`, right after `final l10n = L10n.of(context)!;` (line 39), compute
it once:

```dart
final closesAtLabel = _formatClosesAt(context, review.closesAt);
```

Replace both occurrences of the guard-and-render block (lines 55-61 and
79-85):

```dart
if (review.closesAt != null && review.closesAt!.isNotEmpty) ...[
  const SizedBox(height: 6),
  Text(
    l10n.beaconReviewWindowClosesAt(review.closesAt!),
    style: TenturaText.status(scheme.onSurfaceVariant),
  ),
],
```

with:

```dart
if (closesAtLabel != null) ...[
  const SizedBox(height: 6),
  Text(
    l10n.beaconReviewWindowClosesAt(closesAtLabel),
    style: TenturaText.status(scheme.onSurfaceVariant),
  ),
],
```

**Acceptance:** the review-window banner shows a localized calendar date
(e.g. "Closes Jun 20, 2026") in the viewer's local time, never the raw ISO
string; an unparsable or empty `closesAt` renders nothing, same as today.

**Verification:** extend
`packages/client/test/features/evaluation/review_window_banner_host_test.dart`.
The existing `_window()` fixture already sets `closesAt:
'2099-01-01T00:00:00.000Z'` (line 20) but no existing test asserts on that
text. Add:

```dart
testWidgets('formats closesAt as a localized date, not the raw ISO string', (
  tester,
) async {
  await pumpBanner(tester, window: _window());

  expect(find.textContaining('2099-01-01T00:00:00.000Z'), findsNothing);

  final expected = DateFormat.yMMMd('en').format(
    DateTime.parse('2099-01-01T00:00:00.000Z').toLocal(),
  );
  expect(find.textContaining(expected), findsOneWidget);
});
```

Add `import 'package:intl/intl.dart';` to the test file. Computing `expected`
via the same `.toLocal()` conversion (rather than a hardcoded literal) keeps
the test correct regardless of the runner's timezone.

`cd packages/client && flutter test test/features/evaluation/review_window_banner_host_test.dart`

Commit this phase's change on its own before moving to P5.

---

## Phase P5 — Client: multi-timezone regression matrix for date/time formatters

This directly addresses the audit's gap #15: no existing test exercises a
non-default timezone, DST, or the international date line.

**File (new):** `packages/client/test/ui/utils/timezone_conversion_matrix_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  // These fixed UTC instants are chosen close to a local day boundary for a
  // wide range of offsets (including UTC+14 / UTC-12) so a formatter that
  // forgets to convert to local time is very likely to show the wrong
  // calendar day under a non-UTC TZ, regardless of which zone the test
  // happens to run under. Run this file three times with `TZ=UTC`,
  // `TZ=Europe/Amsterdam` (DST-observing), and `TZ=Pacific/Kiritimati`
  // (UTC+14, across the international date line) — see
  // run_timezone_matrix.sh. Every assertion below is self-referential
  // (computed via the same `.toLocal()` the production code must use), so
  // it is correct under any of those TZs; it exists to catch a *missing*
  // `.toLocal()` call, not to hardcode one zone's expected string.
  final lateUtc = DateTime.utc(2026, 6, 20, 23, 30);
  final earlyUtc = DateTime.utc(2026, 1, 1, 0, 30);

  test('dateFormatYMD/timeFormatHm match direct .toLocal() formatting', () {
    for (final utc in [lateUtc, earlyUtc]) {
      final local = utc.toLocal();
      expect(dateFormatYMD(utc), DateFormat.yMd().format(local));
      expect(timeFormatHm(utc), DateFormat.Hm().format(local));
    }
  });

  test('formatScheduleDate matches direct .toLocal() formatting', () {
    final now = DateTime.utc(2026, 6, 15, 12).toLocal();
    for (final utc in [lateUtc, earlyUtc]) {
      final local = utc.toLocal();
      final expectedYear = local.year == now.year
          ? DateFormat.MMMd('en').format(local)
          : DateFormat.yMMMd('en').format(local);
      expect(
        formatScheduleDate(utc, localeName: 'en', now: now),
        expectedYear,
      );
    }
  });

  test('coordinationLogTimestampLabel matches direct .toLocal() formatting', () {
    for (final utc in [lateUtc, earlyUtc]) {
      final local = utc.toLocal();
      expect(
        coordinationLogTimestampLabel(utc),
        '${dateFormatYMD(local)} ${timeFormatHm(local)}',
      );
    }
  });

  test('compactRelativeTimeAgo diffs against the correct local day', () {
    final now = lateUtc.add(const Duration(days: 2)).toLocal();
    final l10n = lookupL10n(const Locale('en'));
    final label = compactRelativeTimeAgo(when: lateUtc, now: now, l10n: l10n);
    // Whatever the runner's TZ, "2 days ago" must be computed from the
    // same local calendar day the value converts to, not raw UTC digits.
    expect(label, l10n.relativeTimeDaysAgo(2));
  });
}
```

Check the exact import path/name for a synchronous `L10n` lookup by locale
(`lookupL10n` or equivalent — search `packages/client/lib/ui/l10n/` for how
other non-widget tests obtain an `L10n` instance without pumping a widget
tree, e.g. `relative_time_test.dart`, and match that pattern exactly instead
of guessing).

**File (new):** `packages/client/test/ui/utils/run_timezone_matrix.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
for tz in UTC Europe/Amsterdam Pacific/Kiritimati; do
  echo "=== TZ=$tz ==="
  TZ="$tz" flutter test test/ui/utils/timezone_conversion_matrix_test.dart
done
```

`chmod +x packages/client/test/ui/utils/run_timezone_matrix.sh`

**Acceptance:** `dateFormatYMD`, `timeFormatHm`, `formatScheduleDate`,
`coordinationLogTimestampLabel`, and `compactRelativeTimeAgo` all produce
output consistent with `.toLocal()` conversion, verified under UTC, a
DST-observing zone (Amsterdam), and a date-line zone (Kiritimati, UTC+14).

**Verification:**

```bash
cd packages/client && bash test/ui/utils/run_timezone_matrix.sh
```

All three `TZ=` runs must pass. If `TZ=Pacific/Kiritimati` or
`TZ=Europe/Amsterdam` isn't available in the execution environment's tzdata
(`dart` on Linux reads the system's IANA database via `TZ`), fall back to
`TZ=Asia/Tokyo` (UTC+9, no date-line ambiguity) and `TZ=America/New_York`
(DST-observing) respectively, and note the substitution in the journal.

Commit this phase's change on its own before moving to P6.

---

## Phase P6 — Full regression pass

Run the full verification set from §2, plus the TZ matrix from P5:

```bash
cd packages/client && flutter analyze
cd packages/client && flutter test
cd packages/client && bash test/ui/utils/run_timezone_matrix.sh
cd packages/server && dart analyze
cd packages/server && dart test
```

Re-read this plan's acceptance criteria for P1-P5 and confirm each against
the actual diff (not just "tests pass") before considering the plan complete:

- P1: `scheduleDateTimeToIso` always emits a `Z`-suffixed string; all three
  beacon mutation methods use it for both `startAt` and `endAt`.
- P2: `InputFieldDatetime` always returns `isUtc == true`; offset-less input
  is treated as UTC digits, not server-local time.
- P3: `dateFormatYMD`/`timeFormatHm` convert to local before formatting;
  `beacon_tile.dart`, `inbox_item_tile.dart`, `beacon_hud_metadata_composer.dart`
  needed no source change.
- P4: `review_window_banner_host.dart` shows a formatted local date, never
  the raw ISO string.
- P5: the TZ matrix passes under at least UTC + one DST zone + one
  far-offset zone.

No changes to `info_tab.dart`, `beacon_create_cubit.dart`,
`timestamptz_serializer.dart`, or any Drift table definition are expected —
confirm the diff doesn't touch them (per §0.4, no schema/wire-shape change is
in scope).

---

## 6. Out of scope / follow-ups

Do not implement these as part of this plan; note them in the journal's final
entry as follow-ups if still relevant when this plan completes:

- **Author-timezone storage and "your time vs. original" dual-label UI.**
  Explicitly deferred per §0.4 — a product decision, not a bug. If revisited,
  it needs a stored IANA zone (e.g. an `author_timezone` column on `beacons`),
  a wire change, and new UI; this plan's P1/P2 fixes are compatible with
  adding that later (they establish "always explicit UTC on the wire" as the
  baseline it would build on).
- **Date-only deadline "day may shift by ±1 for distant-timezone viewers."**
  Accepted consequence of storing `startAt`/`endAt` as instants without an
  author timezone (see §0.4's Amsterdam/New York example). Not a defect this
  plan fixes; would only be resolved by the deferred item above.
- **A general-purpose `RemoteApiService` test double/fake.** None exists in
  this codebase today (verified: no `class ... implements RemoteApiService`
  or `Fake`/`Mock` variant under `packages/client/test`). P1's verification
  deliberately tests the extracted pure function instead of building one —
  do not build a full repository-mocking harness as part of this plan; that
  is a larger, separate testing-infrastructure investment.
- **`TimestamptzSerializer` (`packages/client/lib/data/gql/timestamptz_serializer.dart`)
  normalization.** It performs a bare `DateTime.parse` with no forced
  `.toUtc()`/`.toLocal()`. Not touched here because every value it currently
  deserializes comes from server-generated `timestamptz` columns via Hasura,
  which always emit an offset — verified no regression risk — and after P1
  the client's own writes are also always offset-tagged. If a future field
  ever round-trips through this serializer without a guaranteed offset,
  revisit.
