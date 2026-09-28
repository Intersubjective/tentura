// tentura-617.31: fact history sheet — issue #181 plan §3 (layout, diff
// against the entry below, 'Show full' over 6 lines, kind-3 imported
// label, restored-from label, visibility/pin events), D2 (restore
// appends, Undo snackbar, no confirm), D5 (neutral diff styling), §14.6
// (diff rendering). Also wires the manage sheet's 'Edit history' item to
// open this sheet (today `showFactActionsSheet`/`showBeaconFactActions`
// never pass `onEditHistory`, so it never appears from a real call site).
//
// `FactHistorySheet` / `showFactHistorySheet` do not exist yet, so this
// file does not compile — every test below fails until they (and the
// `onEditHistory` wiring in fact_actions_sheet.dart) are added.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_fact_actions.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart' show pumpUntil;
import 'room_cubit_fakes.dart';

const _kBeaconId = 'b-fact-history-sheet-test';
const _kFactCardId = 'fact-history-sheet-1';

BeaconFactHistoryEdited _edited({
  required String id,
  required int seq,
  required String text,
  String actorTitle = 'Anna',
}) => BeaconFactHistoryEdited(
  id: id,
  factCardId: _kFactCardId,
  seq: seq,
  factText: text,
  actorId: 'actor-$id',
  actorTitle: actorTitle,
  createdAt: DateTime.utc(2026, 1, seq),
);

BeaconFactHistoryImported _imported({
  required String id,
  required int seq,
  required String text,
  String actorTitle = '',
}) => BeaconFactHistoryImported(
  id: id,
  factCardId: _kFactCardId,
  seq: seq,
  factText: text,
  actorId: null,
  actorTitle: actorTitle,
  createdAt: DateTime.utc(2026, 1, seq),
);

/// Serves a fixed [entries] page and records every `restore` call, in
/// order, so a test can assert exactly which (fromSeq, baseRevisionSeq)
/// pairs the cubit passed through — for both the initial restore and a
/// subsequent Undo — rather than inferring success from snackbar text.
///
/// Most tests only need one unchanging page and should set [entries].
/// A test that needs the post-restore reload(s) to show a *different*
/// timeline (e.g. to prove Undo's reload really brings prior content
/// back) should set [pagesAfterRestore] instead: index 0 is served
/// before any restore, index N after the Nth `restore()` call.
class _FakeFactHistoryRepository extends Fake
    implements BeaconFactCardRepository {
  List<BeaconFactTimelineEntry> entries = const [];
  List<List<BeaconFactTimelineEntry>>? pagesAfterRestore;
  int restoreReturnsSeq = 99;

  final List<({int fromSeq, int baseRevisionSeq})> restoreCalls = [];

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) async {
    final pages = pagesAfterRestore;
    if (pages == null) return (entries: entries, nextCursor: null);
    final index = restoreCalls.length < pages.length
        ? restoreCalls.length
        : pages.length - 1;
    return (entries: pages[index], nextCursor: null);
  }

  @override
  Future<int> restore({
    required String beaconId,
    required String factCardId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) async {
    restoreCalls.add((fromSeq: fromSeq, baseRevisionSeq: baseRevisionSeq));
    return restoreReturnsSeq;
  }
}

void _collectSpans(InlineSpan span, List<(String, TextStyle?)> out) {
  if (span is TextSpan) {
    final text = span.text;
    if (text != null && text.isNotEmpty) out.add((text, span.style));
    for (final child in span.children ?? const <InlineSpan>[]) {
      _collectSpans(child, out);
    }
  }
}

