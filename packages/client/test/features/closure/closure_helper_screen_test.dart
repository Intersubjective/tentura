// A21: helper screen «Поддержать коллег». Pumps `ClosureHelperView` (body of
// the screen, no AutoRouter) under a real `ClosureHelperCubit` over a real
// `ClosureCase` on a fake `ClosureRepository` that behaves like the server
// (draft / committed support, `inCalcText` code, scapegoat release U56).
// Contract the implementation must follow:
//  - files: `ui/bloc/closure_helper_cubit.dart` (`ClosureHelperCubit`),
//    `ui/screen/closure_helper_screen.dart` (`ClosureHelperView`),
//    `ui/widget/share_flow_diagram.dart` (`ShareFlowDiagram`, see its test).
//  - cubit: `ClosureHelperCubit(ClosureCase, {required String beaconId,
//    required String viewerId, required ClosureMember author})`; loads
//    `fetchState` on creation; every write passes `expectedEpoch`;
//    `ClosureStaleEpochException` => `fetchState` again + a SnackBar. The
//    author is not in `ClosureState.members`; the viewer is (skip it).
//  - `ClosureState.status` is the server epoch status: 0 evaluating,
//    1 finalized. The notices of this screen are for an evaluating epoch.
//  - voting UI (toggles, «Готово», «Пропустить», header, legend, privacy)
//    is for a `voter` with colleagues to support; a `member` role (left or
//    removed) sees only the bookmark section, the deadline and the U58
//    notice. Which of the voting controls a 1- or 2-person roster shows is
//    not pinned here; the U58 notice is.
//  - `inCalcText` is the server code `notCounted` | `counted` | `differs`;
//    «В расчёте» lists `mySupport` names joined by «, ».
//  - Controls are found by VISIBLE content only, no semantics labels: a
//    colleague's name is a `Text` with exactly the display name, and each
//    control belongs to the name nearest to it vertically (one row per
//    person). The support toggle is a `Text` «☆ Поддержать» / «★ Поддерживаю»
//    inside the tappable control; the ▲ / ▼ indicators are separate
//    `Text('▲')` / `Text('▼')`; the bookmark is a tappable Material bookmark
//    icon (`Icons.bookmark` when set, `Icons.bookmark_border` when not).
//  - Only these ValueKeys are pinned (no visible text exists for them):
//    `closure.helper.info` (the (i) button).
//  - the confirm dialog on «Пропустить» is an `AlertDialog` with two
//    `ButtonStyleButton`s: cancel first, confirm last.
//  - the (i) sheet builds `ShareFlowDiagram(memberCount: roster size,
//    avatars: author + every member)`.
//  - strings are Russian (locale `ru`), keys `closureHelper*` in both ARBs.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/bloc/closure_helper_cubit.dart';
import 'package:tentura/features/closure/ui/screen/closure_helper_screen.dart';
import 'package:tentura/features/closure/ui/widget/share_flow_diagram.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _beaconId = 'Bclosure00001';
const _epoch = 4;
const _me = 'me';

/// Server `ClosureEpochStatus` values.
const _evaluating = 0;
const _finalized = 1;

const _header =
    'Чья работа, по-твоему, была важной? Твоя часть от этого не меняется';
const _legend = '▲ получат добавку — ▼ её отдадут те, кого ты не выбрал';
const _supportEdge =
    'Поддержка ещё и чуть усиливает твою связь в сети с теми, кого ты '
    'выбрал. Им не придёт уведомление';
const _authorEdge =
    'Когда запрос закроется, в сети появится слабая связь от тебя к автору: '
    'вы работали вместе. Не хочешь её — выйди из запроса до закрытия';
const _scaling =
    'Ты не знаешь, как решил автор, — и знать не нужно. Поддержи тех, чья '
    'работа, по-твоему, была важной. Если автор уже оценил человека высоко, '
    'добавка будет маленькой; если низко — заметной. Отдают в основном те, '
    'кому автор дал больше. Автор твой выбор не видит';
const _bookmarkCopy =
    'Закладка чуть усиливает твою связь с этим человеком в сети. Ему не '
    'придёт уведомление, части в этом запросе не меняются. Поставить и снять '
    'можно и позже';
