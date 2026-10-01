// A22: the Results card «Итоги для тебя» shown on the request screen after
// finalize. Pumps `ClosureResultCard` over a real `ClosureCase` (taken from
// GetIt, like the other closure UI) on a fake `ClosureRepository` that returns
// what the server's `closureResultForViewer` / `closureState` would.
// Contract (only what the bead names):
//  - `features/closure/ui/widget/closure_result_card.dart` exports
//    `ClosureResultCard({required String beaconId, required String viewerId,
//    required ClosureMember author})`; it loads the result for the viewer and
//    the closure state itself (the state is the only source of the final
//    epoch and of the roster) and renders nothing of the card for a `null`
//    result. How it holds state internally is not pinned.
//  - Texts (locale `ru`, keys `closureResult*` in both ARBs), compared
//    case-insensitively and ignoring quote characters:
//      outcome line  «Автор отметил: выполнено» / «…не выполнено» /
//                    «…не смог судить»;
//      band          raised «Коллеги подняли твою часть», asIfSilent «Твоя
//                    часть — как если бы коллеги промолчали», lowered
//                    «Коллеги опустили твою часть»;
//      V8            outcome notDone AND band none: «Автор отметил: не
//                    выполнено — части в итогах нет», no band sentence;
//      V6            outcome notDone AND band raised: the outcome line plus
//                    the raised sentence, never «части в итогах нет»;
//      draft line    notCounted «Твои отметки не вошли: ты не нажал
//                    «Готово»», lastEditNotCounted «В расчёте прошлая версия,
//                    последняя правка не вошла» (plan A12 / U44); none shows
//                    neither.
//  - Own bookmarks: next to a person's name (a `Text` with exactly the
//    display name) there is a tappable Material bookmark icon. Tapping it
//    calls `setMark` with the final epoch from `fetchState`, the person's id
//    and the new state (on, then off on the next tap).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/closure_band.dart';
import 'package:tentura/features/closure/domain/entity/closure_draft_flag.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/widget/closure_result_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _beaconId = 'Bclosure00001';
const _epoch = 7;
const _me = 'me';

/// Server `ClosureEpochStatus.finalized`.
const _finalized = 1;

// Normalised (lower case, no quote characters) fragments of the copy.
const _outDone = 'автор отметил: выполнено';
const _outNotDone = 'автор отметил: не выполнено';
const _outCantJudge = 'автор отметил: не смог судить';
const _noShare = 'автор отметил: не выполнено — части в итогах нет';
const _noShareTail = 'части в итогах нет';
const _raised = 'коллеги подняли твою часть';
const _asIfSilent = 'твоя часть — как если бы коллеги промолчали';
const _lowered = 'коллеги опустили твою часть';
const _notCounted = 'твои отметки не вошли: ты не нажал готово';
const _lastEdit = 'в расчёте прошлая версия, последняя правка не вошла';

const _author = ClosureMember(id: 'auth', displayName: 'Name auth');

const _filledBookmarks = [
  Icons.bookmark,
  Icons.bookmark_rounded,
  Icons.bookmark_sharp,
  Icons.bookmark_added,
  Icons.bookmark_added_rounded,
];
const _outlineBookmarks = [
  Icons.bookmark_border,
  Icons.bookmark_outline,
  Icons.bookmark_border_rounded,
  Icons.bookmark_outline_rounded,
  Icons.bookmark_border_sharp,
  Icons.bookmark_outline_sharp,
  Icons.bookmark_add_outlined,
];

final class _FakeClosureRepository implements ClosureRepository {
  _FakeClosureRepository({
    required this.outcome,
    this.band = ClosureBand.none,
    this.draftFlag = ClosureDraftFlag.none,
    List<String> marks = const [],
  }) : marks = [...marks];

  final ClosureOutcome outcome;
  final ClosureBand band;
  final ClosureDraftFlag draftFlag;
  final List<String> marks;
  final calls = <Map<String, Object?>>[];

  @override
  Future<ClosureResult?> fetchResultForViewer(String beaconId) async =>
      ClosureResult(
        outcome: outcome,
        band: band,
        draftFlag: draftFlag,
        marks: [...marks],
      );

