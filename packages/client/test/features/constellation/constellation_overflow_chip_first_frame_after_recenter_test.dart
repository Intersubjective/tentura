import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/frame_slice_scheduler.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _owner = Profile(id: 'ego', displayName: 'Alice');

const _ownerChip = Key('constellation.overflow.ego');

/// Desktop Chrome, the viewport of the report.
const _desktop = Size(1280, 900);

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

const _magnetTag = 'qa-magnet';

/// Contacts carrying the magnet's tag; the magnet pulls them on the Field.
const _magnetTagged = {'carol', 'dave', 'erin'};

/// One saved magnet for [_magnetTag], as the QA account has it.
final class _SavedMagnets implements ConstellationTagMagnetRepositoryPort {
  @override
  Future<List<ConstellationTagMagnet>> list() async => const [
    ConstellationTagMagnet(
      tagId: _magnetTag,
      xUnits: 2.5,
      yUnits: 1.5,
      revision: 1,
    ),
  ];

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) => throw UnimplementedError();

  @override
  Future<void> remove({
    required String tagId,
    required String clientOpId,
  }) => throw UnimplementedError();
}

/// The owner has 35 open Requests and ten mutual contacts; Bob has two.
ConstellationField _field() {
  const contacts = [
    ConstellationPerson(id: 'bob', displayName: 'Bob'),
    ConstellationPerson(id: 'carol', displayName: 'Carol'),
    ConstellationPerson(id: 'dave', displayName: 'Dave GQ2'),
    ConstellationPerson(id: 'erin', displayName: 'Erin'),
    ConstellationPerson(id: 'frank', displayName: 'Frank'),
    ConstellationPerson(id: 'grace', displayName: 'Grace'),
    ConstellationPerson(id: 'heidi', displayName: 'Heidi'),
    ConstellationPerson(id: 'ivan', displayName: 'Ivan'),
    ConstellationPerson(id: 'judy', displayName: 'Judy'),
    ConstellationPerson(id: 'kate', displayName: 'Kate'),
  ];
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 29),
    context: '',
    peers: contacts,
    edges: [
      for (final contact in contacts) ...[
        ConstellationTrustEdgeEntity(src: 'ego', dst: contact.id, tier: 1),
        ConstellationTrustEdgeEntity(src: contact.id, dst: 'ego', tier: 1),
      ],
    ],
    directContactIds: [for (final contact in contacts) contact.id],
    requests: [
      for (var i = 0; i < 35; i++)
        ConstellationRequest(
          id: 'request-ego-$i',
          authorId: 'ego',
          title: 'Alice request $i',
          status: 0,
          isMine: true,
        ),
      for (var i = 0; i < 2; i++)
        ConstellationRequest(
          id: 'request-bob-$i',
          authorId: 'bob',
          title: 'Bob request $i',
          status: 0,
        ),
    ],
  );
}

/// Runs layout jobs the way the app's FrameSliceScheduler does: in bounded
/// slices, one per frame, so a layout lands frames after the tap that asked
/// for it. The production scheduler posts idle tasks the fake-async test
/// binding re-polls forever while an animation runs, so it cannot be pumped.
class _FrameSlices extends Fake implements FrameSliceScheduler {
  static const _unitsPerFrame = 8;

  bool Function(int units)? _step;
  void Function()? _onComplete;
  var _epoch = 0;

  @override
  void start({
    required bool Function(int units) step,
    required void Function() onComplete,
  }) {
    cancel();
    _step = step;
    _onComplete = onComplete;
    _postSlice();
  }

  void _postSlice() {
    final epoch = _epoch;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _slice(epoch))
      ..ensureVisualUpdate();
  }

  void _slice(int epoch) {
    final step = _step;
    if (epoch != _epoch || step == null) return;
    if (!step(_unitsPerFrame)) {
      _postSlice();
      return;
    }
    final onComplete = _onComplete;
    cancel();
    onComplete?.call();
  }

  @override
  void cancel() {
    _epoch++;
    _step = null;
    _onComplete = null;
  }

  @override
  void cancelJob(void Function() onComplete) {
    if (identical(_onComplete, onComplete)) cancel();
  }

  @override
  void dispose() => cancel();
}

/// The cubit as ConstellationScreen.wrappedRoute builds it: a frame-sliced
/// scene over a fake repository.
Future<ConstellationCubit> _loadCubit(WidgetTester tester) async {
  final cubit = (await tester.runAsync(() async {
    final realtime = buildTestRealtimeSync();
    addTearDown(realtime.port.dispose);
    final cubit = ConstellationCubit(
      case_: constellationCaseForField(_field()),
      viewer: _owner,
      ownTagIdsOf: (personId) =>
          _magnetTagged.contains(personId) ? const {_magnetTag} : const {},
      tagMagnetCase: ConstellationTagMagnetCase(
        _SavedMagnets(),
        realtime.case_,
        env: const Env(),
        logger: Logger('overflow chip first frame'),
      ),
      scene: ConstellationSceneController(slicer: _FrameSlices()),
    );
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
    return cubit;
  }))!;
  return cubit;
}

