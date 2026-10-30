// #459: «Show fewer» on the Field screen brings the owner's «+N more» chip
// back and refits the camera to the collapsed set, with no recenter.
//
// constellation_overflow_collapse_test.dart pins the same outcome on a bare
// ConstellationBody: a default scene that lays out synchronously, reduced
// motion and a field holding only the owner's Requests. With only the owner
// on the field, a refit to the owner and its Requests is also the fit of the
// whole collapsed field, so that test cannot tell them apart. This test
// mounts the real ConstellationScreen with a frame-sliced scene (as
// ConstellationScreen.wrappedRoute builds it), animations on, nine contacts
// and a saved tag magnet, as the QA account has them. Only the repositories
// and the slice scheduler's frame pacing are stand-ins.

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
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
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

/// Desktop Chrome and iPhone SE, the two viewports of the report.
const _viewports = {
  'desktop': Size(1280, 900),
  'phone': Size(375, 667),
};

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

/// The owner has 35 open Requests and nine mutual contacts; Bob has two.
ConstellationField _field() {
  const contacts = [
    ConstellationPerson(id: 'bob', displayName: 'Bob'),
    ConstellationPerson(id: 'carol', displayName: 'Carol'),
    ConstellationPerson(id: 'dave', displayName: 'Dave'),
    ConstellationPerson(id: 'erin', displayName: 'Erin'),
    ConstellationPerson(id: 'frank', displayName: 'Frank'),
    ConstellationPerson(id: 'grace', displayName: 'Grace'),
    ConstellationPerson(id: 'heidi', displayName: 'Heidi'),
    ConstellationPerson(id: 'ivan', displayName: 'Ivan'),
    ConstellationPerson(id: 'judy', displayName: 'Judy'),
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
        logger: Logger('overflow collapse screen'),
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

Matrix4 _cameraMatrix(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .clone();

void main() {
  group('Show fewer on the Field screen', () {
    for (final MapEntry(key: name, value: size) in _viewports.entries) {
      testWidgets(
        'brings the owner overflow chip back and refits the camera to the '
        'collapsed field without a recenter ($name)',
        (tester) async {
          final cubit = await _mountFieldScreen(tester, size);
          final controller = cubit.graphController;

          // As in the report: recenter on the owner, then expand.
          await tester.tap(find.byTooltip('Center view'));
          await _settle(tester);
          final recentredCamera = _cameraMatrix(tester);
          final hiddenBefore = cubit.overflowHiddenCountByAuthor['ego'];
          expect(hiddenBefore, isNotNull, reason: 'the owner starts collapsed');
          final collapsedNodeCount =
              controller.renderSnapshot.topology.nodesById.length;
          expect(find.byKey(_ownerChip), findsOneWidget);
          expect(find.text('+$hiddenBefore more'), findsOneWidget);

          await tester.tap(find.text('+$hiddenBefore more'));
          await _settle(tester);
          expect(find.text('Show fewer'), findsOneWidget);
          final viewport = tester.getRect(find.byType(ConstellationBody));
          final fewerRect = tester.getRect(find.byKey(_ownerChip));
          expect(
            viewport.contains(fewerRect.topLeft) &&
                viewport.contains(fewerRect.bottomRight),
            isTrue,
            reason: 'the expanded camera keeps «Show fewer» on screen',
          );
          expect(
            controller.renderSnapshot.topology.nodesById.length,
            greaterThan(collapsedNodeCount),
            reason: 'expanding reveals the hidden Requests',
          );
          final expandedCamera = _cameraMatrix(tester);

          await tester.tap(find.text('Show fewer'));
          await _settle(tester);

          expect(
            controller.renderSnapshot.topology.nodesById,
            hasLength(collapsedNodeCount),
            reason: 'collapsing hides the revealed Requests again',
          );
          expect(find.text('Show fewer'), findsNothing);
          expect(
            find.byKey(_ownerChip),
            findsOneWidget,
            reason: "the owner's overflow chip is built again with no recenter",
          );
          expect(
            find.descendant(
              of: find.byKey(_ownerChip),
              matching: find.text('+$hiddenBefore more'),
            ),
            findsOneWidget,
          );
          final chipRect = tester.getRect(find.byKey(_ownerChip));
          expect(
            viewport.contains(chipRect.topLeft) &&
                viewport.contains(chipRect.bottomRight),
            isTrue,
            reason: 'the restored chip is on screen',
          );

          final collapsedCamera = _cameraMatrix(tester);
          final expectedCamera = recentredCamera;
          expect(
            expectedCamera.storage,
            isNot(
              orderedEquals(
                expandedCamera.storage.map((v) => closeTo(v, 0.000001)),
              ),
            ),
            reason: 'the recentred camera differs from the expanded one',
          );
          expect(
            collapsedCamera.storage,
            orderedEquals(
              expectedCamera.storage.map((v) => closeTo(v, 0.000001)),
            ),
            reason: 'Show fewer returns the camera to the recentred framing',
          );
        },
      );
    }
  });
}
