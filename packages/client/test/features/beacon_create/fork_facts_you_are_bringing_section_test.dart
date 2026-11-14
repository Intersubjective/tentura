// «Facts you're bringing» on the draft create screen (fact continuity plan
// D12, D13, §6.5). Before the lazy fork has run the section renders the facts
// ticked on the fork sheet (read from the source Request's fact list) and ✕
// edits that local selection; once the draft exists, and for any draft that
// received facts by push, it renders the draft's own fact list and ✕ calls
// the existing fact-card remove. If fewer facts arrived than were ticked the
// screen says so once.
//
// The screen is driven the way a person uses it: the real BeaconCreateScreen
// over a real BeaconCreateCubit and BeaconCreateCase; the fact list query is
// reached through GetIt (registerFactRepository), as other sheets reach it.
// The real-path test runs HTTP -> Ferry -> BeaconFactCardRepository instead
// of an in-memory repository.
//
// The ✕ of a fact row is found as the close icon on the same line as the
// fact's text, so the tests do not depend on the row's widget type.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fact_origin_test_support.dart'
    show hasCyrillic, pumpRealAsync, registerFactRepository;
import '../beacon_threads/room_cubit_fakes.dart'
    show FakeBeaconFactCardRepository;
import 'fake_beacon_ports.dart';
import 'fork_beacon_ports.dart';

const _sourceId = 'Bsource00001';
const _forkedId = 'fork-1';
const _draftId = 'Bdraft000001';

BeaconFactCard _fact(String id, String text, String beaconId) => BeaconFactCard(
  id: id,
  beaconId: beaconId,
  factText: text,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Upinner000001',
  createdAt: DateTime.utc(2026, 10),
  status: BeaconFactCardStatusBits.active,
);

/// In-memory fact list query and remove mutation, by beacon id.
class _Facts extends FakeBeaconFactCardRepository {
  final byBeacon = <String, List<BeaconFactCard>>{};
  final listCalls = <String>[];
  final removeCalls = <({String beaconId, String factCardId})>[];

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    listCalls.add(beaconId);
    return [...?byBeacon[beaconId]];
  }

  @override
  Future<void> remove({
    required String beaconId,
    required String factCardId,
  }) async {
    removeCalls.add((beaconId: beaconId, factCardId: factCardId));
    byBeacon[beaconId]?.removeWhere((f) => f.id == factCardId);
  }
}

/// A lineage fork that also remembers the fact ids it was asked to bring.
class _RecordingForkPort extends ForkingBeaconWritePort {
  _RecordingForkPort({required super.source});

  final forkFactIds = <List<String>>[];

  @override
  Future<Beacon> fork(
    String sourceId, {
    bool copyPlan = false,
    List<PlanStepTime> planStepTimes = const [],
    List<String> factIds = const [],
  }) {
    forkFactIds.add(List.of(factIds));
    return super.fork(
      sourceId,
      copyPlan: copyPlan,
      planStepTimes: planStepTimes,
      factIds: factIds,
    );
  }
}

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _NavRouter extends Mock implements StackRouter {
  late BuildContext host;

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) =>
      Navigator.of(host).maybePop(result);
}

final _source = Beacon.empty.copyWith(
  id: _sourceId,
  title: 'Fix the north fence',
  description: 'Posts are loose near the gate.',
  status: BeaconStatus.open,
);

final _existingDraft = Beacon.empty.copyWith(
  id: _draftId,
  title: 'Tool shed rota',
  description: 'Who has the key.',
  status: BeaconStatus.draft,
);

String _header(int n) => "Facts you're bringing ($n)";

/// Hook run after every pump of [_settle], so a test can watch the screen
/// during the whole fork-and-edit sequence.
void Function()? _onPump;

