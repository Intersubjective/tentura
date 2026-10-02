// A20: author screen «Подвести итоги». Pumps `ClosureAuthorView` (body of the
// screen, no AutoRouter) under a real `ClosureAuthorCubit` over a real
// `ClosureCase` on a fake `ClosureRepository`. Contract the implementation must
// follow:
//  - cubit: `ClosureAuthorCubit(ClosureCase, {required String beaconId})`,
//    loads `fetchState` on creation, every write passes `expectedEpoch`;
//    `ClosureStaleEpochException` => `fetchState` again + a SnackBar.
//  - `ClosureState.extensionsUsed` (int, default 0; server `extensions_used`).
//  - Controls are found by visible text and semantics labels: each outcome
//    option and the bookmark toggle expose a label with the member's name
//    (bookmark label contains «закладк»); sliders appear in row order.
//  - Only these ValueKeys are pinned (no visible text exists for them):
//    `closure.author.preview.<id>` (the bar itself; its width is proportional
//    to the member's silent share), `closure.author.split.save`,
//    `closure.author.story.save`.
//  - strings are Russian (locale `ru`), keys `closureAuthor*` in both ARBs.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/silent_preview.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/bloc/closure_author_cubit.dart';
import 'package:tentura/features/closure/ui/screen/closure_author_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _beaconId = 'Bclosure00001';
const _epoch = 4;

final class _FakeClosureRepository implements ClosureRepository {
  _FakeClosureRepository(this.state);

  ClosureState state;
  int fetchCount = 0;
  Object? throwOnWrite;
  final calls = <String, Map<String, Object?>>{};