Future<ConstellationCubit> _mountFieldScreen(
  WidgetTester tester,
  Size viewportSize,
) async {
  await tester.binding.setSurfaceSize(viewportSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final cubit = await _loadCubit(tester);
  final reselect = HomeTabReselectCubit();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await reselect.close();
    await cubit.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConstellationCubit>.value(value: cubit),
            BlocProvider<HomeTabReselectCubit>.value(value: reselect),
            BlocProvider<GraphPersonContextCubit>(
              create: (_) => _StubContextCubit(),
            ),
            BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(FakeUiEffectPort()),
            ),
          ],
          child: const ConstellationScreen(),
        ),
      ),
    ),
  );
  await _settle(tester);
  return cubit;
}

/// Lets sliced layouts and camera animations finish. Never long enough to
/// matter for a user watching the screen (the QA report waited ~10 s).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Rect _chipRect(WidgetTester tester) => tester.getRect(find.byKey(_ownerChip));

/// Centre of the node [graphId] in global screen coordinates.
Offset _nodeCentre(
  WidgetTester tester,
  ConstellationCubit cubit,
  String graphId,
) {
  final scene = cubit.graphController.getPositionOrNullForId(graphId);
  expect(scene, isNotNull, reason: 'node $graphId has a scene position');
  final overlay = tester.getTopLeft(
    find.byType(ConstellationViewportOverlay),
  );
  return overlay + cubit.graphController.sceneToViewportLocal(scene!);
}

/// Attribution uses screen-space centres, independent of node radii.
double _distanceToNode(
  WidgetTester tester,
  ConstellationCubit cubit,
  Rect rect,
  String graphId,
) => (rect.center - _nodeCentre(tester, cubit, graphId)).distance;

void main() {
  group('Field owner overflow chip after Center view', () {
    testWidgets(
      'is placed on the first frame where the settled layout puts it, '
      'nearest to its author',
      (tester) async {
        final cubit = await _mountFieldScreen(tester, _desktop);
        expect(cubit.overflowHiddenCountByAuthor['ego'], isNotNull);

        // Zoom out first: recenter then changes the scale and the layout.
        final wheel =
            tester.getCenter(find.byType(ConstellationViewportOverlay)) +
            const Offset(300, 0);
        for (var i = 0; i < 2; i++) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: wheel,
              scrollDelta: const Offset(0, 300),
            ),
          );
          await _settle(tester);
        }

        await tester.tap(find.byTooltip('Center view'));
        await tester.pump();
        expect(find.byKey(_ownerChip), findsOneWidget);
        final firstFrame = _chipRect(tester);
        final firstFrameDistances = {
          for (final id
              in cubit.graphController.renderSnapshot.topology.nodesById.keys)
            id: _distanceToNode(tester, cubit, firstFrame, id),
        };

        // Record the settled recenter separately from the zoom reference.
        // _settle advances 120 frames of 50 ms (6 seconds).
        await _settle(tester);
        final settledAfterRecenter = _chipRect(tester);
        final settledRecenterDistances = {
          for (final id
              in cubit.graphController.renderSnapshot.topology.nodesById.keys)
            id: _distanceToNode(tester, cubit, settledAfterRecenter, id),
        };

        // Each half of the zoom cycle also gets 6 seconds to settle before
        // measuring the final reference rect.
        final viewport = tester.getCenter(
          find.byType(ConstellationViewportOverlay),
        );
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: viewport + const Offset(300, 0),
            scrollDelta: const Offset(0, -100),
          ),
        );
        await _settle(tester);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: viewport + const Offset(300, 0),
            scrollDelta: const Offset(0, 100),
          ),
        );
        await _settle(tester);
        final settled = _chipRect(tester);

        final referenceDistances = {
          for (final id
              in cubit.graphController.renderSnapshot.topology.nodesById.keys)
            id: _distanceToNode(tester, cubit, settled, id),
        };
        for (final (stage, referenceRect) in [
          ('settled recenter before zoom', settledAfterRecenter),
          ('settled zoom cycle', settled),
        ]) {
          for (final (first, reference) in [
            (firstFrame.left, referenceRect.left),
            (firstFrame.top, referenceRect.top),
            (firstFrame.right, referenceRect.right),
            (firstFrame.bottom, referenceRect.bottom),
          ]) {
            expect(
              first,
              closeTo(reference, 2),
              reason:
                  'first frame rect $firstFrame must match '
                  '$stage rect $referenceRect within 2 pixels',
            );
          }
        }
        // Evaluate all three frames together so a failure reports whether the
        // initial placement, settled recenter, or zoom reference misattributes
        // the chip. Distances use each frame's own node/camera positions.
        final closerOrEquallyCloseNodes = {
          for (final (stage, distances) in [
            ('first frame after recenter', firstFrameDistances),
            ('settled recenter before zoom', settledRecenterDistances),
            ('settled zoom cycle', referenceDistances),
          ])
            stage: [
              for (final other in distances.entries)
                if (other.key != 'fp:ego' &&
                    other.value <= distances['fp:ego']!)
                  other.key,
            ],
        };
        expect(
          closerOrEquallyCloseNodes,
          {
            'first frame after recenter': isEmpty,
            'settled recenter before zoom': isEmpty,
            'settled zoom cycle': isEmpty,
          },
          reason:
              'Alice must have the nearest screen-space centre in all layouts; '
              'first-frame distances: $firstFrameDistances; '
              'settled recenter distances: $settledRecenterDistances; '
              'reference distances: $referenceDistances',
        );
      },
    );
  });
}
