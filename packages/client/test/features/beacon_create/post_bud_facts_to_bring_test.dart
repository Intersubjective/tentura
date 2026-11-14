// «Facts to bring» in the Post bud form («Оформить запрос»): the Post's readable
// facts as an unticked checklist, the ticked ids sent as `factIds` in the bud
// mutation (and none at all when nothing is ticked), also for an archived Post,
// no skipped-facts notice afterwards, EN and RU copy, and no overflow on a
// 375x667 phone in Russian.
//
// Driven the way a person uses it: the real BeaconCreateScreen over a real
// BeaconCreateCubit. Most tests use an in-memory bud port; the real-path test
// goes HTTP -> Ferry -> BeaconFactCardRepository / PostBudRepository.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/facts_to_bring_checklist.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../../support/remote_wire_harness.dart';
import '../beacon_threads/fact_origin_test_support.dart'
    show pumpRealAsync, registerFactRepository;
import '../beacon_threads/room_cubit_fakes.dart'
    show FakeBeaconFactCardRepository;
import 'post_bud_fakes.dart';

BeaconFactCard _fact(String id, String text) => BeaconFactCard(
  id: id,
  beaconId: kBudPostId,
  factText: text,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Upinner000001',
  createdAt: DateTime.utc(2026, 10),
  status: BeaconFactCardStatusBits.active,
);

class _Facts extends FakeBeaconFactCardRepository {
  _Facts(this.facts);

  final List<BeaconFactCard> facts;
  final listCalls = <String>[];

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    listCalls.add(beaconId);
    return beaconId == kBudPostId ? [...facts] : const [];
  }
}

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _Router extends Mock implements StackRouter {
  final opened = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    opened.add(route);
    return null;
  }
}

typedef _Pumped = ({
  BudHarness h,
  BeaconCreateCubit cubit,
  _Router router,
  _Facts? facts,
  FakeUiEffectPort effects,
});

Future<_Pumped> _pump(
  WidgetTester tester, {
  List<BeaconFactCard> facts = const [],
  Beacon? post,
  Locale locale = const Locale('en'),
  Size surface = const Size(800, 1600),
  PostBudCase Function(BudHarness h)? budCase,
  bool realFactRepository = false,
  Future<void> Function()? beforePump,
}) async {
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<Env>(const Env())
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
    )
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake());
  addTearDown(GetIt.I.reset);
  _Facts? repo;
  if (!realFactRepository) {
    repo = _Facts(facts);
    registerFactRepository(repo);
  }
  await beforePump?.call();

  final h = BudHarness(parent: post ?? budPost());
  final cubit = BeaconCreateCubit(
    beaconCreateCase: h.createCase,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      h.hierarchy,
      createCase: h.createCase,
      beacons: h.write,
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
    messagePrefillCase: h.prefillCase,
    postBudCase: budCase?.call(h) ?? h.postBudCase,
    childCreationContext: kBudContext,
    effects: effects,
  );
  addTearDown(cubit.close);

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: surface),
        child: TenturaResponsiveScope(
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider(create: (_) => ContextCubit()),
                  BlocProvider<BeaconCreateCubit>.value(value: cubit),
                ],
                child: const BeaconCreateScreen(
                  parentBeaconId: kBudPostId,
                  sourceMessageId: kBudSourceMessageId,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester, real: realFactRepository);
  return (h: h, cubit: cubit, router: router, facts: repo, effects: effects);
}