  Future<void> _write(String name, Map<String, Object?> args) async {
    calls[name] = args;
    final e = throwOnWrite;
    // ignore: only_throw_errors
    if (e != null) throw e;
  }

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    fetchCount++;
    return state;
  }

  @override
  Future<void> saveOutcome({
    required String beaconId,
    required int expectedEpoch,
    required String helperId,
    required ClosureOutcome? outcome,
  }) => _write('saveOutcome', {
    'expectedEpoch': expectedEpoch,
    'helperId': helperId,
    'outcome': outcome,
  });

  @override
  Future<void> saveAuthorSplit({
    required String beaconId,
    required int expectedEpoch,
    required Map<String, int>? split,
  }) => _write('saveAuthorSplit', {
    'expectedEpoch': expectedEpoch,
    'split': split,
  });

  @override
  Future<void> setMark({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) => _write('setMark', {
    'expectedEpoch': expectedEpoch,
    'targetId': targetId,
    'on': on,
  });

  @override
  Future<void> saveStory({
    required String beaconId,
    required int expectedEpoch,
    required String body,
  }) => _write('saveStory', {'expectedEpoch': expectedEpoch, 'body': body});

  @override
  Future<void> closeNow({
    required String beaconId,
    required int expectedEpoch,
  }) => _write('closeNow', {'expectedEpoch': expectedEpoch});

  @override
  Future<void> extendClosure({
    required String beaconId,
    required int expectedEpoch,
  }) => _write('extendClosure', {'expectedEpoch': expectedEpoch});

  @override
  Future<void> reopen({
    required String beaconId,
    required int expectedEpoch,
  }) => _write('reopen', {'expectedEpoch': expectedEpoch});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClosureMember _member(String id, {String? name, String? departure}) =>
    ClosureMember(
      id: id,
      displayName: name ?? 'Name $id',
      departure: departure,
    );

ClosureState _state({
  List<ClosureMember>? members,
  Map<String, ClosureOutcome>? outcomes,
  Map<String, int>? split,
  List<String> myMarks = const [],
  String? story,
  bool canCloseNow = false,
  bool canReopen = false,
  DateTime? earlyCloseAt,
  int extensionsUsed = 0,
}) => ClosureState(
  epoch: _epoch,
  status: 1,
  role: ClosureRole.author,
  members:
      members ?? [_member('u1'), _member('u2'), _member('u3'), _member('u4')],
  closesAt: DateTime.utc(2030, 1, 10, 12),
  outcomes: outcomes ?? const {},
  split: split,
  myMarks: myMarks,
  story: story,
  canCloseNow: canCloseNow,
  canReopen: canReopen,
  earlyCloseAt: earlyCloseAt,
  extensionsUsed: extensionsUsed,
);

Key _k(String s) => ValueKey<String>(s);

Finder _outcome(String id, String label) =>
    find.bySemanticsLabel(RegExp('Name $id\\b.*$label')).first;

Finder _mark(String id) =>
    find.bySemanticsLabel(RegExp('Name $id\\b.*закладк')).first;

Finder _name(String id) => find.text('Name $id');

Future<_FakeClosureRepository> _pump(
  WidgetTester tester,
  ClosureState state, {
  Size size = const Size(360, 2400),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = _FakeClosureRepository(state);
  final cubit = ClosureAuthorCubit(
    ClosureCase(fake, env: const Env(), logger: Logger('test')),
    beaconId: _beaconId,
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: BlocProvider<ClosureAuthorCubit>.value(
          value: cubit,
          child: const ClosureAuthorView(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

final _standalone20 = RegExp(r'(?<!\d)20(?!\d)');

final _allDone = {
  for (final id in ['u1', 'u2', 'u3']) id: ClosureOutcome.done,
};

double _barWidth(WidgetTester tester, String id) {
  final f = find.byKey(_k('closure.author.preview.$id'));
  return f.evaluate().isEmpty ? 0 : tester.getSize(f).width;
}

/// Fixed silent shares (server vectors) -> bar widths proportional to them.
void _expectRatios(WidgetTester tester, List<double> shares) {
  final w = [
    for (var i = 1; i <= shares.length; i++) _barWidth(tester, 'u$i'),
  ];
  expect(w[0], greaterThan(0));
  for (var i = 1; i < shares.length; i++) {
    expect(
      w[i] / w[0],
      closeTo(shares[i] / shares[0], 0.02),
      reason: 'u${i + 1}',
    );
  }
}

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

/// Tabs through [groups]; any order inside a group, strict between groups.
Future<void> _expectFocusGroups(
  WidgetTester tester,
  List<List<Finder>> groups,
) async {
  var guard = 0;
  while (!groups.first.any(_focusMatches) && guard++ < 12) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  var firstStop = true;
  for (var g = 0; g < groups.length; g++) {
    final remaining = [...groups[g]];
    while (remaining.isNotEmpty) {
      if (!firstStop) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      firstStop = false;
      final hit = remaining.indexWhere(_focusMatches);
      expect(hit, isNonNegative, reason: 'group $g: focus not in $remaining');
      remaining.removeAt(hit);
    }
  }
}

void main() {
  testWidgets('outcome picker: labels, hints, and expectedEpoch on write', (
    tester,
  ) async {
    final fake = await _pump(tester, _state());
    expect(find.text('Выполнено'), findsWidgets);
    expect(find.text('Не выполнено'), findsWidgets);
    expect(find.text('Не могу судить'), findsWidgets);
    expect(
      find.textContaining('убирает человека из твоего распределения'),
      findsOneWidget,
    );
    expect(find.textContaining('оставляет его в равной доле'), findsOneWidget);

    await tester.tap(_outcome('u1', 'Не выполнено'));
    await tester.pumpAndSettle();
    expect(fake.calls['saveOutcome'], {
      'expectedEpoch': _epoch,
      'helperId': 'u1',
      'outcome': ClosureOutcome.notDone,
    });
  });

  testWidgets('outcome picker is a vertical list at 360 px', (tester) async {
    await _pump(tester, _state());
    final done = tester.getTopLeft(_outcome('u1', 'Выполнено'));
    final notDone = tester.getTopLeft(_outcome('u1', 'Не выполнено'));
    final cant = tester.getTopLeft(_outcome('u1', 'Не могу судить'));
    expect(notDone.dy, greaterThan(done.dy));
    expect(cant.dy, greaterThan(notDone.dy));
    expect(notDone.dx, done.dx);
    expect(cant.dx, done.dx);
  });

  testWidgets('outcome toggles carry semantics label and selected state', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        members: [_member('u1'), _member('u2')],
        outcomes: {'u1': ClosureOutcome.done},
      ),
    );
    final done = tester.getSemantics(_outcome('u1', 'Выполнено'));
    final notDone = tester.getSemantics(_outcome('u1', 'Не выполнено'));
    expect(done.label, contains('Name u1'));
    expect(done.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(notDone.hasFlag(SemanticsFlag.isSelected), isFalse);
  });

  testWidgets('«Вернуть поровну» sends split: null', (tester) async {
    final fake = await _pump(
      tester,
      _state(split: {'u1': 40, 'u2': 30, 'u3': 20, 'u4': 10}),
    );
    await tester.tap(find.text('Вернуть поровну'));
    await tester.pumpAndSettle();
    expect(fake.calls['saveAuthorSplit'], {
      'expectedEpoch': _epoch,
      'split': null,
    });
  });

  testWidgets('two members: explanatory text', (tester) async {
    await _pump(tester, _state(members: [_member('u1'), _member('u2')]));
    expect(
      find.text(
        'Долю каждого распределяешь ты. Каждый из двоих поймёт по своему '
        'итогу, как ты разделил',
      ),
      findsOneWidget,
    );
  });

  testWidgets('story field has a hint when empty', (tester) async {
    await _pump(tester, _state());
    final field = tester.widget<TextField>(find.byType(TextField));
    final hint = field.decoration?.hintText ?? field.decoration?.helperText;
    expect(hint, isNotNull);
    expect(hint, isNotEmpty);
  });

  testWidgets('story field shows saved text and saves with expectedEpoch', (
    tester,
  ) async {
    final fake = await _pump(tester, _state(story: 'Old story'));
    expect(find.text('Old story'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'New story');
    await tester.tap(find.byKey(_k('closure.author.story.save')));
    await tester.pumpAndSettle();
    expect(fake.calls['saveStory'], {
      'expectedEpoch': _epoch,
      'body': 'New story',
    });
  });

  testWidgets('bookmark toggle per member sends setMark on/off', (
    tester,
  ) async {
    final fake = await _pump(tester, _state(myMarks: ['u2']));
    await tester.tap(_mark('u1'));
    await tester.pumpAndSettle();
    expect(fake.calls['setMark'], {
      'expectedEpoch': _epoch,
      'targetId': 'u1',
      'on': true,
    });
    await tester.tap(_mark('u2'));
    await tester.pumpAndSettle();
    expect(fake.calls['setMark'], {
      'expectedEpoch': _epoch,
      'targetId': 'u2',
      'on': false,
    });
  });

  testWidgets('bookmark toggle semantics: label, toggled state', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(members: [_member('u1'), _member('u2')], myMarks: ['u2']),
    );
    final off = tester.getSemantics(_mark('u1'));
    final on = tester.getSemantics(_mark('u2'));
    expect(off.hasFlag(SemanticsFlag.hasToggledState), isTrue);
    expect(off.hasFlag(SemanticsFlag.isToggled), isFalse);
    expect(on.hasFlag(SemanticsFlag.isToggled), isTrue);
  });

  testWidgets('footer: deadline shown, extend, close now disabled', (
    tester,
  ) async {
    final fake = await _pump(tester, _state());
    expect(
      find.textContaining(RegExp(r'10 янв|10\.01|янв\w* 10')),
      findsWidgets,
    );
    expect(_button(tester, 'Завершить сейчас').onPressed, isNull);
    expect(find.text('Вернуть в работу'), findsNothing);
    await tester.tap(find.text('Продлить на 7 дней'));
    await tester.pumpAndSettle();
    expect(fake.calls['extendClosure'], {'expectedEpoch': _epoch});
  });

  testWidgets('«Продлить на 7 дней» stays after one extension', (
    tester,
  ) async {
    await _pump(tester, _state(extensionsUsed: 1));
    expect(find.text('Продлить на 7 дней'), findsOneWidget);
  });

  testWidgets('«Продлить на 7 дней» is hidden after two extensions', (
    tester,
  ) async {
    await _pump(tester, _state(extensionsUsed: 2));
    expect(find.text('Продлить на 7 дней'), findsNothing);
    expect(find.text('Завершить сейчас'), findsOneWidget);
  });

  testWidgets('footer: «Завершить сейчас» enabled by canCloseNow + hint', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      _state(canCloseNow: true, earlyCloseAt: DateTime.utc(2030, 1, 5, 9)),
    );
    expect(find.textContaining('Можно закрыть раньше после'), findsOneWidget);
    expect(
      find.textContaining('или когда все помощники ответят'),
      findsOneWidget,
    );
    await tester.tap(find.text('Завершить сейчас'));
    await tester.pumpAndSettle();
    expect(fake.calls['closeNow'], {'expectedEpoch': _epoch});
  });

  testWidgets('never shows who has answered', (tester) async {
    await _pump(
      tester,
      _state(
        canCloseNow: true,
        earlyCloseAt: DateTime.utc(2030, 1, 5, 9),
        outcomes: {'u1': ClosureOutcome.done},
      ),
    );
    expect(
      find.textContaining(
        RegExp(
          'ответил|проголосовал|answered|replied|voted',
          caseSensitive: false,
        ),
      ),
      findsNothing,
    );
    expect(find.textContaining(RegExp(r'\d+ из \d+|\d+ of \d+')), findsNothing);
  });

  testWidgets('«Вернуть в работу» appears with canReopen', (tester) async {
    final fake = await _pump(tester, _state(canReopen: true));
    await tester.tap(find.text('Вернуть в работу'));
    await tester.pumpAndSettle();
    expect(fake.calls['reopen'], {'expectedEpoch': _epoch});
  });

  testWidgets('members: actives first, leavers in order with their own label', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        members: [
          _member('u1', departure: 'voluntary'),
          _member('u2', departure: 'removed'),
          _member('u3'),
          _member('u4'),
          _member('u5', departure: 'voluntary'),
        ],
      ),
      size: const Size(360, 2400),
    );
    double top(String id) => tester.getTopLeft(_name(id).first).dy;
    expect(top('u3'), lessThan(top('u4')));
    expect(top('u4'), lessThan(top('u1')));
    expect(top('u1'), lessThan(top('u2')));
    expect(top('u2'), lessThan(top('u5')));
    expect(find.text('ушёл'), findsNWidgets(2));
    expect(find.text('исключён'), findsOneWidget);
    double labelY(Finder f, int i) => tester.getCenter(f.at(i)).dy;
    // «ушёл» belongs to u1 and u5, «исключён» to u2.
    expect(
      labelY(find.text('ушёл'), 0),
      inInclusiveRange(top('u1'), top('u2')),
    );
    expect(
      labelY(find.text('исключён'), 0),
      inInclusiveRange(top('u2'), top('u5')),
    );
    expect(labelY(find.text('ушёл'), 1), greaterThanOrEqualTo(top('u5')));
  });

  testWidgets('split is locked until «Изменить распределение»', (tester) async {
    final fake = await _pump(tester, _state());
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text('Изменить распределение'));
    await tester.pumpAndSettle();
    expect(fake.calls.containsKey('saveAuthorSplit'), isFalse);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(4));
    for (final s in sliders) {
      expect(s.value, 25, reason: 'equal values as the starting point');
      expect(s.min, 5);
      expect((s.max - s.min) / s.divisions!, 5);
    }
    await tester.tap(find.byKey(_k('closure.author.split.save')));
    await tester.pumpAndSettle();
    expect(fake.calls['saveAuthorSplit'], {
      'expectedEpoch': _epoch,
      'split': {'u1': 25, 'u2': 25, 'u3': 25, 'u4': 25},
    });
  });

  testWidgets('sliders cover only set A: notDone members get none', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      _state(
        members: [for (var i = 1; i <= 5; i++) _member('u$i')],
        outcomes: {'u5': ClosureOutcome.notDone},
      ),
      size: const Size(360, 2400),
    );
    await tester.tap(find.text('Изменить распределение'));
    await tester.pumpAndSettle();
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(4));
    expect(sliders.map((s) => s.value), everyElement(25));
    await tester.tap(find.byKey(_k('closure.author.split.save')));
    await tester.pumpAndSettle();
    expect(fake.calls['saveAuthorSplit'], {
      'expectedEpoch': _epoch,
      'split': {'u1': 25, 'u2': 25, 'u3': 25, 'u4': 25},
    });
  });

  testWidgets('sliders enforce min 5, steps of 5 and a 100 total', (
    tester,
  ) async {
    final fake = await _pump(tester, _state());
    await tester.tap(find.text('Изменить распределение'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider).first).value, 5);
    await tester.drag(find.byType(Slider).first, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Slider>(find.byType(Slider).first).value,
      lessThanOrEqualTo(85),
      reason: 'the other three keep at least 5 each',
    );
    await tester.drag(find.byType(Slider).at(1), const Offset(30, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_k('closure.author.split.save')));
    await tester.pumpAndSettle();
    final split = fake.calls['saveAuthorSplit']!['split']! as Map<String, int>;
    expect(split.values.fold<int>(0, (a, b) => a + b), 100);
    expect(split.values.every((v) => v % 5 == 0 && v >= 5), isTrue);
  });

  testWidgets('|A| > 20 disables the split and explains why', (tester) async {
    await _pump(
      tester,
      _state(
        members: [
          for (var i = 0; i < 21; i++)
            _member('m$i', name: 'Helper ${i + 101}'),
        ],
      ),
      size: const Size(360, 4000),
    );
    expect(_button(tester, 'Изменить распределение').onPressed, isNull);
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining(_standalone20), findsOneWidget);
  });

  testWidgets('22 members with |A| = 21 is still disabled', (tester) async {
    await _pump(
      tester,
      _state(
        members: [
          for (var i = 0; i < 22; i++)
            _member('m$i', name: 'Helper ${i + 101}'),
        ],
        outcomes: {'m0': ClosureOutcome.notDone},
      ),
      size: const Size(360, 4000),
    );
    expect(_button(tester, 'Изменить распределение').onPressed, isNull);
  });

  testWidgets('22 members with |A| = 20 keeps the split available', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        members: [
          for (var i = 0; i < 22; i++)
            _member('m$i', name: 'Helper ${i + 101}'),
        ],
        outcomes: {
          'm0': ClosureOutcome.notDone,
          'm1': ClosureOutcome.notDone,
        },
      ),
      size: const Size(360, 4000),
    );
    expect(_button(tester, 'Изменить распределение').onPressed, isNotNull);
    expect(find.textContaining(_standalone20), findsNothing);
  });

  testWidgets('live preview bars match server vector V2 (70/20/10)', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        members: [_member('u1'), _member('u2'), _member('u3')],
        outcomes: _allDone,
        split: {'u1': 70, 'u2': 20, 'u3': 10},
      ),
    );
    expect(find.text('если коллеги промолчат'), findsOneWidget);
    expect(_name('u1'), findsWidgets);
    _expectRatios(tester, [0.3856, 0.2074, 0.1069]);
  });

  testWidgets('live preview bars match server vector V1 (equal)', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        members: [_member('u1'), _member('u2'), _member('u3')],
        outcomes: _allDone,
      ),
    );
    _expectRatios(tester, [0.2333, 0.2333, 0.2333]);
  });

  testWidgets('live preview follows a changed outcome (V8)', (tester) async {
    final fake = await _pump(
      tester,
      _state(
        members: [_member('u1'), _member('u2'), _member('u3')],
        outcomes: _allDone,
      ),
    );
    fake.state = _state(
      members: [_member('u1'), _member('u2'), _member('u3')],
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.notDone,
        'u3': ClosureOutcome.notDone,
      },
    );
    await tester.tap(_outcome('u2', 'Не выполнено'));
    await tester.pumpAndSettle();
    expect(_barWidth(tester, 'u1'), greaterThan(0));
    expect(_barWidth(tester, 'u2'), 0);
    expect(_barWidth(tester, 'u3'), 0);
  });

  testWidgets('live preview follows a changed split (V1 -> V2)', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      _state(
        members: [_member('u1'), _member('u2'), _member('u3')],
        outcomes: _allDone,
      ),
    );
    fake.state = _state(
      members: [_member('u1'), _member('u2'), _member('u3')],
      outcomes: _allDone,
      split: {'u1': 70, 'u2': 20, 'u3': 10},
    );
    await tester.tap(_outcome('u1', 'Выполнено'));
    await tester.pumpAndSettle();
    _expectRatios(tester, [0.3856, 0.2074, 0.1069]);
  });

  group('staleEpoch on every write reloads and shows a snackbar', () {
    final cases =
        <
          String,
          ({ClosureState state, Future<void> Function(WidgetTester) act})
        >{
          'outcome': (
            state: _state(),
            act: (t) => t.tap(_outcome('u1', 'Выполнено')),
          ),
          'mark': (state: _state(), act: (t) => t.tap(_mark('u1'))),
          'reset split': (
            state: _state(split: {'u1': 40, 'u2': 30, 'u3': 20, 'u4': 10}),
            act: (t) => t.tap(find.text('Вернуть поровну')),
          ),
          'extend': (
            state: _state(),
            act: (t) => t.tap(find.text('Продлить на 7 дней')),
          ),
          'close now': (
            state: _state(canCloseNow: true),
            act: (t) => t.tap(find.text('Завершить сейчас')),
          ),
          'reopen': (
            state: _state(canReopen: true),
            act: (t) => t.tap(find.text('Вернуть в работу')),
          ),
          'story': (
            state: _state(),
            act: (t) async {
              await t.enterText(find.byType(TextField), 'x');
              await t.tap(find.byKey(_k('closure.author.story.save')));
            },
          ),
          'split save': (
            state: _state(),
            act: (t) async {
              await t.tap(find.text('Изменить распределение'));
              await t.pumpAndSettle();
              await t.tap(find.byKey(_k('closure.author.split.save')));
            },
          ),
        };
    for (final e in cases.entries) {
      testWidgets(e.key, (tester) async {
        final fake = await _pump(
          tester,
          e.value.state,
          size: const Size(360, 2400),
        );
        expect(fake.fetchCount, 1);
        fake.throwOnWrite = const ClosureStaleEpochException();
        await e.value.act(tester);
        await tester.pumpAndSettle();
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
      _state(
        members: [
          for (var i = 0; i < 12; i++)
            _member('u$i', name: 'Very long display name number $i of twelve'),
        ],
        canCloseNow: true,
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
      find.text('Завершить сейчас'),
      300,
      scrollable: scrollable,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus order, locked split: rows, split, story, footer', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        members: [_member('u1'), _member('u2')],
        split: {'u1': 60, 'u2': 40},
        story: 'story',
        canCloseNow: true,
        canReopen: true,
      ),
      size: const Size(360, 2400),
    );
    await _expectFocusGroups(tester, [
      [
        _outcome('u1', 'Выполнено'),
        _outcome('u1', 'Не выполнено'),
        _outcome('u1', 'Не могу судить'),
        _mark('u1'),
      ],
      [
        _outcome('u2', 'Выполнено'),
        _outcome('u2', 'Не выполнено'),
        _outcome('u2', 'Не могу судить'),
        _mark('u2'),
      ],
      [find.text('Изменить распределение'), find.text('Вернуть поровну')],
      [find.byType(TextField), find.byKey(_k('closure.author.story.save'))],
      [
        find.text('Продлить на 7 дней'),
        find.text('Завершить сейчас'),
        find.text('Вернуть в работу'),
      ],
    ]);
  });

  testWidgets('focus order, unlocked split: sliders and save before story', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        members: [_member('u1'), _member('u2')],
        story: 'story',
        canCloseNow: true,
      ),
      size: const Size(360, 2400),
    );
    await tester.tap(find.text('Изменить распределение'));
    await tester.pumpAndSettle();
    await _expectFocusGroups(tester, [
      [
        _outcome('u1', 'Выполнено'),
        _outcome('u1', 'Не выполнено'),
        _outcome('u1', 'Не могу судить'),
        _mark('u1'),
      ],
      [
        _outcome('u2', 'Выполнено'),
        _outcome('u2', 'Не выполнено'),
        _outcome('u2', 'Не могу судить'),
        _mark('u2'),
      ],
      [find.byType(Slider).at(0)],
      [find.byType(Slider).at(1)],
      [find.byKey(_k('closure.author.split.save'))],
      [find.byType(TextField), find.byKey(_k('closure.author.story.save'))],
      [find.text('Продлить на 7 дней'), find.text('Завершить сейчас')],
    ]);
  });
}