Map<String, Object?> _arb(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

/// The ARB key whose English value satisfies [test]; exactly one must.
String _enKey(bool Function(String) test, String what) {
  final keys = [
    for (final e in _arb('l10n/app_en.arb').entries)
      if (!e.key.startsWith('@') &&
          e.value is String &&
          test(e.value! as String))
        e.key,
  ];
  expect(keys, hasLength(1), reason: 'one app_en.arb entry for $what');
  return keys.single;
}

String _headerKey() => _enKey(
  (v) => RegExp("Facts you'{1,2}re bringing").hasMatch(v),
  "the «Facts you're bringing (N)» header",
);

String _noticeKey() => _enKey(
  (v) => v.contains('could not be brought'),
  'the «could not be brought» notice',
);

/// The ICU `plural` branches of [value] by selector (`=1`, `one`, `other`...).
Map<String, String> _pluralBranches(String value) {
  final at = value.indexOf('plural,');
  expect(at, isNonNegative, reason: 'an ICU plural: $value');
  final out = <String, String>{};
  var i = at + 'plural,'.length;
  while (i < value.length) {
    while (i < value.length && ' \n\t'.contains(value[i])) {
      i++;
    }
    if (i >= value.length || value[i] == '}') break;
    final selStart = i;
    while (i < value.length && value[i] != '{') {
      i++;
    }
    final selector = value.substring(selStart, i).trim();
    var depth = 0;
    final bodyStart = i + 1;
    for (; i < value.length; i++) {
      if (value[i] == '{') depth++;
      if (value[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    out[selector] = value.substring(bodyStart, i);
    i++;
  }
  return out;
}

String _fillCount(String text, int n) =>
    text.replaceAll('#', '$n').replaceAll(RegExp(r'\{\w+\}'), '$n');

String _pluralText(String value, int n, {required bool russian}) {
  final b = _pluralBranches(value);
  final exact = b['=$n'];
  if (exact != null) return _fillCount(exact, n);
  final String category;
  if (russian) {
    final m10 = n % 10;
    final m100 = n % 100;
    category = m10 == 1 && m100 != 11
        ? 'one'
        : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
        ? 'few'
        : 'many';
  } else {
    category = n == 1 ? 'one' : 'other';
  }
  final branch = b[category] ?? b['other'];
  expect(branch, isNotNull, reason: 'a «$category» or «other» branch');
  return _fillCount(branch!, n);
}

String _enNotice(int n) => _pluralText(
  _arb('l10n/app_en.arb')[_noticeKey()]! as String,
  n,
  russian: false,
);

String _ruNotice(int n) {
  final ru = _arb('l10n/app_ru.arb')[_noticeKey()];
  expect(ru, isA<String>(), reason: 'app_ru.arb has the notice entry');
  return _pluralText(ru! as String, n, russian: true);
}

String _ruHeader(int n) {
  final ru = _arb('l10n/app_ru.arb')[_headerKey()];
  expect(ru, isA<String>(), reason: 'app_ru.arb has the header entry');
  return _fillCount(ru! as String, n);
}

final _headerFinder = find.textContaining(
  'Facts you',
  findRichText: true,
);

void main() {
  late ContextCubit contextCubit;
  late FakeUiEffectPort effects;
  late _Facts facts;

  setUp(() {
    GetIt.I
      ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
      ..registerSingleton<Logger>(Logger('test'));
    effects = FakeUiEffectPort();
    contextCubit = ContextCubit(
      authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      contextRepository: _ContextRepositoryFake(),
      effects: FakeUiEffectPort(),
    );
    facts = _Facts();
    registerFactRepository(facts);
  });

  tearDown(() async {
    _onPump = null;
    await contextCubit.close();
    await GetIt.I.reset();
  });

  Future<void> openEditor(
    WidgetTester tester,
    BeaconCreateCubit createCubit, {
    Locale locale = const Locale('en'),
    Size size = const Size(500, 1600),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _NavRouter();
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (homeContext) => TextButton(
            onPressed: () {
              Navigator.of(homeContext).push<void>(
                MaterialPageRoute<void>(
                  builder: (routeContext) {
                    router.host = routeContext;
                    return RouterScope(
                      controller: router,
                      stateHash: 0,
                      inheritableObserversBuilder: () => const [],
                      child: StackRouterScope(
                        controller: router,
                        stateHash: 0,
                        child: MultiBlocProvider(
                          providers: [
                            BlocProvider<ContextCubit>.value(
                              value: contextCubit,
                            ),
                            BlocProvider<BeaconCreateCubit>.value(
                              value: createCubit,
                            ),
                          ],
                          child: const BeaconCreateScreen(),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('open-create'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-create'));
    await _settle(tester);
    expect(find.byType(BeaconCreateScreen), findsOneWidget);
  }

  BeaconCreateCubit forkCubit(
    _RecordingForkPort write,
    List<String> ticked, {
    String sourceTitle = 'Fix the north fence',
  }) {
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: effects,
      forkSourceIdToLoad: _sourceId,
      forkFactIds: ticked,
      forkTitle: (t) => 'Copy of $t',
    );
    addTearDown(cubit.close);
    return cubit;
  }

  BeaconCreateCubit draftCubit() {
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(
        write: FakeBeaconWritePort(beacon: _existingDraft),
      ),
      effects: effects,
      draftBeaconIdToLoad: _draftId,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  /// Runs the lazy fork the way the first edit does.
  Future<void> runFork(WidgetTester tester, BeaconCreateCubit cubit) async {
    cubit
      ..setAutosaveContext('')
      ..setDescription('Bring a hammer too.');
    await tester.runAsync(
      () => cubit.flushAutosave().timeout(const Duration(seconds: 5)),
    );
    await _settle(tester);
  }

  /// The ✕ on the same line as the fact text [text].
  Finder closeFor(WidgetTester tester, String text) {
    final textY = tester.getCenter(find.text(text)).dy;
    final candidates = find
        .byWidgetPredicate(
          (w) =>
              w is Icon &&
              (w.icon == Icons.close ||
                  w.icon == Icons.close_rounded ||
                  w.icon == Icons.clear),
        )
        .evaluate()
        .map((e) => e.widget)
        .toList();
    expect(candidates, isNotEmpty, reason: 'a ✕ is shown next to «$text»');
    final icons = find.byWidgetPredicate(candidates.contains);
    final near = <Finder>[];
    for (var i = 0; i < icons.evaluate().length; i++) {
      final f = icons.at(i);
      if ((tester.getCenter(f).dy - textY).abs() < 30) near.add(f);
    }
    expect(near, hasLength(1), reason: 'exactly one ✕ on the line of «$text»');
    return near.single;
  }

  group('before the fork: the section is the local selection', () {
    testWidgets('lists the ticked facts under a counted header; ✕ drops one '
        'from the selection without any remove call and the fork then '
        'brings only the rest', (tester) async {
      facts.byBeacon[_sourceId] = [
        _fact('f1', 'Key is under the mat', _sourceId),
        _fact('f2', 'Shed code 4471', _sourceId),
        _fact('f3', 'Not ticked fact', _sourceId),
      ];
      final write = _RecordingForkPort(source: _source);
      final cubit = forkCubit(write, ['f1', 'f2']);
      await openEditor(tester, cubit);

      expect(find.text(_header(2)), findsOneWidget);
      expect(find.text('Key is under the mat'), findsOneWidget);
      expect(find.text('Shed code 4471'), findsOneWidget);
      expect(find.text('Not ticked fact'), findsNothing);

      await tester.tap(closeFor(tester, 'Key is under the mat'));
      await _settle(tester);

      expect(find.text('Key is under the mat'), findsNothing);
      expect(find.text('Shed code 4471'), findsOneWidget);
      expect(find.text(_header(1)), findsOneWidget);
      expect(cubit.state.forkFactIds, ['f2']);
      expect(facts.removeCalls, isEmpty);

      await runFork(tester, cubit);
      expect(write.forkFactIds, [
        ['f2'],
      ]);
    });

    testWidgets('✕ on the only ticked fact removes the whole section and the '
        'fork brings nothing', (tester) async {
      facts.byBeacon[_sourceId] = [
        _fact('f1', 'Key is under the mat', _sourceId),
      ];
      final write = _RecordingForkPort(source: _source);
      final cubit = forkCubit(write, ['f1']);
      await openEditor(tester, cubit);
      expect(find.text(_header(1)), findsOneWidget);

      await tester.tap(closeFor(tester, 'Key is under the mat'));
      await _settle(tester);

      expect(_headerFinder, findsNothing);
      expect(find.text('Key is under the mat'), findsNothing);
      await runFork(tester, cubit);
      expect(write.forkFactIds, [<String>[]]);
    });

    testWidgets('the section region offers no control to add a fact', (
      tester,
    ) async {
      facts.byBeacon[_sourceId] = [
        _fact('f1', 'Key is under the mat', _sourceId),
        _fact('f2', 'Shed code 4471', _sourceId),
      ];
      await openEditor(
        tester,
        forkCubit(_RecordingForkPort(source: _source), ['f1', 'f2']),
      );
      expect(find.text(_header(2)), findsOneWidget);

      // The region: from the header's top to a ✕-button height below the
      // last fact row.
      final top = tester.getTopLeft(find.text(_header(2))).dy;
      final bottom = tester.getBottomLeft(find.text('Shed code 4471')).dy + 24;
      bool inRegion(Finder f) {
        final dy = tester.getCenter(f).dy;
        return dy >= top && dy <= bottom;
      }

      final addIcons = {
        Icons.add,
        Icons.add_rounded,
        Icons.add_circle,
        Icons.add_circle_outline,
        Icons.add_box,
        Icons.add_box_outlined,
        Icons.post_add,
        Icons.playlist_add,
        Icons.library_add,
        Icons.note_add,
        Icons.attach_file,
      };
      final icons = find.byType(Icon);
      for (var i = 0; i < icons.evaluate().length; i++) {
        final icon = tester.widget<Icon>(icons.at(i));
        if (inRegion(icons.at(i))) {
          expect(addIcons, isNot(contains(icon.icon)), reason: 'add icon');
        }
      }
      final addLike = RegExp(
        r'^\s*(\+|add\b|attach|new fact)',
        caseSensitive: false,
      );
      final texts = find.byType(Text);
      for (var i = 0; i < texts.evaluate().length; i++) {
        if (!inRegion(texts.at(i))) continue;
        final w = tester.widget<Text>(texts.at(i));
        final label = w.data ?? w.textSpan?.toPlainText() ?? '';
        expect(addLike.hasMatch(label), isFalse, reason: 'add label «$label»');
      }
      // The Material 3 IconButton builds a private ButtonStyleButton; the ✕
      // is one, so buttons inside an IconButton are not counted.
      final buttons = find
          .byWidgetPredicate(
            (w) => w is ButtonStyleButton,
          )
          .evaluate()
          .where(
            (e) => find
                .ancestor(
                  of: find.byWidget(e.widget),
                  matching: find.byType(IconButton),
                )
                .evaluate()
                .isEmpty,
          )
          .map((e) => find.byWidget(e.widget))
          .toList();
      for (final button in buttons) {
        expect(
          inRegion(button),
          isFalse,
          reason:
              'no text/filled/outlined button inside the section (✕ is an IconButton)',
        );
      }
      final tooltips = find.byType(Tooltip);
      for (var i = 0; i < tooltips.evaluate().length; i++) {
        if (!inRegion(tooltips.at(i))) continue;
        final msg = tester.widget<Tooltip>(tooltips.at(i)).message ?? '';
        expect(addLike.hasMatch(msg), isFalse, reason: 'add tooltip «$msg»');
      }
    });
  });

  group('after the fork: the section is the draft fact list', () {
    testWidgets('lists the draft facts; ✕ calls remove with the draft id and '
        'the fact id, then the reloaded list shows the rest', (tester) async {
      facts.byBeacon[_sourceId] = [
        _fact('f1', 'Key is under the mat', _sourceId),
        _fact('f2', 'Shed code 4471', _sourceId),
      ];
      facts.byBeacon[_forkedId] = [
        _fact('g1', 'Key is under the mat (copy)', _forkedId),
        _fact('g2', 'Shed code 4471 (copy)', _forkedId),
      ];
      final write = _RecordingForkPort(source: _source);
      final cubit = forkCubit(write, ['f1', 'f2']);
      await openEditor(tester, cubit);
      await runFork(tester, cubit);

      expect(cubit.state.draftId, _forkedId);
      expect(find.text(_header(2)), findsOneWidget);
      expect(find.text('Key is under the mat (copy)'), findsOneWidget);
      expect(find.text('Shed code 4471 (copy)'), findsOneWidget);
      expect(find.text('Key is under the mat'), findsNothing);
      expect(facts.listCalls, contains(_forkedId));

      await tester.tap(closeFor(tester, 'Key is under the mat (copy)'));
      await _settle(tester);

      expect(facts.removeCalls, [(beaconId: _forkedId, factCardId: 'g1')]);
      expect(find.text('Key is under the mat (copy)'), findsNothing);
      expect(find.text('Shed code 4471 (copy)'), findsOneWidget);
      expect(find.text(_header(1)), findsOneWidget);
    });

    testWidgets('a draft that received a fact by push shows the section and '
        '✕ removes that fact from that draft', (tester) async {
      facts.byBeacon[_draftId] = [
        _fact('gpush', 'Pushed from the picker', _draftId),
      ];
      await openEditor(tester, draftCubit());

      expect(find.text(_header(1)), findsOneWidget);
      expect(find.text('Pushed from the picker'), findsOneWidget);

      await tester.tap(closeFor(tester, 'Pushed from the picker'));
      await _settle(tester);

      expect(facts.removeCalls, [
        (beaconId: _draftId, factCardId: 'gpush'),
      ]);
    });

    testWidgets("a draft without facts shows no «Facts you're bringing» "
        'section', (tester) async {
      await openEditor(tester, draftCubit());

      expect(facts.listCalls, contains(_draftId), reason: 'the list was read');
      expect(_headerFinder, findsNothing);
    });
  });

  group('could-not-be-brought notice', () {
    /// Counts every showing of a notice whose text satisfies [matches] over
    /// all pumps of the test: rising edges of the text on screen plus
    /// ShowMessage effects that carry it, so it does not matter whether the
    /// screen delivers the notice inline or as a snackbar effect.
    ({int Function() total}) watchNotice(
      WidgetTester tester,
      Finder onScreen,
      bool Function(String en, String ru) matches,
    ) {
      var edges = 0;
      var visible = false;
      _onPump = () {
        final now = onScreen.evaluate().isNotEmpty;
        if (now && !visible) edges++;
        visible = now;
      };
      return (
        total: () =>
            edges +
            effects.emitted
                .whereType<ShowMessage>()
                .where((m) => matches(m.message.toEn, m.message.toRu))
                .length,
      );
    }

    Future<void> edit(WidgetTester tester, BeaconCreateCubit cubit) async {
      cubit.setDescription('Bring a hammer and gloves.');
      await tester.runAsync(
        () => cubit.flushAutosave().timeout(const Duration(seconds: 5)),
      );
      await _settle(tester);
    }

    Future<void> wait(WidgetTester tester, Duration d) async {
      for (
        var t = Duration.zero;
        t < d;
        t += const Duration(milliseconds: 100)
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        _onPump?.call();
      }
    }

    testWidgets('3 ticked, 2 arrived: «1 fact could not be brought» is shown '
        'exactly once across the fork, later edits and reloads', (
      tester,
    ) async {
      facts.byBeacon[_sourceId] = [
        for (final i in [1, 2, 3]) _fact('f$i', 'Source fact $i', _sourceId),
      ];
      facts.byBeacon[_forkedId] = [
        _fact('g1', 'Copied fact 1', _forkedId),
        _fact('g2', 'Copied fact 2', _forkedId),
      ];
      final cubit = forkCubit(_RecordingForkPort(source: _source), [
        'f1',
        'f2',
        'f3',
      ]);
      await openEditor(tester, cubit);
      final notice = watchNotice(
        tester,
        find.text('1 fact could not be brought', findRichText: true),
        (en, _) => en.contains('1 fact could not be brought'),
      );

      await runFork(tester, cubit);
      await wait(tester, const Duration(seconds: 6));
      expect(find.text(_header(2)), findsOneWidget);
      expect(notice.total(), 1, reason: 'the notice was shown by the fork');
      await edit(tester, cubit);
      await wait(tester, const Duration(seconds: 6));
      await edit(tester, cubit);
      await wait(tester, const Duration(seconds: 6));

      expect(notice.total(), 1);
    });

    testWidgets('3 ticked, 1 arrived: «2 facts could not be brought» once', (
      tester,
    ) async {
      facts.byBeacon[_sourceId] = [
        for (final i in [1, 2, 3]) _fact('f$i', 'Source fact $i', _sourceId),
      ];
      facts.byBeacon[_forkedId] = [_fact('g1', 'Copied fact 1', _forkedId)];
      final cubit = forkCubit(_RecordingForkPort(source: _source), [
        'f1',
        'f2',
        'f3',
      ]);
      await openEditor(tester, cubit);
      final notice = watchNotice(
        tester,
        find.text('2 facts could not be brought', findRichText: true),
        (en, _) => en.contains('2 facts could not be brought'),
      );

      await runFork(tester, cubit);
      await wait(tester, const Duration(seconds: 6));

      expect(notice.total(), 1);
    });

    testWidgets('2 ticked, 2 arrived: no notice in any form', (tester) async {
      facts.byBeacon[_sourceId] = [
        for (final i in [1, 2]) _fact('f$i', 'Source fact $i', _sourceId),
      ];
      facts.byBeacon[_forkedId] = [
        _fact('g1', 'Copied fact 1', _forkedId),
        _fact('g2', 'Copied fact 2', _forkedId),
      ];
      final cubit = forkCubit(_RecordingForkPort(source: _source), [
        'f1',
        'f2',
      ]);
      await openEditor(tester, cubit);
      final notice = watchNotice(
        tester,
        find.textContaining('could not be brought', findRichText: true),
        (en, _) => en.contains('could not be brought'),
      );

      await runFork(tester, cubit);
      await wait(tester, const Duration(seconds: 2));

      expect(find.text(_header(2)), findsOneWidget);
      expect(notice.total(), 0);
    });
  });

  group('new strings exist in English and Russian', () {
    test('the header, the plural notice and «Your drafts» are in both ARB '
        'files, with Russian values', () {
      final en = _arb('l10n/app_en.arb');
      final ru = _arb('l10n/app_ru.arb');
      for (final key in [
        _headerKey(),
        _noticeKey(),
        _enKey(
          (v) => v == 'Your drafts',
          '«Your drafts»',
        ),
      ]) {
        expect(ru[key], isA<String>(), reason: 'app_ru.arb has $key');
        expect(
          hasCyrillic(ru[key]! as String),
          isTrue,
          reason: 'app_ru.arb value of $key is Russian',
        );
        expect(en[key], isA<String>());
      }
    });

    test('the notice is an ICU plural: English «1 fact» / «2 facts», Russian '
        'forms differ for 1, 2 and 5', () {
      expect(_enNotice(1), '1 fact could not be brought');
      expect(_enNotice(2), '2 facts could not be brought');
      final ru = [
        for (final n in [1, 2, 5]) _ruNotice(n),
      ];
      for (final (i, n) in [1, 2, 5].indexed) {
        expect(ru[i], contains('$n'));
        expect(hasCyrillic(ru[i]), isTrue);
      }
      expect(ru.toSet(), hasLength(3), reason: 'one, few and many differ');
    });
  });

  group('Russian locale at 375x667', () {
    testWidgets('the section header and the plural notice are Russian, '
        'without overflow', (tester) async {
      facts.byBeacon[_sourceId] = [
        for (final i in [1, 2, 3])
          _fact(
            'f$i',
            'Очень длинный текст факта номер $i про ключ под ковриком '
                'и код от сарая',
            _sourceId,
          ),
      ];
      facts.byBeacon[_forkedId] = [
        _fact('g1', 'Очень длинный текст скопированного факта', _forkedId),
      ];
      final cubit = forkCubit(_RecordingForkPort(source: _source), [
        'f1',
        'f2',
        'f3',
      ]);
      await openEditor(
        tester,
        cubit,
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      Future<void> reveal(String text) async {
        // The scroller of the form: the one holding the title field.
        final form = find
            .ancestor(
              of: find.byType(TextField).first,
              matching: find.byType(Scrollable),
            )
            .first;
        final target = find.text(text, findRichText: true);
        for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
          await tester.drag(form, const Offset(0, -200));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(target, findsOneWidget, reason: 'the Russian text «$text»');
        await tester.ensureVisible(target);
        await tester.pump();
      }

      await reveal(_ruHeader(3));
      expect(find.text(_header(3)), findsNothing, reason: 'not English');
      expect(tester.takeException(), isNull);

      final ruNotice = _ruNotice(2);
      var edges = 0;
      var visible = false;
      _onPump = () {
        final now = find
            .text(ruNotice, findRichText: true)
            .evaluate()
            .isNotEmpty;
        if (now && !visible) edges++;
        visible = now;
      };
      await runFork(tester, cubit);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        _onPump?.call();
      }
      final viaEffects = effects.emitted
          .whereType<ShowMessage>()
          .where((m) => m.message.toRu == ruNotice)
          .length;

      expect(edges + viaEffects, 1, reason: 'the exact RU text «$ruNotice»');
      await reveal(_ruHeader(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('real path (HTTP -> Ferry -> repository -> cubit -> screen)', () {
    testWidgets('the fact list response for the draft id fills the section; '
        '✕ sends the remove mutation for that draft and fact', (tester) async {
      final sent = <Map<String, dynamic>>[];
      final removed = <Map<String, dynamic>>[];
      late RemoteApiService remote;
      late BeaconFactCardRepository repository;
      await tester.runAsync(() async {
        await http.runWithClient(
          () async {
            remote = RemoteApiService(
              const Env(),
              const WebSocketClientRealtimeSocketFactory(),
            );
            await remote.setSessionAuth();
            await remote.getAuthToken();
            repository = BeaconFactCardRepository(remote);
          },
          () => MockClient((request) async {
            http.Response json(Object body) => http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json'},
            );
            if (request.url.path.endsWith('/session/access-token')) {
              return json({
                'subject': 'Uviewer000001',
                'access_token': 'test-token',
                'expires_in': 3600,
              });
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final name = body['operationName'] as String;
            final vars = (body['variables'] as Map).cast<String, dynamic>();
            if (name == 'BeaconFactCardList') sent.add(vars);
            if (name == 'BeaconFactCardRemove') removed.add(vars);
            return json({
              'data': switch (name) {
                'BeaconFactCardList' => {
                  '__typename': 'query_root',
                  'BeaconFactCardList': [
                    for (final (id, text) in [
                      ('Fwire00001', 'Wire fact about the key'),
                      ('Fwire00002', 'Wire fact about the shed'),
                    ])
                      {
                        '__typename': 'v2_BeaconFactCardRow',
                        'id': id,
                        'beaconId': _draftId,
                        'factText': text,
                        'visibility': BeaconFactCardVisibilityBits.public,
                        'pinnedBy': 'Upinner000001',
                        'pinnedByTitle': 'Pinner',
                        'sourceMessageId': null,
                        'status': BeaconFactCardStatusBits.active,
                        'createdAt': '2026-10-01T08:00:00.000Z',
                        'updatedAt': null,
                        'attachmentsJson': '[]',
                        'revisionSeq': 1,
                        'lastEditedBy': null,
                        'lastEditedByTitle': null,
                        'lastEditedAt': null,
                        'otherEditorCount': 0,
                        'historyTruncated': false,
                        'savedByMe': false,
                        'originBeaconKind': null,
                      },
                  ],
                },
                'BeaconFactCardRemove' => {
                  '__typename': 'mutation_root',
                  'BeaconFactCardRemove': true,
                },
                _ => null,
              },
            });
          }),
        );
      });
      addTearDown(() => tester.runAsync(remote.close));
      registerFactRepository(repository);

      await openEditor(tester, draftCubit());
      await pumpRealAsync(tester);

      expect(sent.any((v) => v['beaconId'] == _draftId), isTrue);
      expect(find.text(_header(2)), findsOneWidget);
      expect(find.text('Wire fact about the key'), findsOneWidget);
      expect(find.text('Wire fact about the shed'), findsOneWidget);

      await tester.tap(closeFor(tester, 'Wire fact about the key'));
      await pumpRealAsync(tester);

      expect(removed, [
        {'beaconId': _draftId, 'factCardId': 'Fwire00001'},
      ]);
    });
  });
}

/// Bounded pumps: the editor keeps timers (autosave) that never settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    _onPump?.call();
  }
}
