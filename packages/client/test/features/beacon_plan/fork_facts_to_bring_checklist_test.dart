@Timeout(Duration(minutes: 2))
library;

// «Create from this Request» with a «Facts to bring» checklist (fact
// continuity plan D14, §6.4). The fork action loads the source's readable
// facts with the existing fact list query and shows the plan copy sheet when
// the source has a plan or at least one readable fact. Ticked ids ride to the
// editor as the `forkFactIds` list of `AppNavigator.createBeacon` (the route
// puts them in its `fork_facts` query; their encoding is not read here).
//
// The action is called exactly as its callers call it today, with no fact
// argument: it must load the facts itself. The app's fact list query is
// reached the way other sheets reach it, through GetIt: the tests register
// one BeaconFactCardRepository and a BeaconThreadsCase over it
// (registerFactRepository), so the action may use either. Most tests use an
// in-memory repository; the real-path test registers the production
// repository over the real Ferry link chain with only HTTP faked.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_copy_sheet.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/env.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_app_navigator.dart';
import '../beacon_threads/fact_origin_test_support.dart'
    show pumpRealAsync, registerFactRepository;
import '../beacon_threads/room_cubit_fakes.dart'
    show FakeBeaconFactCardRepository;
import 'beacon_plan_test_support.dart';

/// The source's readable facts as the fact list query returns them; records
/// which beacon each query asked for.
class _SourceFacts extends FakeBeaconFactCardRepository {
  List<BeaconFactCard> facts = const [];
  final queriedFor = <String>[];

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    queriedFor.add(beaconId);
    return facts.where((f) => f.beaconId == beaconId).toList();
  }
}

BeaconFactCard _fact(
  String id,
  String text, {
  int visibility = BeaconFactCardVisibilityBits.public,
}) => BeaconFactCard(
  id: id,
  beaconId: 'src',
  factText: text,
  visibility: visibility,
  pinnedBy: 'Upinner000001',
  createdAt: DateTime.utc(2026, 10),
  status: BeaconFactCardStatusBits.active,
);

final _key = _fact(
  'Fkey',
  'Key is under the mat',
  visibility: BeaconFactCardVisibilityBits.room,
);
final _gloves = _fact('Fgloves', 'Bring gloves');
final _shed = _fact(
  'Fshed',
  'Shed code 4471',
  visibility: BeaconFactCardVisibilityBits.room,
);

List<BeaconFactCard> _many(int n) => [
  for (var i = 1; i <= n; i++)
    _fact('F${i.toString().padLeft(2, '0')}', 'Fact number $i'),
];

/// The lock mark is assumed to be a Material lock icon (any of these
/// variants), as every other «restricted» mark in the app is.
final _lockIcons = <IconData>{
  Icons.lock,
  Icons.lock_outline,
  Icons.lock_outlined,
  Icons.lock_rounded,
  Icons.lock_outline_rounded,
};

