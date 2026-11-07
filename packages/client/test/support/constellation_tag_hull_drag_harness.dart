import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../features/constellation/fixtures/constellation_arrange_harness.dart';
import '../ui/effect/fake_ui_effect_port.dart';
import 'constellation_store_fixture.dart';
import 'fake_clock_port.dart';
import 'fake_wake_up_port.dart';
import 'phone_surface.dart';
import 'remote_wire_harness.dart';
import 'test_realtime_sync.dart';

const hullDragMembers = ['ann', 'bob', 'cid'];
const hullDragPeople = [...hullDragMembers, 'dan', 'eve'];

// Both triangles have empty interior. Dan belongs only to the second tag;
// Eve is an unrelated person. Cid starts without an anchor, so a group drop
// must create a pin as well as move the existing pins.
const _positions = <String, Offset>{
  'ann': Offset(-0.6, 0.4),
  'bob': Offset(0.6, 0.4),
  'cid': Offset(0, 1.45),
  'dan': Offset(0, 1.05),
  'eve': Offset(-0.6, -0.75),
};

Offset hullDragInitialScene(String personId) =>
    const Offset(kConstellationCanvasCentre, kConstellationCanvasCentre) +
    _positions[personId]! * kConstellationRingUnitPixels;

final class HullDragHarness {
  const HullDragHarness({
    required this.cubit,
    required this.selection,
    required this.lens,
    required this.server,
    required this.scene,
  });

  final ConstellationCubit cubit;
  final ConstellationSceneController scene;
  final ConstellationSelectionCubit selection;
  final ConstellationTagLensCubit lens;
  final ArrangeAnchorRepository server;
}

final class _ContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _ContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void clearSelection() {}

  @override
  void dismiss() {}

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}
}

/// Deterministic free-node geometry, independent of force-layout timing.
/// Saved anchors still place pinned people, as in the production layout.
final class _Layout implements SceneLayoutAlgorithm {
  const _Layout(this.server);

  final ArrangeAnchorRepository server;

  Offset _personPosition(String id) {
    final anchor = server.anchors[ConstellationAnchorTarget.person(id)];
    return anchor == null
        ? hullDragInitialScene(id)
        : Offset(
            kConstellationCanvasCentre +
                anchor.xUnits * kConstellationRingUnitPixels,
            kConstellationCanvasCentre +
                anchor.yUnits * kConstellationRingUnitPixels,
          );
  }

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          id: switch (id) {
            final String id
                when id.startsWith('fp:') &&
                    hullDragPeople.contains(id.substring(3)) =>
              ScenePoint(
                x: _personPosition(id.substring(3)).dx,
                y: _personPosition(id.substring(3)).dy,
              ),
            // Posts keep free people on the Field but do not obscure the
            // empty hull interior used by these tests.
            final String id when id.startsWith('fr:') => ScenePoint(
              x: kConstellationCanvasCentre + 300,
              y: kConstellationCanvasCentre - 200,
            ),
            _ => ScenePoint(
              x: kConstellationCanvasCentre,
              y: kConstellationCanvasCentre,
            ),
          },
      },
      isTerminal: true,
    );
  }
}

Map<String, dynamic> _peer(String id, {bool contactOnly = false}) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'displayName': switch (id) {
    'ann' => 'Анна',
    'bob' => 'Борис',
    'cid' => 'Вера',
    'dan' => 'Денис',
    _ => 'Елена',
  },
  'contactOnly': contactOnly,
  'visible': !contactOnly,
  'presence': contactOnly ? 'contactOnly' : 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'handle': null,
  'image': null,
  'pinState': null,
  'isNew': false,
};