  @override
  Future<ClosureState> fetchState(String beaconId) async => ClosureState(
    epoch: _epoch,
    status: _finalized,
    role: ClosureRole.voter,
    members: [
      const ClosureMember(id: _me, displayName: 'Name me'),
      for (var i = 1; i <= 2; i++)
        ClosureMember(id: 'c$i', displayName: 'Name c$i'),
    ],
    closesAt: DateTime.utc(2030, 1, 10, 12),
    myMarks: [...marks],
  );

  @override
  Future<void> setMark({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) async {
    calls.add({
      'expectedEpoch': expectedEpoch,
      'targetId': targetId,
      'on': on,
    });
    on ? marks.add(targetId) : marks.remove(targetId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _norm(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp('[„“”«»"\']'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A `Text` whose normalised content contains [fragment].
Finder _copy(String fragment) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      _norm(w.data ?? w.textSpan?.toPlainText() ?? '').contains(fragment),
  description: 'Text containing «$fragment»',
);

Finder _bookmarks() => find.byWidgetPredicate(
  (w) =>
      w is Icon &&
      (_filledBookmarks.contains(w.icon) || _outlineBookmarks.contains(w.icon)),
);

/// The bookmark in the row of [id]: the one inside the nearest ancestor of
/// the person's name that holds any bookmark.
Finder _markOf(String id) {
  final name = find.text('Name $id').evaluate();
  expect(name, isNotEmpty, reason: 'no row for Name $id');
  Element? row;
  name.first.visitAncestorElements((a) {
    final n = find
        .descendant(
          of: find.byElementPredicate((e) => identical(e, a)),
          matching: _bookmarks(),
        )
        .evaluate()
        .length;
    if (n == 0) return true;
    row = a;
    return false;
  });
  expect(row, isNotNull, reason: 'Name $id has no bookmark');
  return find.descendant(
    of: find.byElementPredicate((e) => identical(e, row)),
    matching: _bookmarks(),
  );
}

Future<_FakeClosureRepository> _pump(
  WidgetTester tester,
  _FakeClosureRepository fake,
) async {
  tester.view
    ..physicalSize = const Size(360, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  GetIt.I.registerSingleton<ClosureCase>(
    ClosureCase(fake, env: const Env(), logger: Logger('test')),
  );
  addTearDown(() => GetIt.I.unregister<ClosureCase>());
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: ClosureResultCard(
            beaconId: _beaconId,
            viewerId: _me,
            author: _author,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void _expectNoBand() {
  expect(_copy(_raised), findsNothing);
  expect(_copy(_asIfSilent), findsNothing);
  expect(_copy(_lowered), findsNothing);
}

void main() {
  group('outcome line', () {
    testWidgets('done', (tester) async {
      await _pump(tester, _FakeClosureRepository(outcome: ClosureOutcome.done));
      expect(_copy(_outDone), findsOneWidget);
      expect(_copy(_outNotDone), findsNothing);
      expect(_copy(_outCantJudge), findsNothing);
    });

    testWidgets("can't judge", (tester) async {
      await _pump(
        tester,
        _FakeClosureRepository(outcome: ClosureOutcome.cantJudge),
      );
      expect(_copy(_outCantJudge), findsOneWidget);
      expect(_copy(_outDone), findsNothing);
    });

    testWidgets('band none for a non-notDone outcome: no band sentence, '
        'no «части нет»', (tester) async {
      await _pump(tester, _FakeClosureRepository(outcome: ClosureOutcome.done));
      _expectNoBand();
      expect(_copy(_noShareTail), findsNothing);
    });
  });

  group('band sentence', () {
    for (final (band, text) in [
      (ClosureBand.raised, _raised),
      (ClosureBand.asIfSilent, _asIfSilent),
      (ClosureBand.lowered, _lowered),
    ]) {
      testWidgets('${band.name} shows only its sentence', (tester) async {
        await _pump(
          tester,
          _FakeClosureRepository(outcome: ClosureOutcome.done, band: band),
        );
        expect(_copy(_outDone), findsOneWidget);
        expect(_copy(text), findsOneWidget);
        for (final other in [_raised, _asIfSilent, _lowered]) {
          if (other != text) expect(_copy(other), findsNothing);
        }
      });
    }
  });

  group('notDone', () {
    testWidgets('V8: band none shows the single «части в итогах нет» line', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeClosureRepository(outcome: ClosureOutcome.notDone),
      );
      expect(_copy(_noShare), findsOneWidget);
      // The author's outcome is always shown, alone or inside that line.
      expect(_copy(_outNotDone), findsWidgets);
      _expectNoBand();
    });

    for (final (band, text) in [
      (ClosureBand.asIfSilent, _asIfSilent),
      (ClosureBand.lowered, _lowered),
    ]) {
      testWidgets('${band.name}: outcome line plus band, never «части нет»', (
        tester,
      ) async {
        await _pump(
          tester,
          _FakeClosureRepository(outcome: ClosureOutcome.notDone, band: band),
        );
        expect(_copy(_outNotDone), findsOneWidget);
        expect(_copy(text), findsOneWidget);
        expect(_copy(_noShareTail), findsNothing);
        for (final other in [_raised, _asIfSilent, _lowered]) {
          if (other != text) expect(_copy(other), findsNothing);
        }
      });
    }

    testWidgets('V6: band raised shows outcome + raised, not the V8 line', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeClosureRepository(
          outcome: ClosureOutcome.notDone,
          band: ClosureBand.raised,
        ),
      );
      expect(_copy(_outNotDone), findsOneWidget);
      expect(_copy(_raised), findsOneWidget);
      expect(_copy(_noShareTail), findsNothing);
      expect(_copy(_asIfSilent), findsNothing);
      expect(_copy(_lowered), findsNothing);
    });
  });

  group('draft line', () {
    testWidgets('none shows no draft line', (tester) async {
      await _pump(tester, _FakeClosureRepository(outcome: ClosureOutcome.done));
      expect(_copy(_notCounted), findsNothing);
      expect(_copy(_lastEdit), findsNothing);
    });

    testWidgets('notCounted', (tester) async {
      await _pump(
        tester,
        _FakeClosureRepository(
          outcome: ClosureOutcome.done,
          draftFlag: ClosureDraftFlag.notCounted,
        ),
      );
      expect(_copy(_notCounted), findsOneWidget);
      expect(_copy(_lastEdit), findsNothing);
    });

    testWidgets('lastEditNotCounted', (tester) async {
      await _pump(
        tester,
        _FakeClosureRepository(
          outcome: ClosureOutcome.done,
          draftFlag: ClosureDraftFlag.lastEditNotCounted,
        ),
      );
      expect(_copy(_lastEdit), findsOneWidget);
      expect(_copy(_notCounted), findsNothing);
    });
  });

  group('own bookmarks', () {
    testWidgets('each toggle calls setMark on the final epoch', (tester) async {
      final fake = await _pump(
        tester,
        _FakeClosureRepository(outcome: ClosureOutcome.done),
      );

      await tester.tap(_markOf('c1').first);
      await tester.pumpAndSettle();
      expect(fake.calls.last, {
        'expectedEpoch': _epoch,
        'targetId': 'c1',
        'on': true,
      });

      await tester.tap(_markOf('c2').first);
      await tester.pumpAndSettle();
      expect(fake.calls.last, {
        'expectedEpoch': _epoch,
        'targetId': 'c2',
        'on': true,
      });

      // Toggling the same person again turns the bookmark off.
      await tester.tap(_markOf('c1').first);
      await tester.pumpAndSettle();
      expect(fake.calls.last, {
        'expectedEpoch': _epoch,
        'targetId': 'c1',
        'on': false,
      });
      expect(fake.calls, hasLength(3));
    });

    testWidgets('the author can be bookmarked too', (tester) async {
      final fake = await _pump(
        tester,
        _FakeClosureRepository(outcome: ClosureOutcome.done),
      );
      await tester.tap(_markOf('auth').first);
      await tester.pumpAndSettle();
      expect(fake.calls.single, {
        'expectedEpoch': _epoch,
        'targetId': 'auth',
        'on': true,
      });
    });
  });
}