final _lock = find.byWidgetPredicate(
  (w) => w is Icon && _lockIcons.contains(w.icon),
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

/// The text of ARB [message] exactly, any value standing in for its
/// placeholders (a whole-text match, not a fragment).
Finder _exactly(String message) {
  final pattern = message
      .split(RegExp(r'\{[^}]*\}'))
      .map(RegExp.escape)
      .join('.+');
  return find.textContaining(RegExp('^$pattern\$'));
}

/// New strings of the checklist, by the ARB key that must define them.
const _newKeys = [
  'factsToBringTitle',
  'factsToBringSelectAll',
  'factsToBringCapNotice',
  'factsToBringLockLegend',
];

void main() {
  final plan = BeaconPlan.decode(planJson());
  final noPlan = plan.withSteps(const []);
  late FakeAppNavigator navigator;
  late _SourceFacts repository;

  setUp(() {
    navigator = registerFakeAppNavigator();
    repository = _SourceFacts();
    registerFactRepository(repository);
  });

  /// «Create from this request» on source `src`, called as the overflow menu
  /// calls it; [facts] are what the fact list query holds for it.
  Future<void> createFrom(
    BuildContext context, {
    required List<BeaconFactCard> facts,
    BeaconPlan? sourcePlan,
  }) {
    repository.facts = facts;
    return runBeaconCreateFromAction(
      context,
      sourceBeaconId: 'src',
      sourcePlan: sourcePlan,
    );
  }

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onTap, {
    Locale locale = const Locale('en'),
    Size size = const Size(500, 1400),
    bool realAsync = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => onTap(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    if (realAsync) {
      await pumpRealAsync(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(PlanCopySheet.confirmKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PlanCopySheet.confirmKey));
    await tester.pumpAndSettle();
  }

  Future<void> tick(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  // FakeAppNavigator records only arguments that differ from their defaults
  // (empty strings and empty lists are left out), so «no forkFactIds key»
  // means the action passed no fact ids.

  /// The ids the editor was opened with, from the `forkFactIds` argument.
  List<String> openedWithFactIds() {
    final intent = navigator.named('createBeacon').single;
    final ids = intent.args['forkFactIds'] as List<String>?;
    return ids ?? const [];
  }

  /// The checklist row holding [text]: its nearest ancestor with a checkbox.
  Finder rowOf(String text) {
    final element = _elementOf(find.text(text));
    Element? row;
    element.visitAncestorElements((ancestor) {
      final hasCheckbox = find
          .descendant(
            of: find.byElementPredicate((e) => e == ancestor),
            matching: find.byType(Checkbox),
          )
          .evaluate()
          .isNotEmpty;
      if (hasCheckbox) {
        row = ancestor;
        return false;
      }
      return true;
    });
    expect(row, isNotNull, reason: '«$text» is not a checklist row');
    return find.byElementPredicate((e) => e == row);
  }

  group('Create from this Request offers facts to bring', () {
    testWidgets(
      'a source with facts and no plan opens the sheet with the checklist '
      'and no plan row',
      (tester) async {
        await pumpHost(
          tester,
          (context) =>
              createFrom(context, facts: [_key, _gloves], sourcePlan: noPlan),
        );

        expect(repository.queriedFor, ['src']);
        expect(navigator.named('createBeacon'), isEmpty);
        expect(find.byType(PlanCopySheet), findsOneWidget);
        expect(find.byKey(PlanCopySheet.toggleKey), findsNothing);
        expect(find.text('Facts to bring'), findsOneWidget);
        expect(find.text('Select all'), findsOneWidget);
        expect(find.text('Key is under the mat'), findsOneWidget);
        expect(find.text('Bring gloves'), findsOneWidget);
      },
    );

    testWidgets('a source with neither plan nor facts opens the editor '
        'straight away', (tester) async {
      await pumpHost(
        tester,
        (context) => createFrom(context, facts: const [], sourcePlan: noPlan),
      );

      expect(repository.queriedFor, ['src']);
      expect(find.byType(PlanCopySheet), findsNothing);
      expect(navigator.intents, [
        const NavIntent('createBeacon', {'forkSourceId': 'src'}),
      ]);
    });

    testWidgets('a source with plan steps and facts shows the plan row and '
        'every readable fact', (tester) async {
      await pumpHost(
        tester,
        (context) => createFrom(
          context,
          facts: [_key, _gloves, _shed],
          sourcePlan: plan,
        ),
      );

      expect(find.byKey(PlanCopySheet.toggleKey), findsOneWidget);
      expect(find.text('Facts to bring'), findsOneWidget);
      for (final f in [_key, _gloves, _shed]) {
        await tester.ensureVisible(find.text(f.factText));
        expect(find.text(f.factText), findsOneWidget);
      }
    });

    testWidgets('a source with plan steps and no facts shows the plan row '
        'only and forks with no facts', (tester) async {
      await pumpHost(
        tester,
        (context) => createFrom(context, facts: const [], sourcePlan: plan),
      );

      // The source's facts were looked up and found empty.
      expect(repository.queriedFor, ['src']);
      expect(find.byKey(PlanCopySheet.toggleKey), findsOneWidget);
      expect(find.text('Facts to bring'), findsNothing);
      expect(find.text('Select all'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);

      await confirm(tester);
      final intent = navigator.named('createBeacon').single;
      expect(intent.args['forkSourceId'], 'src');
      expect(intent.args.containsKey('forkFactIds'), isFalse);
      // The plan choice travels as before.
      expect(
        decodePlanStepTimesQuery(intent.args['forkPlanTimes']! as String),
        hasLength(plan.steps.length),
      );
    });

    testWidgets('nothing is ticked at first: confirming brings no facts', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context) =>
            createFrom(context, facts: [_key, _gloves], sourcePlan: noPlan),
      );

      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(boxes, hasLength(2));
      expect(boxes.where((b) => b.value ?? false), isEmpty);

      await confirm(tester);
      final intent = navigator.named('createBeacon').single;
      expect(intent.args['forkSourceId'], 'src');
      expect(intent.args.containsKey('forkFactIds'), isFalse);
      expect(intent.args.containsKey('forkPlanTimes'), isFalse);
    });

    testWidgets('ticked facts reach the editor as forkFactIds', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context) => createFrom(
          context,
          facts: [_key, _gloves, _shed],
          sourcePlan: plan,
        ),
      );

      await tick(tester, 'Key is under the mat');
      await tick(tester, 'Shed code 4471');
      await confirm(tester);

      expect(openedWithFactIds(), unorderedEquals(['Fkey', 'Fshed']));
      // Ticking facts leaves the plan choice untouched.
      expect(
        decodePlanStepTimesQuery(
          navigator.named('createBeacon').single.args['forkPlanTimes']!
              as String,
        ),
        hasLength(plan.steps.length),
      );
    });

    testWidgets('a discussion-only fact shows a Material lock icon, a '
        'request-visible fact shows none', (tester) async {
      await pumpHost(
        tester,
        (context) =>
            createFrom(context, facts: [_key, _gloves], sourcePlan: noPlan),
      );

      expect(
        find.descendant(of: rowOf('Key is under the mat'), matching: _lock),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf('Bring gloves'), matching: _lock),
        findsNothing,
      );
    });

    testWidgets('Select all with more than 20 facts ticks the first 20 and '
        'says so', (tester) async {
      final facts = _many(25);
      final capNotice = _exactly(
        _arb('en')['factsToBringCapNotice'] as String,
      );
      await pumpHost(
        tester,
        (context) => createFrom(context, facts: facts, sourcePlan: noPlan),
      );

      expect(capNotice, findsNothing);
      await tick(tester, 'Select all');
      expect(capNotice, findsOneWidget);

      await confirm(tester);
      expect(
        openedWithFactIds(),
        unorderedEquals([for (final f in facts.take(20)) f.id]),
      );
    });

    testWidgets('Select all with 20 or fewer facts ticks every fact without '
        'a notice', (tester) async {
      final facts = _many(3);
      final capNotice = _exactly(
        _arb('en')['factsToBringCapNotice'] as String,
      );
      await pumpHost(
        tester,
        (context) => createFrom(context, facts: facts, sourcePlan: noPlan),
      );

      await tick(tester, 'Select all');
      expect(capNotice, findsNothing);

      await confirm(tester);
      expect(
        openedWithFactIds(),
        unorderedEquals([for (final f in facts) f.id]),
      );
    });

    testWidgets('with 20 facts ticked a 21st cannot be ticked', (
      tester,
    ) async {
      final facts = _many(21);
      await pumpHost(
        tester,
        (context) => createFrom(context, facts: facts, sourcePlan: noPlan),
      );

      for (final f in facts.take(20)) {
        await tick(tester, f.factText);
      }
      await tick(tester, 'Fact number 21');

      // On screen: the 21st row stays unticked and 20 boxes stay ticked
      // (the checklist sits in the sheet's scroll view; offstage rows count).
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(
                of: rowOf('Fact number 21'),
                matching: find.byType(Checkbox),
              ),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox, skipOffstage: false))
            .where((b) => b.value ?? false),
        hasLength(20),
      );

      await confirm(tester);

      final ids = openedWithFactIds();
      expect(ids, hasLength(20));
      expect(ids, isNot(contains('F21')));
    });

    testWidgets('dismissing the sheet opens no editor', (tester) async {
      await pumpHost(
        tester,
        (context) =>
            createFrom(context, facts: [_key, _gloves], sourcePlan: noPlan),
      );
      expect(find.byType(PlanCopySheet), findsOneWidget);

      await tick(tester, 'Bring gloves');
      // Dismiss as a barrier tap or Back does: pop the sheet's route with no
      // result.
      Navigator.of(tester.element(find.byType(PlanCopySheet))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(PlanCopySheet), findsNothing);
      expect(navigator.named('createBeacon'), isEmpty);
    });

    testWidgets('the action queries the fact list for its source over the '
        'wire and lists every returned fact', (tester) async {
      final sent = <({String name, Map<String, dynamic> vars})>[];
      Map<String, dynamic> row(String id, String text, int visibility) => {
        '__typename': 'v2_BeaconFactCardRow',
        'id': id,
        'beaconId': 'src',
        'factText': text,
        'visibility': visibility,
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
      };
      late RemoteApiService remote;
      await tester.runAsync(
        () => http.runWithClient(
          () async {
            remote = RemoteApiService(
              const Env(),
              const WebSocketClientRealtimeSocketFactory(),
            );
            await remote.setSessionAuth();
            await remote.getAuthToken();
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
            sent.add((
              name: name,
              vars: ((body['variables'] as Map?) ?? const {})
                  .cast<String, dynamic>(),
            ));
            return json({
              'data': name == 'BeaconFactCardList'
                  ? {
                      '__typename': 'query_root',
                      'BeaconFactCardList': [
                        row('Fwire1', 'Meet at the north gate', 0),
                        row('Fwire2', 'Ladder is in the shed', 1),
                      ],
                    }
                  : null,
            });
          }),
        ),
      );
      addTearDown(() => tester.runAsync(remote.close));
      registerFactRepository(BeaconFactCardRepository(remote));

      await pumpHost(
        tester,
        (context) => runBeaconCreateFromAction(
          context,
          sourceBeaconId: 'src',
          sourcePlan: noPlan,
        ),
        realAsync: true,
      );

      final listQueries = [
        for (final s in sent)
          if (s.name == 'BeaconFactCardList') s.vars,
      ];
      expect(listQueries, isNotEmpty, reason: 'the fact list was not queried');
      expect(listQueries.map((v) => v['beaconId']).toSet(), {'src'});
      expect(navigator.named('createBeacon'), isEmpty);
      expect(find.text('Facts to bring'), findsOneWidget);
      expect(find.text('Meet at the north gate'), findsOneWidget);
      expect(find.text('Ladder is in the shed'), findsOneWidget);
      expect(
        find.descendant(of: rowOf('Ladder is in the shed'), matching: _lock),
        findsOneWidget,
      );
    });
  });

  group('Facts to bring strings', () {
    test('EN and RU define every new checklist string', () {
      final en = _arb('en');
      final ru = _arb('ru');
      for (final key in _newKeys) {
        expect(en[key], isA<String>(), reason: 'app_en.arb lacks $key');
        expect(ru[key], isA<String>(), reason: 'app_ru.arb lacks $key');
        expect(ru[key], isNot(en[key]), reason: '$key is not translated');
      }
    });

    testWidgets('EN renders every checklist string in English', (
      tester,
    ) async {
      final en = _arb('en');
      final facts = [
        _fact(
          'Fen1',
          'Key is under the mat by the back door',
          visibility: BeaconFactCardVisibilityBits.room,
        ),
        ..._many(24),
      ];
      await pumpHost(
        tester,
        (context) => createFrom(context, facts: facts, sourcePlan: plan),
      );

      expect(en['factsToBringTitle'], 'Facts to bring');
      expect(en['factsToBringSelectAll'], 'Select all');
      expect(find.text('Facts to bring'), findsOneWidget);
      await tick(tester, 'Select all');
      expect(
        _exactly(en['factsToBringCapNotice'] as String),
        findsOneWidget,
      );
      final legend = _exactly(en['factsToBringLockLegend'] as String);
      await tester.ensureVisible(legend);
      expect(legend, findsOneWidget);
    });

    testWidgets('RU on a 375×667 phone renders the checklist translated, '
        'without overflow', (tester) async {
      final ru = _arb('ru');
      final facts = [
        _fact(
          'Fru1',
          'Ключ лежит под ковриком у задней двери, синий брелок',
          visibility: BeaconFactCardVisibilityBits.room,
        ),
        ..._many(24),
      ];
      await pumpHost(
        tester,
        (context) => createFrom(context, facts: facts, sourcePlan: plan),
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      expect(find.text(ru['factsToBringTitle'] as String), findsOneWidget);
      expect(find.text('Facts to bring'), findsNothing);
      await tick(tester, ru['factsToBringSelectAll'] as String);
      expect(
        _exactly(ru['factsToBringCapNotice'] as String),
        findsOneWidget,
      );
      await tester.ensureVisible(
        _exactly(ru['factsToBringLockLegend'] as String),
      );
      expect(
        _exactly(ru['factsToBringLockLegend'] as String),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// The element behind [finder]; it must match exactly one.
Element _elementOf(Finder finder) => finder.evaluate().single;