const _privacy =
    'В приложении твой выбор не видят. По своим итогам другие могут о нём '
    'догадаться';
const _statusNone = 'В расчёт ещё не входит';
const _statusDiffers = 'На экране иначе — «Готово» заменит расчёт';
const _skipLabel = 'Пропустить — не отмечаю никого';
const _skipNote = 'Твоя часть не меняется никогда';
const _skipConfirm = 'Стереть то, что уже в расчёте?';
const _off = '☆ Поддержать';
const _on = '★ Поддерживаю';

String _scapegoat(String name) =>
    'Поддержать всех — то же, что никого. Кто-то должен отдать: снята самая '
    'ранняя ($name)';

const _author = ClosureMember(id: 'auth', displayName: 'Name auth');

const _filledBookmarks = [Icons.bookmark, Icons.bookmark_rounded];
const _outlineBookmarks = [
  Icons.bookmark_border,
  Icons.bookmark_outline,
  Icons.bookmark_border_rounded,
  Icons.bookmark_outline_rounded,
];

/// Behaves like the server for the viewer: ordered draft, committed copy,
/// `inCalcText` code and the U56 release of the earliest press.
final class _FakeClosureRepository implements ClosureRepository {
  _FakeClosureRepository({
    required this.members,
    this.role = ClosureRole.voter,
    this.status = _evaluating,
    List<String> draft = const [],
    List<String>? committed,
    List<String> marks = const [],
    this.earlyCloseAt,
  }) : draft = [...draft],
       committed = committed == null ? null : [...committed],
       marks = [...marks];

  final List<ClosureMember> members;
  final ClosureRole role;
  final int status;
  final List<String> draft;
  List<String>? committed;
  final List<String> marks;
  final DateTime? earlyCloseAt;
  int fetchCount = 0;
  Object? throwOnWrite;
  final calls = <String, Map<String, Object?>>{};
  final writes = <String>[];

  Iterable<String> get _colleagues =>
      members.map((m) => m.id).where((id) => id != _me);

  Future<void> _write(String name, Map<String, Object?> args) async {
    calls[name] = args;
    writes.add(name);
    final e = throwOnWrite;
    // Rethrows whatever the test asked the "server" to fail with.
    // ignore: only_throw_errors
    if (e != null) throw e;
  }

