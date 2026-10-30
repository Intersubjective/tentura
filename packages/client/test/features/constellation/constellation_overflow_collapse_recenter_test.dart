// #459: «Show fewer» on the Field screen leaves the camera where «Center view»
// puts it on the collapsed graph, at a wide (desktop) and a compact (phone)
// width alike, whichever pointer collapsed it.
//
// constellation_overflow_collapse_screen_test.dart pins that «Show fewer» fits
// the collapsed field; this test pins the user-visible contract the report
// states: after expand and «Show fewer» the camera is the one recenter gives.

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
        logger: Logger('overflow collapse recenter'),
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


/// Where [matrix] sends a few scene points: an equality that reads in screen
/// pixels, the unit a user sees a camera drift in.
List<Offset> _screenPoints(Matrix4 matrix) => [
  for (final scene in const [Offset.zero, Offset(1000, 0), Offset(0, 1000)])
    MatrixUtils.transformPoint(matrix, scene),
];

/// Taps like the pointer of the device: a mouse that moves onto its target and
/// hovers there first, as on desktop, or a bare touch.
final class _Pointer {
  _Pointer(this.tester, this.kind);

  final WidgetTester tester;
  final PointerDeviceKind kind;
  TestGesture? _mouse;

  Future<void> tap(Finder target) async {
    if (kind == PointerDeviceKind.touch) {
      await tester.tap(target);
      return;
    }
    var mouse = _mouse;
    if (mouse == null) {
      mouse = _mouse = await tester.createGesture(kind: kind);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
    }
    final at = tester.getCenter(target);
    await mouse.moveTo(at);
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.down(at);
    await mouse.up();
  }
}

void main() {
  group('Show fewer on the Field screen', () {
    const pointers = {
      'desktop': PointerDeviceKind.mouse,
      'phone': PointerDeviceKind.touch,
    };
    for (final MapEntry(key: name, value: size) in _viewports.entries) {
      testWidgets(
        'leaves the camera where recenter puts it on the collapsed graph '
        '($name)',
        (tester) async {
          final pointer = _Pointer(tester, pointers[name]!);
          final cubit = await _mountFieldScreen(tester, size);

          await tester.tap(find.byTooltip('Center view'));
          await _settle(tester);
          final recentred = _cameraMatrix(tester);
          final hidden = cubit.overflowHiddenCountByAuthor['ego'];
          expect(hidden, isNotNull, reason: 'the owner starts collapsed');

          await pointer.tap(find.text('+$hidden more'));
          await _settle(tester);
          expect(find.text('Show fewer'), findsOneWidget);

          await pointer.tap(find.text('Show fewer'));
          await _settle(tester);
          expect(find.text('Show fewer'), findsNothing);
          expect(find.byKey(_ownerChip), findsOneWidget);

          final collapsed = _screenPoints(_cameraMatrix(tester));
          final expected = _screenPoints(recentred);
          for (var i = 0; i < expected.length; i++) {
            expect(
              (collapsed[i] - expected[i]).distance,
              lessThan(1),
              reason:
                  'scene point $i lands at ${collapsed[i]}, recenter puts it '
                  'at ${expected[i]}',
            );
          }
        },
      );
    }
  });
}