Future<void> _settle(WidgetTester tester, {bool real = false}) async {
  if (real) return pumpRealAsync(tester);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The form step has «Next» and the invite step «Оформить запрос»; the facts
/// checklist may live on either, so look on the form step first, then the next.
Future<void> _revealFacts(WidgetTester tester, String factText) async {
  // Exactly one bud step is showing: the form step (Next) or the invite step.
  final onForm = find.byKey(const Key('PostBud.NextButton')).evaluate();
  final onInvite = find.byKey(const Key('PostBud.SubmitButton')).evaluate();
  expect(onForm.length + onInvite.length, 1, reason: 'a bud step is showing');
  if (find.text(factText).evaluate().isNotEmpty) return;
  expect(onForm, hasLength(1), reason: 'the form step comes first');
  await tester.tap(find.byKey(const Key('PostBud.NextButton')));
  await _settle(tester);
  expect(
    find.byKey(const Key('PostBud.SubmitButton')),
    findsOneWidget,
    reason: 'the second bud step is the invite step',
  );
  expect(find.text(factText), findsOneWidget);
}

Future<void> _submit(WidgetTester tester, {bool real = false}) async {
  if (find.byKey(const Key('PostBud.SubmitButton')).evaluate().isEmpty) {
    await tester.ensureVisible(find.byKey(const Key('PostBud.NextButton')));
    await tester.tap(find.byKey(const Key('PostBud.NextButton')));
    await _settle(tester, real: real);
  }
  await tester.ensureVisible(find.byKey(const Key('PostBud.SubmitButton')));
  await tester.tap(find.byKey(const Key('PostBud.SubmitButton')));
  await _settle(tester, real: real);
}

Future<void> _tick(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
}

List<BeaconFactCard> _many(int n) => [
  for (var i = 1; i <= n; i++) _fact('F$i', 'Fact number $i'),
];

void main() {
  group('bud form facts checklist', () {
    testWidgets('a Post with facts shows them unticked, in list order', (
      tester,
    ) async {
      final p = await _pump(
        tester,
        facts: [
          _fact('F1', 'Meet at the north gate'),
          _fact('F2', 'Bring gloves'),
        ],
      );
      await _revealFacts(tester, 'Meet at the north gate');

      expect(find.byType(FactsToBringChecklist), findsOneWidget);
      expect(find.text('Facts to bring'), findsOneWidget);
      expect(p.facts!.listCalls, contains(kBudPostId));
      final first = tester.getTopLeft(find.text('Meet at the north gate')).dy;
      final second = tester.getTopLeft(find.text('Bring gloves')).dy;
      expect(first, lessThan(second));
      final boxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(boxes, hasLength(2));
      expect(boxes.every((b) => b.value == false), isTrue);
    });

    testWidgets('a Post without facts shows no checklist or heading', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byKey(const Key('PostBud.NextButton')), findsOneWidget);
      expect(find.byType(FactsToBringChecklist), findsNothing);
      expect(find.text('Facts to bring'), findsNothing);
      await tester.tap(find.byKey(const Key('PostBud.NextButton')));
      await _settle(tester);
      expect(find.byKey(const Key('PostBud.SubmitButton')), findsOneWidget);
      expect(find.byType(FactsToBringChecklist), findsNothing);
      expect(find.text('Facts to bring'), findsNothing);
    });

    testWidgets('the form of an archived Post still shows the checklist', (
      tester,
    ) async {
      final p = await _pump(
        tester,
        post: budPost().copyWith(expiresAt: DateTime.utc(2020)),
        facts: [_fact('F1', 'Meet at the north gate')],
      );
      expect(p.cubit.state.postBud, isNotNull);
      await _revealFacts(tester, 'Meet at the north gate');
      expect(find.byType(FactsToBringChecklist), findsOneWidget);
      // Read-only archive: the checklist is still usable and shows no error.
      CheckboxListTile box() => tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(box().onChanged, isNotNull, reason: 'checkbox is not disabled');
      expect(box().value, isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(p.effects.emitted, isEmpty);

      await _tick(tester, 'Meet at the north gate');
      expect(box().value, isTrue);
      expect(box().onChanged, isNotNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(p.effects.emitted, isEmpty);
      await _submit(tester);
      expect(p.h.port.calls, hasLength(1));
      expect(p.h.port.calls.single.factIds, ['F1']);
    });

    testWidgets('EN copy: «Facts to bring» and «Select all»', (tester) async {
      await _pump(tester, facts: [_fact('F1', 'Bring gloves')]);
      await _revealFacts(tester, 'Bring gloves');
      expect(find.text('Facts to bring'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
    });

    testWidgets('RU copy on a 375x667 phone, no overflow', (tester) async {
      await _pump(
        tester,
        locale: const Locale('ru'),
        surface: const Size(375, 667),
        facts: [
          _fact('F1', 'Встретиться у северных ворот'),
          _fact('F2', 'Взять перчатки'),
        ],
      );
      await _revealFacts(tester, 'Встретиться у северных ворот');
      await tester.ensureVisible(find.text('Взять факты'));
      expect(find.text('Взять факты'), findsOneWidget);
      expect(find.text('Выбрать все'), findsOneWidget);
      expect(find.byType(FactsToBringChecklist), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('bud request carries the ticked facts', () {
    testWidgets('tick F1 and F3, untick F1: only F3 is sent', (tester) async {
      final p = await _pump(tester, facts: _many(3));
      await _revealFacts(tester, 'Fact number 1');
      await _tick(tester, 'Fact number 1');
      await _tick(tester, 'Fact number 3');
      await _tick(tester, 'Fact number 1');
      await _submit(tester);

      expect(p.h.port.calls, hasLength(1));
      expect(p.h.port.calls.single.factIds, ['F3']);
    });

    testWidgets('nothing ticked: the bud call carries no fact ids', (
      tester,
    ) async {
      final p = await _pump(tester, facts: _many(2));
      await _submit(tester);

      expect(p.h.port.calls, hasLength(1));
      expect(p.h.port.calls.single.factIds ?? const [], isEmpty);
    });

    testWidgets('cubit.submitBud with no ticks sends no fact ids', (
      tester,
    ) async {
      final p = await _pump(tester, facts: _many(2));
      await tester.runAsync(() => p.cubit.submitBud(context: ''));
      expect(p.h.port.calls, hasLength(1));
      expect(p.h.port.calls.single.factIds ?? const [], isEmpty);
    });

    testWidgets('25 facts: Select all caps at 20 and sends the first 20', (
      tester,
    ) async {
      final p = await _pump(tester, facts: _many(25));
      await _revealFacts(tester, 'Fact number 1');
      await tester.ensureVisible(find.text('Select all'));
      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(
        find.text('Only the first 20 were selected, the most you can bring'),
        findsOneWidget,
      );
      await _submit(tester);

      expect(p.h.port.calls, hasLength(1));
      expect(p.h.port.calls.single.factIds, [
        for (var i = 1; i <= 20; i++) 'F$i',
      ]);
    });

    testWidgets('RU: 25 facts, Select all shows the RU cap notice', (
      tester,
    ) async {
      final p = await _pump(
        tester,
        locale: const Locale('ru'),
        facts: _many(25),
      );
      await _revealFacts(tester, 'Fact number 1');
      await tester.ensureVisible(find.text('Выбрать все'));
      await tester.tap(find.text('Выбрать все'));
      await tester.pump();
      expect(
        find.text('Выбраны только первые 20 — больше взять нельзя'),
        findsOneWidget,
      );
      await _submit(tester);
      expect(p.h.port.calls.single.factIds, hasLength(20));
    });

    testWidgets('a created child opens with no skipped-facts notice and no '
        'fact list read for the child', (tester) async {
      final p = await _pump(tester, facts: _many(2));
      p.h.port.result = const PostBudResult(
        outcome: PostBudOutcome.created,
        childBeaconId: 'child-9',
      );
      await _revealFacts(tester, 'Fact number 1');
      await _tick(tester, 'Fact number 1');
      await _tick(tester, 'Fact number 2');
      await _submit(tester);

      expect(p.router.opened, hasLength(1));
      final args = p.router.opened.single.args! as BeaconViewRouteArgs;
      expect(args.id, 'child-9');
      expect(p.h.port.calls.single.factIds, ['F1', 'F2']);
      expect(p.facts!.listCalls, isNot(contains('child-9')));
      // No notice of any kind: no snackbar, no error/notice effect.
      expect(find.byType(SnackBar), findsNothing);
      expect(p.effects.emitted, isEmpty);
      expect(find.textContaining('Could not invite'), findsNothing);
    });
  });

  group('real path (HTTP -> Ferry -> repositories -> cubit -> screen)', () {
    Future<
      ({
        List<Map<String, dynamic>> bud,
        List<String> lists,
        RemoteApiService remote,
        BeaconFactCardRepository facts,
      })
    >
    startWire(WidgetTester tester, {required int factCount}) async {
      final bud = <Map<String, dynamic>>[];
      final lists = <String>[];
      late RemoteApiService remote;
      late BeaconFactCardRepository facts;
      await tester.runAsync(() async {
        await http.runWithClient(
          () async {
            remote = RemoteApiService(
              const Env(),
              const WebSocketClientRealtimeSocketFactory(),
            );
            await remote.setSessionAuth();
            await remote.getAuthToken();
            facts = BeaconFactCardRepository(remote);
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
            final vars = ((body['variables'] as Map?) ?? const {})
                .cast<String, dynamic>();
            if (name == 'PostBudFromPost') bud.add(vars);
            if (name == 'BeaconFactCardList') {
              lists.add(vars['beaconId'] as String);
            }
            return json({
              'data': switch (name) {
                'BeaconFactCardList' => {
                  '__typename': 'query_root',
                  'BeaconFactCardList': [
                    for (final (id, text) in [
                      ('Fwire00001', 'Meet at the north gate'),
                      ('Fwire00002', 'Bring gloves'),
                    ].take(factCount))
                      {
                        '__typename': 'v2_BeaconFactCardRow',
                        'id': id,
                        'beaconId': kBudPostId,
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
                'PostBudInviteCandidates' => {
                  '__typename': 'query_root',
                  'postBudInviteCandidates': <Object>[],
                },
                'PostBudFromPost' => {
                  '__typename': 'mutation_root',
                  'beaconBudFromPost': {
                    '__typename': 'PostBudResult',
                    'outcome': 'created',
                    'childBeaconId': 'Bchild0000001',
                    'invitees': <Object>[],
                  },
                },
                _ => null,
              },
            });
          }),
        );
      });
      addTearDown(() => tester.runAsync(remote.close));
      return (bud: bud, lists: lists, remote: remote, facts: facts);
    }

    PostBudCase realCase(BudHarness h, RemoteApiService remote) => PostBudCase(
      PostBudRepository(remote),
      h.profiles,
      OpIdService(),
      env: const Env(),
      logger: Logger('post-bud-wire-test'),
    );

    testWidgets('the fact list response fills the checklist; ticked ids go '
        'out as factIds in order', (tester) async {
      final wire = await startWire(tester, factCount: 2);
      registerFactRepository(wire.facts);
      await _pump(
        tester,
        realFactRepository: true,
        budCase: (h) => realCase(h, wire.remote),
      );
      expect(wire.lists, contains(kBudPostId));
      await _revealFacts(tester, 'Meet at the north gate');
      expect(find.text('Bring gloves'), findsOneWidget);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((b) => b.value == false),
        isTrue,
      );

      await _tick(tester, 'Bring gloves');
      await _tick(tester, 'Meet at the north gate');
      await _submit(tester, real: true);

      expect(wire.bud, hasLength(1));
      expect(wire.bud.single['factIds'], ['Fwire00001', 'Fwire00002']);
    });

    testWidgets('a response with zero facts shows no checklist; the bud '
        'mutation has no factIds variable', (tester) async {
      final wire = await startWire(tester, factCount: 0);
      registerFactRepository(wire.facts);
      await _pump(
        tester,
        realFactRepository: true,
        budCase: (h) => realCase(h, wire.remote),
      );
      expect(find.byType(FactsToBringChecklist), findsNothing);
      expect(find.text('Facts to bring'), findsNothing);

      await _submit(tester, real: true);
      expect(wire.bud, hasLength(1));
      expect(wire.bud.single.containsKey('factIds'), isFalse);
    });

    testWidgets('facts listed but none ticked: no factIds variable at all', (
      tester,
    ) async {
      final wire = await startWire(tester, factCount: 2);
      registerFactRepository(wire.facts);
      await _pump(
        tester,
        realFactRepository: true,
        budCase: (h) => realCase(h, wire.remote),
      );
      await _revealFacts(tester, 'Meet at the north gate');
      await _submit(tester, real: true);

      expect(wire.bud, hasLength(1));
      expect(wire.bud.single.containsKey('factIds'), isFalse);
      expect(wire.bud.single['postId'], kBudPostId);
    });
  });

  group('PostBudRepository.budFromPost factIds on the wire', () {
    Map<String, dynamic> response() => {
      '__typename': 'mutation_root',
      'beaconBudFromPost': {
        '__typename': 'PostBudResult',
        'outcome': 'created',
        'childBeaconId': 'Bchild0000001',
        'invitees': [
          {
            '__typename': 'PostBudInviteeResult',
            'userId': 'Uinvitee00001',
            'outcome': 'invited',
          },
        ],
      },
    };

    // Every argument of the existing «sends every argument» case; only
    // factIds varies between the tests below.
    final fullVars = <String, dynamic>{
      'postId': 'Bpost00000001',
      'sourceMessageId': 'Mmsg00000001',
      'clientCommandId': 'cmd-1',
      'title': 'Fix the fence',
      'description': 'Posts are loose',
      'context': 'home',
      'coordinates': {'lat': 1.5, 'long': 2.5},
      'startAt': '2026-10-12T09:00:00.000Z',
      'endAt': '2026-10-13T18:00:00.000Z',
      'tags': 'fence',
      'needs': 'tools',
      'primaryNeedSlug': 'tools',
      'addressLabel': 'Garden',
      'isDiscoverable': true,
      'invitees': [
        {'userId': 'Uinvitee00001', 'note': 'You have a saw'},
        {'userId': 'Uinvitee00002'},
      ],
      'closePost': true,
    };

    const invitees = [
      PostBudInvitee(userId: 'Uinvitee00001', note: 'You have a saw'),
      PostBudInvitee(userId: 'Uinvitee00002'),
    ];

    Future<PostBudResult> call(
      PostBudRepository repo, {
      List<String>? factIds,
      bool withFactIds = false,
    }) {
      if (!withFactIds) {
        return repo.budFromPost(
          postId: 'Bpost00000001',
          sourceMessageId: 'Mmsg00000001',
          clientCommandId: 'cmd-1',
          title: 'Fix the fence',
          description: 'Posts are loose',
          context: 'home',
          coordinates: const Coordinates(lat: 1.5, long: 2.5),
          startAt: DateTime.utc(2026, 10, 12, 9),
          endAt: DateTime.utc(2026, 10, 13, 18),
          tags: 'fence',
          needs: 'tools',
          primaryNeedSlug: 'tools',
          addressLabel: 'Garden',
          isDiscoverable: true,
          invitees: invitees,
          closePost: true,
        );
      }
      // `factIds:` does not exist on the typed signature yet, so this goes
      // through dynamic; switch to the typed call once the parameter exists.
      return (repo as dynamic).budFromPost(
            postId: 'Bpost00000001',
            sourceMessageId: 'Mmsg00000001',
            clientCommandId: 'cmd-1',
            title: 'Fix the fence',
            description: 'Posts are loose',
            context: 'home',
            coordinates: const Coordinates(lat: 1.5, long: 2.5),
            startAt: DateTime.utc(2026, 10, 12, 9),
            endAt: DateTime.utc(2026, 10, 13, 18),
            tags: 'fence',
            needs: 'tools',
            primaryNeedSlug: 'tools',
            addressLabel: 'Garden',
            isDiscoverable: true,
            invitees: invitees,
            closePost: true,
            factIds: factIds,
          )
          as Future<PostBudResult>;
    }

    Future<({List<WireSent> sent, PostBudResult result})> run({
      List<String>? factIds,
      bool withFactIds = false,
    }) async {
      final sent = <WireSent>[];
      late PostBudResult result;
      await withRemoteWire({'PostBudFromPost': response()}, sent, (
        remote,
      ) async {
        result = await call(
          PostBudRepository(remote),
          factIds: factIds,
          withFactIds: withFactIds,
        );
      });
      return (sent: sent, result: result);
    }

    void expectMapped(PostBudResult r) {
      expect(r.outcome, PostBudOutcome.created);
      expect(r.childBeaconId, 'Bchild0000001');
      expect(r.invitees, const [
        PostBudInviteeResult(
          userId: 'Uinvitee00001',
          outcome: PostBudInviteOutcome.invited,
        ),
      ]);
    }

    test(
      'factIds [F2, F1] are sent in the order given; result unchanged',
      () async {
        final r = await run(factIds: ['F2', 'F1'], withFactIds: true);
        expect(r.sent.single.operationName, 'PostBudFromPost');
        expect(r.sent.single.variables, {
          ...fullVars,
          'factIds': ['F2', 'F1'],
        });
        expectMapped(r.result);
      },
    );

    test('an empty factIds list leaves the factIds variable out', () async {
      final r = await run(factIds: const [], withFactIds: true);
      expect(r.sent.single.variables.containsKey('factIds'), isFalse);
      expect(r.sent.single.variables, fullVars);
      expectMapped(r.result);
    });

    test('null factIds leaves the factIds variable out', () async {
      final r = await run(withFactIds: true);
      expect(r.sent.single.variables.containsKey('factIds'), isFalse);
      expect(r.sent.single.variables, fullVars);
      expectMapped(r.result);
    });

    test(
      'omitting factIds leaves the variable out, others unchanged',
      () async {
        final r = await run();
        expect(r.sent.single.variables.containsKey('factIds'), isFalse);
        expect(r.sent.single.variables, fullVars);
        expectMapped(r.result);
      },
    );
  });

  group('l10n copy parity', () {
    test('app_en.arb and app_ru.arb define exactly the same message keys', () {
      Set<String> keys(String f) =>
          (jsonDecode(File('l10n/$f').readAsStringSync())
                  as Map<String, dynamic>)
              .keys
              .where((k) => !k.startsWith('@'))
              .toSet();
      final en = keys('app_en.arb');
      final ru = keys('app_ru.arb');
      expect(en.difference(ru), isEmpty, reason: 'keys missing from RU');
      expect(ru.difference(en), isEmpty, reason: 'keys missing from EN');
      expect(en, containsAll(['factsToBringTitle', 'factsToBringCapNotice']));
    });
  });
}