  String get _inCalc {
    final c = committed;
    if (c == null) return 'notCounted';
    return c.length == draft.length && c.toSet().containsAll(draft)
        ? 'counted'
        : 'differs';
  }

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    fetchCount++;
    final voter = role == ClosureRole.voter;
    return ClosureState(
      epoch: _epoch,
      status: status,
      role: role,
      members: members,
      closesAt: DateTime.utc(2030, 1, 10, 12),
      mySupport: voter ? [...draft] : const [],
      inCalcText: voter ? _inCalc : null,
      myMarks: [...marks],
      earlyCloseAt: voter ? earlyCloseAt : null,
    );
  }

  @override
  Future<String?> toggleSupport({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) async {
    await _write('toggleSupport', {
      'expectedEpoch': expectedEpoch,
      'targetId': targetId,
      'on': on,
    });
    String? released;
    if (on) {
      if (!draft.contains(targetId)) draft.add(targetId);
      if (_colleagues.every(draft.contains)) {
        released = draft.firstWhere((id) => id != targetId);
        draft.remove(released);
      }
    } else {
      draft.remove(targetId);
    }
    return released;
  }

  @override
  Future<void> done({
    required String beaconId,
    required int expectedEpoch,
  }) async {
    await _write('done', {'expectedEpoch': expectedEpoch});
    committed = [...draft];
  }

  @override
  Future<void> skip({
    required String beaconId,
    required int expectedEpoch,
  }) async {
    await _write('skip', {'expectedEpoch': expectedEpoch});
    committed = [];
  }

  @override
  Future<void> setMark({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) async {
    await _write('setMark', {
      'expectedEpoch': expectedEpoch,
      'targetId': targetId,
      'on': on,
    });
    on ? marks.add(targetId) : marks.remove(targetId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClosureMember _member(String id, {String? name}) =>
    ClosureMember(id: id, displayName: name ?? 'Name $id');

/// The viewer plus [colleagues] other members.
List<ClosureMember> _roster(int colleagues) => [
  _member(_me),
  for (var i = 1; i <= colleagues; i++) _member('c$i'),
];

// ---- finders: visible content only, rows matched by vertical position ----

Finder _toggles() => find.byWidgetPredicate(
  (w) => w is Text && (w.data == _off || w.data == _on),
);

Finder _indicators() => find.byWidgetPredicate(
  (w) => w is Text && (w.data == '▲' || w.data == '▼'),
);

Finder _bookmarks() => find.byWidgetPredicate(
  (w) =>
      w is Icon &&
      (_filledBookmarks.contains(w.icon) || _outlineBookmarks.contains(w.icon)),
);

/// The member of [candidates] whose centre is vertically nearest to the row
/// of [id] (the `Text` with the person's display name).
Finder _inRowOf(WidgetTester tester, Finder candidates, String id) {
  final y = tester.getCenter(find.text('Name $id').first).dy;
  var best = 0;
  var bestDistance = double.infinity;
  final n = candidates.evaluate().length;
  for (var i = 0; i < n; i++) {
    final d = (tester.getCenter(candidates.at(i)).dy - y).abs();
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return candidates.at(best);
}

Finder _support(WidgetTester tester, String id) =>
    _inRowOf(tester, _toggles(), id);

Finder _mark(WidgetTester tester, String id) =>
    _inRowOf(tester, _bookmarks(), id);

bool _supported(WidgetTester tester, String id) =>
    tester.widget<Text>(_support(tester, id)).data == _on;

bool _marked(WidgetTester tester, String id) =>
    _filledBookmarks.contains(tester.widget<Icon>(_mark(tester, id)).icon);

String _indicator(WidgetTester tester, String id) =>
    tester.widget<Text>(_inRowOf(tester, _indicators(), id)).data!;

Future<_FakeClosureRepository> _pump(
  WidgetTester tester,
  _FakeClosureRepository fake, {
  Size size = const Size(360, 2400),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = ClosureHelperCubit(
    ClosureCase(fake, env: const Env(), logger: Logger('test')),
    beaconId: _beaconId,
    viewerId: _me,
    author: _author,
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: BlocProvider<ClosureHelperCubit>.value(
          value: cubit,
          child: const ClosureHelperView(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

/// A voter in an evaluating request with [colleagues] colleagues (>= 2 for
/// the voting UI).
Future<_FakeClosureRepository> _pumpVoter(
  WidgetTester tester, {
  int colleagues = 3,
  List<String> draft = const [],
  List<String>? committed,
  List<String> marks = const [],
  int status = _evaluating,
  Size size = const Size(360, 2400),
}) => _pump(
  tester,
  _FakeClosureRepository(
    members: _roster(colleagues),
    status: status,
    draft: draft,
    committed: committed,
    marks: marks,
    earlyCloseAt: DateTime.utc(2030, 1, 5, 12),
  ),
  size: size,
);

Future<void> _tapSupport(WidgetTester tester, String id) async {
  await tester.tap(_support(tester, id));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('closure.helper.info')));
  await tester.pumpAndSettle();
}

List<ButtonStyleButton> _dialogButtons(WidgetTester tester) => tester
    .widgetList<ButtonStyleButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    )
    .toList();

bool _focusMatches(Finder f) {
  final c = FocusManager.instance.primaryFocus?.context;
  if (c == null) return false;
  for (final e in f.evaluate()) {
    if (identical(e, c)) return true;
    var hit = false;
    c.visitAncestorElements((a) {
      if (identical(a, e)) hit = true;
      return !hit;
    });
    if (hit) return true;
    e.visitAncestorElements((a) {
      if (identical(a, c)) hit = true;
      return !hit;
    });
    if (hit) return true;
  }
  return false;
}

void main() {
  group('voter view (>= 3 people)', () {
    testWidgets('header says whose work mattered, not «сверх решения автора»', (
      tester,
    ) async {
      await _pumpVoter(tester);
      expect(find.text(_header), findsOneWidget);
      expect(find.textContaining('сверх решения автора'), findsNothing);
    });

    testWidgets('one «☆ Поддержать» toggle per colleague, no ▲▼ yet', (
      tester,
    ) async {
      await _pumpVoter(tester);
      expect(find.text(_off), findsNWidgets(3));
      expect(find.text(_on), findsNothing);
      expect(find.text('▲'), findsNothing);
      expect(find.text('▼'), findsNothing);
      expect(find.text(_legend), findsNothing);
      expect(find.text(_supportEdge), findsNothing);
      // The viewer is not offered to themselves.
      expect(find.text('Name me'), findsNothing);
      for (final id in ['c1', 'c2', 'c3']) {
        expect(_supported(tester, id), isFalse, reason: id);
      }
    });

    testWidgets('first press: ▲ on supported, ▼ on the rest, legend, U59', (
      tester,
    ) async {
      final fake = await _pumpVoter(tester);
      await _tapSupport(tester, 'c1');
      expect(fake.calls['toggleSupport'], {
        'expectedEpoch': _epoch,
        'targetId': 'c1',
        'on': true,
      });
      expect(find.text(_on), findsOneWidget);
      expect(find.text(_off), findsNWidgets(2));
      expect(_supported(tester, 'c1'), isTrue);
      expect(_supported(tester, 'c2'), isFalse);
      expect(find.text('▲'), findsOneWidget);
      expect(find.text('▼'), findsNWidgets(2));
      expect(_indicator(tester, 'c1'), '▲');
      expect(_indicator(tester, 'c2'), '▼');
      expect(_indicator(tester, 'c3'), '▼');
      expect(find.text(_legend), findsOneWidget);
      expect(find.text(_supportEdge), findsOneWidget);
    });

    testWidgets('pressing a supported colleague again sends on: false', (
      tester,
    ) async {
      final fake = await _pumpVoter(tester, draft: ['c1']);
      expect(find.text(_on), findsOneWidget);
      await _tapSupport(tester, 'c1');
      expect(fake.calls['toggleSupport'], {
        'expectedEpoch': _epoch,
        'targetId': 'c1',
        'on': false,
      });
      expect(find.text(_on), findsNothing);
      expect(find.text(_off), findsNWidgets(3));
    });

    testWidgets('server `released`: full scapegoat hint names the released '
        'colleague', (tester) async {
      await _pumpVoter(tester, draft: ['c1', 'c2']);
      expect(find.textContaining('Кто-то должен отдать'), findsNothing);
      await _tapSupport(tester, 'c3');
      // Whole sentence: «supporting everyone = supporting no one», then who
      // was released.
      expect(find.text(_scapegoat('Name c1')), findsOneWidget);
      // c1 was released, c2 and c3 stay supported.
      expect(find.text(_on), findsNWidgets(2));
      expect(_supported(tester, 'c1'), isFalse);
      expect(_supported(tester, 'c2'), isTrue);
      expect(_supported(tester, 'c3'), isTrue);
    });

    testWidgets('the hint names whoever the server released', (tester) async {
      await _pumpVoter(tester, draft: ['c2', 'c3']);
      await _tapSupport(tester, 'c1');
      expect(find.text(_scapegoat('Name c2')), findsOneWidget);
      expect(find.textContaining('Name c1)'), findsNothing);
      expect(_supported(tester, 'c2'), isFalse);
    });

    testWidgets('no scapegoat hint without a release', (tester) async {
      await _pumpVoter(tester);
      await _tapSupport(tester, 'c1');
      await _tapSupport(tester, 'c2');
      expect(find.textContaining('Кто-то должен отдать'), findsNothing);
      expect(find.textContaining('Поддержать всех'), findsNothing);
    });
  });

  group('status line (U44)', () {
    testWidgets('nothing committed: «В расчёт ещё не входит»', (tester) async {
      await _pumpVoter(tester, draft: ['c1']);
      expect(find.text(_statusNone), findsOneWidget);
      expect(find.textContaining('В расчёте: поддержаны'), findsNothing);
      expect(find.text(_statusDiffers), findsNothing);
    });

    testWidgets('committed equals the screen: «В расчёте: поддержаны …»', (
      tester,
    ) async {
      await _pumpVoter(tester, draft: ['c1', 'c2'], committed: ['c1', 'c2']);
      expect(
        find.text('В расчёте: поддержаны Name c1, Name c2'),
        findsOneWidget,
      );
      expect(find.text(_statusNone), findsNothing);
      expect(find.text(_statusDiffers), findsNothing);
    });

    testWidgets('screen differs from committed: «На экране иначе …»', (
      tester,
    ) async {
      await _pumpVoter(tester, draft: ['c1', 'c2'], committed: ['c1']);
      expect(find.text(_statusDiffers), findsOneWidget);
      expect(find.text(_statusNone), findsNothing);
      expect(find.textContaining('В расчёте: поддержаны'), findsNothing);
    });

    testWidgets('«Готово» commits; a later edit shows «На экране иначе»', (
      tester,
    ) async {
      final fake = await _pumpVoter(tester);
      await _tapSupport(tester, 'c1');
      expect(find.text(_statusNone), findsOneWidget);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(fake.calls['done'], {'expectedEpoch': _epoch});
      expect(find.text('В расчёте: поддержаны Name c1'), findsOneWidget);
      await _tapSupport(tester, 'c2');
      expect(find.text(_statusDiffers), findsOneWidget);
      // The committed version is untouched by the edit.
      expect(fake.committed, ['c1']);
    });
  });

  group('«Готово» / «Пропустить»', () {
    testWidgets('buttons, the «never changes» note, deadline and privacy', (
      tester,
    ) async {
      await _pumpVoter(tester);
      expect(find.text('Готово'), findsOneWidget);
      expect(find.text(_skipLabel), findsOneWidget);
      expect(find.text(_skipNote), findsOneWidget);
      expect(find.text(_privacy), findsOneWidget);
      expect(
        find.textContaining(
          RegExp(
            r'Автор может закрыть после .*\d+ янв.* — или раньше, когда '
            'ответят все',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('skip without a committed version acts at once', (
      tester,
    ) async {
      final fake = await _pumpVoter(tester, draft: ['c1']);
      await tester.tap(find.text(_skipLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.calls['skip'], {'expectedEpoch': _epoch});
    });

    testWidgets('skip with a committed version asks first; cancel keeps it', (
      tester,
    ) async {
      final fake = await _pumpVoter(
        tester,
        draft: ['c1'],
        committed: ['c1'],
      );
      await tester.tap(find.text(_skipLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_skipConfirm), findsOneWidget);
      expect(fake.calls['skip'], isNull);

      final buttons = _dialogButtons(tester);
      expect(buttons, hasLength(2));
      await tester.tap(find.byWidget(buttons.first));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.calls['skip'], isNull);
    });

    testWidgets('skip with a committed version: confirm sends skip', (
      tester,
    ) async {
      final fake = await _pumpVoter(
        tester,
        draft: ['c1'],
        committed: ['c1'],
      );
      await tester.tap(find.text(_skipLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidget(_dialogButtons(tester).last));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.calls['skip'], {'expectedEpoch': _epoch});
    });

    testWidgets('a differing screen also counts as a committed version', (
      tester,
    ) async {
      await _pumpVoter(tester, draft: ['c1', 'c2'], committed: ['c1']);
      await tester.tap(find.text(_skipLabel));
      await tester.pumpAndSettle();
      expect(find.text(_skipConfirm), findsOneWidget);
    });
  });

  group('bookmarks and the U58 author-edge notice', () {
    testWidgets('voter: bookmark per colleague and the author, with copy', (
      tester,
    ) async {
      final fake = await _pumpVoter(tester, marks: ['c2']);
      // Three colleagues and the author; never the viewer.
      expect(_bookmarks(), findsNWidgets(4));
      expect(find.textContaining(_bookmarkCopy), findsWidgets);
      expect(_marked(tester, 'c2'), isTrue);
      expect(_marked(tester, 'c1'), isFalse);
      expect(_marked(tester, 'auth'), isFalse);

      await tester.tap(_mark(tester, 'auth'));
      await tester.pumpAndSettle();
      expect(fake.calls['setMark'], {
        'expectedEpoch': _epoch,
        'targetId': 'auth',
        'on': true,
      });
      expect(_marked(tester, 'auth'), isTrue);
      await tester.tap(_mark(tester, 'c2'));
      await tester.pumpAndSettle();
      expect(fake.calls['setMark'], {
        'expectedEpoch': _epoch,
        'targetId': 'c2',
        'on': false,
      });
      expect(_marked(tester, 'c2'), isFalse);
    });

    group('U58 notice while the epoch is evaluating', () {
      testWidgets('voter', (tester) async {
        await _pumpVoter(tester, status: _evaluating);
        expect(find.text(_authorEdge), findsOneWidget);
      });

      testWidgets('1-member request: only the author bookmark', (
        tester,
      ) async {
        await _pump(
          tester,
          _FakeClosureRepository(members: _roster(0), status: _evaluating),
        );
        expect(find.text(_authorEdge), findsOneWidget);
        expect(_bookmarks(), findsOneWidget);
        expect(_marked(tester, 'auth'), isFalse);
      });

      testWidgets('2-member request: bookmarks for colleague and author', (
        tester,
      ) async {
        final fake = await _pump(
          tester,
          _FakeClosureRepository(
            members: _roster(1),
            status: _evaluating,
            earlyCloseAt: DateTime.utc(2030, 1, 5, 12),
          ),
        );
        expect(find.text(_authorEdge), findsOneWidget);
        expect(_bookmarks(), findsNWidgets(2));
        expect(find.textContaining(RegExp(r'\d+ янв')), findsWidgets);
        expect(find.textContaining(_bookmarkCopy), findsWidgets);

        await tester.tap(_mark(tester, 'c1'));
        await tester.pumpAndSettle();
        expect(fake.calls['setMark'], {
          'expectedEpoch': _epoch,
          'targetId': 'c1',
          'on': true,
        });
      });

      testWidgets('non-voter (left or removed): bookmarks and deadline only', (
        tester,
      ) async {
        final fake = await _pump(
          tester,
          _FakeClosureRepository(
            members: _roster(4),
            role: ClosureRole.member,
            status: _evaluating,
          ),
        );
        expect(find.text(_authorEdge), findsOneWidget);
        expect(_bookmarks(), findsNWidgets(5));
        expect(find.textContaining(_bookmarkCopy), findsWidgets);
        // Deadline only (no early-close time for a non-voter).
        expect(find.textContaining(RegExp('10 янв')), findsWidgets);
        expect(find.textContaining('Автор может закрыть после'), findsNothing);
        // No voting UI at all.
        expect(find.text(_header), findsNothing);
        expect(find.text(_off), findsNothing);
        expect(find.text(_on), findsNothing);
        expect(find.text('Готово'), findsNothing);
        expect(find.text(_skipLabel), findsNothing);
        expect(find.text(_skipNote), findsNothing);
        expect(find.text(_privacy), findsNothing);
        expect(find.text(_legend), findsNothing);
        expect(find.text('▲'), findsNothing);
        expect(find.text('▼'), findsNothing);

        await tester.tap(_mark(tester, 'auth'));
        await tester.pumpAndSettle();
        expect(fake.calls['setMark'], {
          'expectedEpoch': _epoch,
          'targetId': 'auth',
          'on': true,
        });
      });
    });

    group('U58 notice is not shown once the epoch is finalized', () {
      testWidgets('voter', (tester) async {
        await _pumpVoter(tester, status: _finalized);
        expect(find.text(_authorEdge), findsNothing);
      });

      testWidgets('1-member request', (tester) async {
        await _pump(
          tester,
          _FakeClosureRepository(members: _roster(0), status: _finalized),
        );
        expect(find.text(_authorEdge), findsNothing);
      });

      testWidgets('non-voter', (tester) async {
        await _pump(
          tester,
          _FakeClosureRepository(
            members: _roster(4),
            role: ClosureRole.member,
            status: _finalized,
          ),
        );
        expect(find.text(_authorEdge), findsNothing);
      });
    });
  });

  group('(i) sheet', () {
    testWidgets('shows the diagram, the scaling text and the U59 line', (
      tester,
    ) async {
      await _pumpVoter(tester);
      // Not on the main screen: the scaling text, and (before any press) the
      // U59 line live only in the sheet.
      expect(find.text(_scaling), findsNothing);
      expect(find.text(_supportEdge), findsNothing);
      expect(find.byType(ShareFlowDiagram), findsNothing);

      await _openSheet(tester);
      expect(find.byType(ShareFlowDiagram), findsOneWidget);
      expect(find.text(_scaling), findsOneWidget);
      expect(find.text(_supportEdge), findsOneWidget);
      expect(find.text('пример'), findsWidgets);
      // Author + every member of the roster get an avatar.
      expect(
        find.descendant(
          of: find.byType(ShareFlowDiagram),
          matching: find.byType(TenturaAvatar),
        ),
        findsNWidgets(_roster(3).length + 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the diagram gets only the roster size and the avatars', (
      tester,
    ) async {
      await _pumpVoter(tester);
      await _openSheet(tester);
      final d = tester.widget<ShareFlowDiagram>(find.byType(ShareFlowDiagram));
      expect(d.memberCount, _roster(3).length);
      expect(
        d.avatars.map((p) => p.id),
        unorderedEquals([..._roster(3).map((m) => m.id), _author.id]),
      );
    });

    testWidgets('U59 line also sits under the ▲▼ legend on the screen', (
      tester,
    ) async {
      await _pumpVoter(tester);
      await _tapSupport(tester, 'c2');
      expect(find.text(_legend), findsOneWidget);
      expect(find.text(_supportEdge), findsOneWidget);
      final legendY = tester.getTopLeft(find.text(_legend)).dy;
      final edgeY = tester.getTopLeft(find.text(_supportEdge)).dy;
      expect(edgeY, greaterThan(legendY));
    });
  });

  group('desktop: hover, mouse, keyboard, no long-press', () {
    testWidgets('toggle is a hover-aware Material control with no long-press', (
      tester,
    ) async {
      await _pumpVoter(tester);
      final control = find.ancestor(
        of: find.text(_off).first,
        matching: find.byWidgetPredicate(
          (w) => w is InkResponse || w is ButtonStyleButton,
        ),
      );
      expect(control, findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              (w is GestureDetector && w.onLongPress != null) ||
              (w is InkResponse && w.onLongPress != null),
        ),
        findsNothing,
      );
    });

    testWidgets('mouse click toggles support', (tester) async {
      final fake = await _pumpVoter(tester);
      final target = tester.getCenter(_support(tester, 'c2'));
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      await g.moveTo(target);
      await tester.pump();
      await g.down(target);
      await g.up();
      await tester.pumpAndSettle();
      await g.removePointer();
      expect(fake.calls['toggleSupport'], {
        'expectedEpoch': _epoch,
        'targetId': 'c2',
        'on': true,
      });
    });

    testWidgets('keyboard: Tab reaches the toggle, Enter activates it', (
      tester,
    ) async {
      final fake = await _pumpVoter(tester);
      var guard = 0;
      while (!_focusMatches(_support(tester, 'c1')) && guard++ < 14) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(_focusMatches(_support(tester, 'c1')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fake.calls['toggleSupport'], {
        'expectedEpoch': _epoch,
        'targetId': 'c1',
        'on': true,
      });
    });
  });

  group('staleEpoch on every write reloads and shows a snackbar', () {
    final cases = <String, Future<void> Function(WidgetTester)>{
      'support': (t) => t.tap(_support(t, 'c1')),
      'done': (t) => t.tap(find.text('Готово')),
      'skip': (t) => t.tap(find.text(_skipLabel)),
      'mark': (t) => t.tap(_mark(t, 'c1')),
    };
    for (final e in cases.entries) {
      testWidgets(e.key, (tester) async {
        final fake = await _pumpVoter(tester);
        expect(fake.fetchCount, 1);
        fake.throwOnWrite = const ClosureStaleEpochException();
        await e.value(tester);
        await tester.pumpAndSettle();
        expect(fake.writes, isNotEmpty);
        expect(fake.fetchCount, 2);
        expect(find.byType(SnackBar), findsOneWidget);
      });
    }
  });

  testWidgets('12 members at 360x800: scrolling shows no layout exception', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeClosureRepository(
        members: [
          _member(_me),
          for (var i = 1; i < 12; i++)
            _member('c$i', name: 'Very long display name number $i of twelve'),
        ],
        earlyCloseAt: DateTime.utc(2030, 1, 5, 12),
      ),
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Very long display name number 11 of twelve'),
      300,
      scrollable: scrollable,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text(_skipLabel),
      300,
      scrollable: scrollable,
    );
    expect(tester.takeException(), isNull);
  });
}