List<(String, TextStyle?)> _allSpans(WidgetTester tester) {
  final leaves = <(String, TextStyle?)>[];
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    _collectSpans(r.text, leaves);
  }
  return leaves;
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required _FakeFactHistoryRepository repo,
  required bool canMutate,
  int baseRevisionSeq = 5,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showFactHistorySheet(
                ctx,
                beaconId: _kBeaconId,
                factCardId: _kFactCardId,
                baseRevisionSeq: baseRevisionSeq,
                canMutate: canMutate,
                repository: repo,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('FactHistorySheet layout (tentura-617.31)', () {
    testWidgets('entries render newest first', (tester) async {
      // Each row's body is diffed against the entry below it (plan §3), so
      // a body-text word can legitimately appear in *two* rows: once as
      // part of the merged diff of the row above it, and once plain in its
      // own row. Ordering markers must therefore live in each entry's
      // `actorTitle` (never diffed, never merged into a neighbouring row)
      // rather than in `factText`, or a match inside the wrong row could
      // make this assertion pass regardless of actual list order.
      final repo = _FakeFactHistoryRepository()
        ..entries = [
          _edited(
            id: 'e3',
            seq: 3,
            text: 'v3 body',
            actorTitle: 'ZetaNewest',
          ),
          _edited(
            id: 'e2',
            seq: 2,
            text: 'v2 body',
            actorTitle: 'BetaMiddle',
          ),
          _edited(
            id: 'e1',
            seq: 1,
            text: 'v1 body',
            actorTitle: 'AlphaOldest',
          ),
        ];

      await _pumpSheet(tester, repo: repo, canMutate: false);

      expect(find.textContaining('ZetaNewest'), findsOneWidget);
      expect(find.textContaining('BetaMiddle'), findsOneWidget);
      expect(find.textContaining('AlphaOldest'), findsOneWidget);

      final newest = tester.getTopLeft(find.textContaining('ZetaNewest'));
      final middle = tester.getTopLeft(find.textContaining('BetaMiddle'));
      final oldest = tester.getTopLeft(find.textContaining('AlphaOldest'));
      expect(
        newest.dy,
        lessThan(middle.dy),
        reason: 'seq 3 (newest) must render above seq 2',
      );
      expect(
        middle.dy,
        lessThan(oldest.dy),
        reason: 'seq 2 must render above seq 1 (oldest)',
      );
    });

    testWidgets(
      'author labels share one left edge across differently sized bodies',
      (tester) async {
        // Regression: Column defaulted to CrossAxisAlignment.center, so
        // shorter rows shifted right and the timeline rail looked crooked.
        final repo = _FakeFactHistoryRepository()
          ..entries = [
            _edited(
              id: 'e3',
              seq: 3,
              text: 'short',
              actorTitle: 'ShortBodyAuthor',
            ),
            _edited(
              id: 'e2',
              seq: 2,
              text: 'a much longer body that widens the content column',
              actorTitle: 'LongBodyAuthor',
            ),
            _edited(
              id: 'e1',
              seq: 1,
              text: 'mid',
              actorTitle: 'MidBodyAuthor',
            ),
          ];

        await _pumpSheet(tester, repo: repo, canMutate: false);

        final shortDx =
            tester.getTopLeft(find.textContaining('ShortBodyAuthor')).dx;
        final longDx =
            tester.getTopLeft(find.textContaining('LongBodyAuthor')).dx;
        final midDx =
            tester.getTopLeft(find.textContaining('MidBodyAuthor')).dx;

        expect(
          shortDx,
          moreOrLessEquals(longDx, epsilon: 0.5),
          reason: 'short-body row must not shift right of long-body row',
        );
        expect(
          midDx,
          moreOrLessEquals(longDx, epsilon: 0.5),
          reason: 'mid-body row must share the same left edge',
        );
      },
    );

    testWidgets(
      'an added word gets a background span, a removed word gets lineThrough',
      (tester) async {
        final repo = _FakeFactHistoryRepository()
          ..entries = [
            _edited(id: 'e2', seq: 2, text: 'Gate code is 5678'),
            _edited(id: 'e1', seq: 1, text: 'Gate code is 1234'),
          ];

        await _pumpSheet(tester, repo: repo, canMutate: false);

        final spans = _allSpans(tester);
        final added = spans.where((s) => s.$1.contains('5678')).toList();
        final removed = spans.where((s) => s.$1.contains('1234')).toList();

        expect(added, isNotEmpty, reason: 'added word "5678" must render');
        expect(
          added.any((s) => s.$2?.backgroundColor != null),
          isTrue,
          reason: 'an added word must carry a background colour',
        );
        expect(removed, isNotEmpty, reason: 'removed word "1234" must render');
        expect(
          removed.any(
            (s) =>
                s.$2?.decoration?.contains(TextDecoration.lineThrough) ??
                false,
          ),
          isTrue,
          reason: 'a removed word must be struck through',
        );
      },
    );

    testWidgets(
      'a kind-3 (imported) entry shows baseline copy with no author',
      (tester) async {
        final repo = _FakeFactHistoryRepository()
          ..entries = [
            _imported(id: 'imp', seq: 1, text: 'Baseline text', actorTitle: 'Zzz'),
          ];

        await _pumpSheet(tester, repo: repo, canMutate: false);

        expect(
          find.textContaining('Zzz'),
          findsNothing,
          reason: 'an imported (kind 3) row must omit the author entirely',
        );
        final flattened = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((r) => r.text.toPlainText().toLowerCase())
            .join(' ');
        expect(
          flattened,
          contains('not recorded'),
          reason:
              'plan §14.6: an imported baseline must say its earlier '
              'history was not recorded',
        );
      },
    );

    testWidgets(
      'a visibility-change event between two revisions still renders, '
      'and does not become the diff baseline for the revision above it',
      (tester) async {
        final repo = _FakeFactHistoryRepository()
          ..entries = [
            _edited(id: 'e2', seq: 2, text: 'Gate code is 5678'),
            BeaconFactHistoryEvent(
              id: 'ev1',
              actorId: 'actor-ev1',
              actorTitle: 'VisibilityActor',
              createdAt: DateTime.utc(2026, 1, 1, 12),
              type: BeaconActivityEventTypeBits.factVisibilityChanged,
              visibilityFrom: BeaconFactCardVisibilityBits.room,
              visibilityTo: BeaconFactCardVisibilityBits.public,
            ),
            _edited(id: 'e1', seq: 1, text: 'Gate code is 1234'),
          ];

        await _pumpSheet(tester, repo: repo, canMutate: false);

        expect(
          find.textContaining('VisibilityActor'),
          findsOneWidget,
          reason:
              'plan §3: a BeaconFactHistoryEvent row (visibility change) '
              'must render in the timeline between the surrounding '
              'revisions, not be silently dropped',
        );

        // Risk (plan §3/§14.6): diff only against the next OLDER
        // *revision*, skipping an event row directly below. If seq 2
        // wrongly treated the event as "nothing below" it would render
        // plain (no diff spans); if it wrongly skipped past seq 1 too it
        // would also show no diff. Either bug leaves these assertions
        // failing, since seq 1 ('1234') is the only revision beneath the
        // event and must still be the diff baseline for seq 2 ('5678').
        final spans = _allSpans(tester);
        final added = spans.where((s) => s.$1.contains('5678')).toList();
        final removed = spans.where((s) => s.$1.contains('1234')).toList();
        expect(
          added.any((s) => s.$2?.backgroundColor != null),
          isTrue,
          reason:
              'seq 2 must still diff against seq 1 (added "5678"), '
              'skipping the event row in between',
        );
        expect(
          removed.any(
            (s) =>
                s.$2?.decoration?.contains(TextDecoration.lineThrough) ??
                false,
          ),
          isTrue,
          reason:
              'seq 1 must still be used as the diff baseline for seq 2 '
              '(removed "1234"), not the interposed event row',
        );
      },
    );

    testWidgets(
      'a pin (unpin) event entry renders in the timeline',
      (tester) async {
        final repo = _FakeFactHistoryRepository()
          ..entries = [
            BeaconFactHistoryEvent(
              id: 'ev-unpin',
              actorId: 'actor-unpin',
              actorTitle: 'UnpinActor',
              createdAt: DateTime.utc(2026, 1, 2, 9),
              type: BeaconActivityEventTypeBits.factRemoved,
            ),
            _edited(id: 'e1', seq: 1, text: 'Gate code is 1234'),
          ];

        await _pumpSheet(tester, repo: repo, canMutate: false);

        expect(
          find.textContaining('UnpinActor'),
          findsOneWidget,
          reason:
              'plan §3: a pin/unpin event row must render in the '
              'timeline, not be silently dropped',
        );
      },
    );

    testWidgets(
      "a body over 6 lines collapses behind 'Show full', which expands it",
      (tester) async {
        final longText = List.generate(
          10,
          (i) => 'Line ${i + 1} content',
        ).join('\n');
        final repo = _FakeFactHistoryRepository()
          ..entries = [_edited(id: 'e1', seq: 1, text: longText)];

        await _pumpSheet(tester, repo: repo, canMutate: false);

        expect(
          find.text('Show full'),
          findsOneWidget,
          reason:
              "plan §3: a body over 6 lines must collapse behind a "
              "'Show full' control",
        );
        expect(
          find.textContaining('Line 10 content'),
          findsNothing,
          reason: 'a collapsed body must not render past the 6-line limit',
        );

        await tester.tap(find.text('Show full'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Line 10 content'),
          findsOneWidget,
          reason: "tapping 'Show full' must reveal the full body text",
        );
      },
    );

    testWidgets(
      'a restored entry shows the localized restored-from label with the '
      'source revision, not just the bare number anywhere on screen',
      (tester) async {
        final repo = _FakeFactHistoryRepository()
          ..entries = [
            BeaconFactHistoryRestored(
              id: 'r1',
              factCardId: _kFactCardId,
              seq: 9,
              factText: 'Restored text',
              restoredFromSeq: 42,
              actorId: 'actor-r1',
              actorTitle: 'Restorer',
              createdAt: DateTime.utc(2026, 1, 9),
            ),
          ];

        await _pumpSheet(tester, repo: repo, canMutate: false);

        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(
          find.textContaining(l10n.beaconRoomFactHistoryRestoredFrom(42)),
          findsOneWidget,
          reason:
              'plan §3: a restored entry must show the localized '
              '"restored from revision" copy together with the source '
              'seq (42), not merely display 42 somewhere unrelated (e.g. '
              'as part of a date or an unrelated seq)',
        );
      },
    );
  });

  group('FactHistorySheet restore (tentura-617.31)', () {
    testWidgets('"Restore this version" is hidden without canMutate', (
      tester,
    ) async {
      final repo = _FakeFactHistoryRepository()
        ..entries = [_edited(id: 'e1', seq: 3, text: 'Some fact text')];

      await _pumpSheet(tester, repo: repo, canMutate: false);

      expect(find.text('Restore this version'), findsNothing);
    });

    testWidgets('"Restore this version" is shown for a mutator on non-head', (
      tester,
    ) async {
      final repo = _FakeFactHistoryRepository()
        ..entries = [
          _edited(id: 'head', seq: 4, text: 'Head text'),
          _edited(id: 'e1', seq: 3, text: 'Some fact text'),
        ];

      await _pumpSheet(tester, repo: repo, canMutate: true);

      expect(find.text('Restore this version'), findsOneWidget);
    });

    testWidgets('"Restore this version" is hidden on the head revision', (
      tester,
    ) async {
      final repo = _FakeFactHistoryRepository()
        ..entries = [_edited(id: 'e1', seq: 3, text: 'Some fact text')];

      await _pumpSheet(tester, repo: repo, canMutate: true);

      expect(find.text('Restore this version'), findsNothing);
    });

    testWidgets(
      'tapping it calls restore without a confirm dialog, shows an '
      'in-sheet Undo banner, then Undo restores the previous head text',
      (tester) async {
        // Distinct, single-token bodies (no shared words) so a wordDiff
        // merge between neighbouring rows can never make one marker leak
        // into a count meant for the other.
        const headText = 'AAAA_HEAD_MARKER';
        const olderText = 'BBBB_OLDER_MARKER';
        final repo = _FakeFactHistoryRepository()
          ..restoreReturnsSeq = 6
          ..pagesAfterRestore = [
            // Loaded when the sheet opens: head is seq 5.
            [
              _edited(id: 'head', seq: 5, text: headText),
              _edited(id: 'older', seq: 3, text: olderText),
            ],
            // Reload after restoring seq 3: server appends a new head
            // (seq 6) carrying seq 3's text (D2: restore appends).
            [
              _edited(id: 'after-restore', seq: 6, text: olderText),
              _edited(id: 'head', seq: 5, text: headText),
              _edited(id: 'older', seq: 3, text: olderText),
            ],
            // Reload after Undo: another append (seq 7) carrying the
            // ORIGINAL head's text back.
            [
              _edited(id: 'after-undo', seq: 7, text: headText),
              _edited(id: 'after-restore', seq: 6, text: olderText),
              _edited(id: 'head', seq: 5, text: headText),
              _edited(id: 'older', seq: 3, text: olderText),
            ],
          ];

        await _pumpSheet(
          tester,
          repo: repo,
          canMutate: true,
          baseRevisionSeq: 5,
        );

        // Two rows may offer "Restore this version" (whether the head row
        // does too is unspecified); the older (seq 3) row is always last.
        await tester.tap(find.text('Restore this version').last);
        await tester.pump();
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'D2: restore fires immediately, no confirm dialog',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tapping "Restore this version" must call the cubit's restore,
        // observable here as exactly one repository.restore call carrying
        // the tapped row's seq and the sheet's fixed baseRevisionSeq — not
        // inferred from snackbar text appearing.
        expect(
          repo.restoreCalls,
          hasLength(1),
          reason: 'tapping "Restore this version" must call cubit.restore',
        );
        expect(
          repo.restoreCalls[0],
          (fromSeq: 3, baseRevisionSeq: 5),
          reason: 'first restore: fromSeq is the tapped row, '
              'baseRevisionSeq is the sheet-open-time head',
        );
        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.beaconRoomFactHistoryRestoredSnackbar),
          findsOneWidget,
          reason: 'successful restore shows an in-sheet Undo banner',
        );
        expect(find.text('Undo'), findsOneWidget);

        final countAfterRestore = find
            .textContaining(headText)
            .evaluate()
            .length;

        await tester.tap(find.text('Undo'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Undo must call the cubit's restore a second time, observable as
        // a second repository.restore call — again asserted on the call
        // log, not on the snackbar having disappeared or any other
        // visibility signal.
        expect(
          repo.restoreCalls,
          hasLength(2),
          reason: 'Undo must call restore again',
        );
        expect(
          repo.restoreCalls[1].fromSeq,
          5,
          reason:
              'Undo must restore the seq that was head before the first '
              'restore, not the seq (3) just restored',
        );
        expect(
          repo.restoreCalls[1].baseRevisionSeq,
          5,
          reason:
              'FactHistoryCubit fixes baseRevisionSeq at construction and '
              'never refetches it (binding convention: "do not inject '
              'RoomCubit or refetch baseRevisionSeq after open"). Both '
              'the initial restore and Undo go through the same cubit '
              'instance and so must carry the same fixed value (5), '
              'never the seq returned by the first restore (6).',
        );

        // Prove Undo's reload actually renders the previous head's text
        // again as a *new* entry — not merely that restore() was called
        // with the right arguments while the UI silently failed to
        // reflect it.
        final countAfterUndo = find.textContaining(headText).evaluate().length;
        expect(
          countAfterUndo,
          greaterThan(countAfterRestore),
          reason:
              'Undo must bring the previous head text back into the '
              'rendered timeline as a new entry',
        );
      },
    );
  });

  group('FactHistorySheet wiring (tentura-617.31)', () {
    testWidgets(
      'tapping "Edit history" in the manage sheet opens the fact history '
      'sheet',
      (tester) async {
        final getIt = GetIt.instance;
        if (getIt.isRegistered<BeaconFactCardRepository>()) {
          getIt.unregister<BeaconFactCardRepository>();
        }
        getIt.registerSingleton<BeaconFactCardRepository>(
          _FakeFactHistoryRepository(),
        );
        addTearDown(() {
          if (getIt.isRegistered<BeaconFactCardRepository>()) {
            getIt.unregister<BeaconFactCardRepository>();
          }
        });

        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        );
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final fact = BeaconFactCard(
          id: 'fact-wire-1',
          beaconId: kRoomCubitFakeBeaconId,
          factText: 'Gate code is 4821',
          visibility: BeaconFactCardVisibilityBits.public,
          pinnedBy: 'Uanna',
          pinnedByTitle: 'Anna',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          status: BeaconFactCardStatusBits.corrected,
          revisionSeq: 2,
          lastEditedBy: 'Uanna',
          lastEditedByTitle: 'Anna',
          lastEditedAt: DateTime.now().subtract(const Duration(hours: 2)),
        );

        await tester.binding.setSurfaceSize(const Size(375, 812));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('en'),
            home: TenturaResponsiveScope(
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => showFactActionsSheet(
                      ctx,
                      cubit: cubit,
                      fact: fact,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.beaconRoomFactCardActionEditHistory),
          findsOneWidget,
          reason: 'revisionSeq 2 must offer the history action',
        );

        await tester.tap(find.text(l10n.beaconRoomFactCardActionEditHistory));
        await tester.pumpAndSettle();

        expect(
          find.byType(FactHistorySheet),
          findsOneWidget,
          reason:
              'showFactActionsSheet must wire onEditHistory to open '
              'FactHistorySheet; today it never passes onEditHistory at '
              'all, so the item never appears from this production call '
              'site',
        );
      },
    );

    testWidgets(
      'tapping "Edit history" in showBeaconFactActions (beacon detail '
      'facts) also opens the fact history sheet',
      (tester) async {
        final getIt = GetIt.instance;
        if (getIt.isRegistered<BeaconFactCardRepository>()) {
          getIt.unregister<BeaconFactCardRepository>();
        }
        getIt.registerSingleton<BeaconFactCardRepository>(
          _FakeFactHistoryRepository(),
        );
        addTearDown(() {
          if (getIt.isRegistered<BeaconFactCardRepository>()) {
            getIt.unregister<BeaconFactCardRepository>();
          }
        });

        const beaconDetailBeaconId = 'b-fact-history-wire-beacon-view';
        final beacon = Beacon(
          id: beaconDetailBeaconId,
          title: 'Facts beacon',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: BeaconStatus.open,
          canReadContent: true,
          author: const Profile(id: 'Uauthor', displayName: 'Author'),
        );
        final fact = BeaconFactCard(
          id: 'fact-wire-2',
          beaconId: beaconDetailBeaconId,
          factText: 'Gate code is 4821',
          visibility: BeaconFactCardVisibilityBits.public,
          pinnedBy: 'Uanna',
          pinnedByTitle: 'Anna',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          status: BeaconFactCardStatusBits.corrected,
          revisionSeq: 2,
          lastEditedBy: 'Uanna',
          lastEditedByTitle: 'Anna',
          lastEditedAt: DateTime.now().subtract(const Duration(hours: 2)),
        );

        // BeaconViewCubit's initial load resolves via real (non-fake-clock)
        // async gaps; testWidgets runs under a FakeAsync zone, so awaiting
        // it directly here would hang forever (see beacon_pinned_facts_
        // sheet_test.dart's loadedCubit, which wraps the same pattern in
        // tester.runAsync for this reason).
        final cubit = (await tester.runAsync(() async {
          final beaconViewCase = buildTestBeaconViewCase(
            beaconRepo: TrackingBeaconRepository()
              ..fetchByIdHandler = (_) async => beacon,
            factCardsRepo: FakeBeaconViewFactCardRepository(cards: [fact]),
          );
          final c = BeaconViewCubit(
            id: beaconDetailBeaconId,
            myProfile: const Profile(id: 'Uviewer', displayName: 'Viewer'),
            beaconViewCase: beaconViewCase,
            effects: FakeUiEffectPort(),
          );
          await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
          return c;
        }))!;
        addTearDown(cubit.close);

        await tester.binding.setSurfaceSize(const Size(375, 812));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('en'),
            home: TenturaResponsiveScope(
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => showBeaconFactActions(
                      ctx,
                      cubit: cubit,
                      fact: fact,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.beaconRoomFactCardActionEditHistory),
          findsOneWidget,
          reason: 'revisionSeq 2 must offer the history action',
        );

        await tester.tap(find.text(l10n.beaconRoomFactCardActionEditHistory));
        await tester.pumpAndSettle();

        expect(
          find.byType(FactHistorySheet),
          findsOneWidget,
          reason:
              'showBeaconFactActions (used for beacon detail facts, e.g. '
              'beacon_pinned_facts_sheet.dart) must also wire '
              'onEditHistory to open FactHistorySheet; today it never '
              'passes onEditHistory at all, so a fact opened from beacon '
              'detail could stay unwired even if showFactActionsSheet '
              '(RoomCubit) alone were fixed',
        );
      },
    );
  });
}