Map<String, dynamic> _fieldWire(
  ArrangeAnchorRepository server, {
  required List<String> unreachablePeerIds,
}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-07T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': hullDragPeople,
    // Unreachable peers are tagged contacts the server lists as contact-only:
    // the map draws no node for them.
    'peers': [
      for (final id in hullDragPeople) _peer(id),
      for (final id in unreachablePeerIds) _peer(id, contactOnly: true),
    ],
    'edges': [
      for (final id in hullDragPeople)
        {
          '__typename': 'v2_ConstellationTrustEdge',
          'src': 'ego',
          'dst': id,
          'tier': 1,
        },
    ],
    'requests': <dynamic>[],
    'posts': [
      for (final id in hullDragPeople)
        {
          '__typename': 'v2_ConstellationPost',
          'id': 'post-$id',
          'authorId': id,
          'rootExcerpt': 'Запись',
          'lastActivityAt': '2026-11-07T12:00:00.000Z',
          'expiresAt': null,
          'status': 0,
          'isPinned': false,
          'hiddenReachCount': 0,
          'has_unread': false,
        },
    ],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '${server.revision}',
      'anchors': [
        for (final entry in server.anchors.entries)
          {
            '__typename': 'v2_ConstellationAnchor',
            'targetKind': 'PERSON',
            'targetId': entry.key.id,
            'xUnits': entry.value.xUnits,
            'yUnits': entry.value.yUnits,
            'coordinateSpaceVersion': 1,
            'revision': '${server.revision}',
            'placedAt': '2026-11-07T11:00:00.000Z',
          },
      ],
      'pinnedPeers': [
        for (final target in server.anchors.keys) _peer(target.id),
      ],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

Map<String, dynamic> _tag(String id, String name, int order) => {
  '__typename': 'PersonTag',
  'id': id,
  'name': name,
  'glyph': order == 0 ? 'С' : 'М',
  'color': order,
  'ord': order,
  'count': 3,
  'countOffField': 0,
};

Future<void> pumpHullDragFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> flushHullDragWrites(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await pumpHullDragFrames(tester);
}

/// Real Field and people-tag HTTP responses pass through Ferry, their real
/// repositories and cases to the production cubits and ConstellationBody.
/// The existing arrangement harness models only the anchor server.
Future<void> withHullDragField(
  WidgetTester tester,
  Future<void> Function(HullDragHarness harness) body, {
  required bool arranging,
  bool overlapping = false,
  // Replaces the default tag membership: tag id -> member ids, one own tag
  // per entry in map order.
  Map<String, List<String>>? tagMembers,
  // Tagged people the server lists but the map does not draw.
  List<String> unreachablePeerIds = const [],
  // Keeps the mocked wire open for the whole test body, so a test can change
  // [tagMembers] and have `PeopleTagsCase.load()` fetch the new membership.
  bool keepWireOpen = false,
  Locale locale = const Locale('ru'),
}) async {
  await usePhoneSurface(tester);
  final server = ArrangeAnchorRepository({
    for (final id in hullDragPeople)
      if (id != 'cid')
        ConstellationAnchorTarget.person(id): arrangePosition(
          _positions[id]!.dx,
          _positions[id]!.dy,
        ),
  });
  final sent = <WireSent>[];
  late HullDragHarness harness;
  late Future<void> Function() dispose;
  // Finish network setup in the real async zone, as other wire/widget
  // fixtures do. Pointer timers and pumps below stay in widget fake time.
  // Created inside runAsync so they complete in the real-async zone.
  late Completer<void> wireReady;
  late Completer<void> wireGate;
  Future<void>? wireRun;
  await tester.runAsync(() async {
    wireReady = Completer<void>();
    wireGate = Completer<void>();
    wireRun = withRemoteWire(
      const {},
      sent,
      (remote) async {
        final sync = buildTestRealtimeSync();
        final tags = PeopleTagsCase(
          PeopleTagsRepository(remote),
          sync.case_,
          env: const Env(),
          logger: Logger('TagHullDrag'),
        );
        await tags.load();
        GetIt.I.registerSingleton<PeopleTagsCase>(tags);
        addTearDown(() => GetIt.I.reset());
        final store = ConstellationStoreFixture(
          ConstellationRepository(remote),
          accountId: 'ego',
          realtime: sync.case_,
          clock: FakeClockPort(DateTime.utc(2026, 11, 7)),
          wakeUp: FakeWakeUpPort(),
        ).store;
        final placement = ConstellationPlacementCase(
          server,
          store,
          FakeClockPort(DateTime.utc(2026, 11, 7)),
          FakeWakeUpPort(),
          realtime: sync.case_,
          env: const Env(),
          logger: Logger('TagHullDrag'),
        );
        final scene = ConstellationSceneController();
        final cubit = ConstellationCubit(
          scene: scene,
          case_: store,
          placementCase: placement,
          viewer: const Profile(id: 'ego', displayName: 'Я'),
          loadOnCreate: false,
          semanticZoomEnabled: false,
        )..testSceneLayoutAlgorithmOverride = _Layout(server);
        final selection = ConstellationSelectionCubit();
        final lens = ConstellationTagLensCubit(ownTagIdsOf: tags.tagsOfPerson);
        await cubit.load();
        harness = HullDragHarness(
          cubit: cubit,
          selection: selection,
          lens: lens,
          server: server,
          scene: scene,
        );
        dispose = () async {
          await lens.close();
          await selection.close();
          await cubit.close();
          await placement.dispose();
          await GetIt.I.reset();
          await tags.dispose();
          await sync.port.dispose();
        };
        if (keepWireOpen) {
          wireReady.complete();
          await wireGate.future;
        }
      },
      responseFor: (request) async => switch (request.operationName) {
        'ConstellationFieldFetch' || 'ConstellationAnchorsFetch' => _fieldWire(
          server,
          unreachablePeerIds: unreachablePeerIds,
        ),
        'PersonTags' => {
          '__typename': 'query_root',
          'personTags': tagMembers == null
              ? [
                  _tag('tag-a', 'Соседи', 0),
                  if (overlapping) _tag('tag-b', 'Мастерская', 1),
                ]
              : [
                  for (final (i, id) in tagMembers.keys.indexed)
                    _tag(id, 'Тег $id', i),
                ],
        },
        'PersonTagMemberships' => {
          '__typename': 'query_root',
          'personTagMemberships': [
            if (tagMembers != null)
              for (final entry in tagMembers.entries)
                {
                  '__typename': 'PersonTagMembership',
                  'tagId': entry.key,
                  'personIds': entry.value,
                  'inherited': <dynamic>[],
                },
            if (tagMembers == null)
              {
                '__typename': 'PersonTagMembership',
                'tagId': 'tag-a',
                'personIds': hullDragMembers,
                'inherited': <dynamic>[],
              },
            if (tagMembers == null && overlapping)
              {
                '__typename': 'PersonTagMembership',
                'tagId': 'tag-b',
                'personIds': ['ann', 'bob', 'dan'],
                'inherited': <dynamic>[],
              },
          ],
        },
        _ => throw StateError(
          'Unexpected wire operation: ${request.operationName}',
        ),
      },
    );
    if (keepWireOpen) {
      await wireReady.future;
    } else {
      await wireRun;
    }
  });
  final cubit = harness.cubit;
  final selection = harness.selection;
  final lens = harness.lens;
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<ConstellationSelectionCubit>.value(
                value: selection,
              ),
              BlocProvider<ConstellationTagLensCubit>.value(value: lens),
              // The Field screen always provides an idle composer.
              BlocProvider<ConstellationComposerCubit>(
                create: (_) => ConstellationComposerCubit(
                  positions: const {},
                  eligible: const {},
                  createCubitFactory: (kind) => BeaconCreateCubit(kind: kind),
                  forwardCubitFactory: (beaconId) =>
                      ForwardCubit(beaconId: beaconId, embedded: true),
                ),
              ),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _ContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: Scaffold(
              body: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await pumpHullDragFrames(tester);
    if (arranging) {
      await tester.tap(
        find.byKey(const Key('constellation.camera.arrange')),
      );
      await pumpHullDragFrames(tester);
    }
    // Put the saved triangle in view at 1:1 scale, as after a user zooms
    // and pans to it. All subsequent input goes through the Field widget.
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..setTranslationRaw(
        kPhoneSurface.width / 2 - kConstellationCanvasCentre,
        kPhoneSurface.height / 2 - kConstellationCanvasCentre - 100,
        0,
      );
    await pumpHullDragFrames(tester);
    expect(
      sent.map((request) => request.operationName),
      containsAll([
        'ConstellationFieldFetch',
        'PersonTags',
        'PersonTagMemberships',
      ]),
      reason: 'the mounted Field and hulls came from the real wire path',
    );
    expect(cubit.state.status, isA<StateIsSuccess>());
    expect(selection.state.arranging, arranging);
    expect(tester.takeException(), isNull);
    await body(harness);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await dispose();
      if (!wireGate.isCompleted) wireGate.complete();
      await wireRun;
    });
  }
}
