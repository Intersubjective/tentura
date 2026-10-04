// The map composer's circle: a press on the rim handle resizes the radius
// (pre-existing), a press anywhere else inside the circle drags the draft
// centre itself (ConstellationComposerCubit.moveDraft).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_composer_radius.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  void clearSelection() {}
}

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

Future<ConstellationCubit> _loadCubit() async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: const [
            ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
        ),
      ),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationComposerRadiusTest'),
    ),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

ConstellationComposerCubit _buildComposerCubit() => ConstellationComposerCubit(
  positions: const {},
  eligible: const {},
  createCubitFactory: (kind) => BeaconCreateCubit(
    kind: kind,
    beaconCreateCase: fakeBeaconCreateCase(),
    effects: FakeUiEffectPort(),
  ),
  forwardCubitFactory: (beaconId) =>
      ForwardCubit(beaconId: beaconId, embedded: true),
);

void main() {
  testWidgets(
    'dragging inside the circle (off the handle) moves the draft centre',
    (tester) async {
      final cubit = await _loadCubit();
      final composer = _buildComposerCubit();
      addTearDown(cubit.close);
      addTearDown(composer.close);

      const size = Size(1200, 900);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: size),
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ConstellationCubit>.value(value: cubit),
                  BlocProvider<ConstellationComposerCubit>.value(
                    value: composer,
                  ),
                  BlocProvider<GraphPersonContextCubit>(
                    create: (_) => _StubContextCubit(),
                  ),
                  BlocProvider<ScreenCubit>(
                    create: (_) => ScreenCubit(FakeUiEffectPort()),
                  ),
                ],
                child: ConstellationBody(
                  legendExpanded: false,
                  onToggleLegend: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      composer.start(
        BeaconKind.post,
        cubit.graphController.viewportLocalToScene(const Offset(600, 450)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final controller = cubit.graphController;
      final before = composer.selection.center;
      final handleOrigin = tester.getTopLeft(
        find.byType(ConstellationComposerHandle),
      );
      // A point just off-centre, perpendicular to the handle (which sits on
      // the horizontal rim) — inside the circle, clear of the handle's own
      // small hit area.
      final localStart = controller.sceneToViewportLocal(before) +
          const Offset(0, 6);
      final localEnd = localStart + const Offset(0, 25);

      final gesture = await tester.startGesture(handleOrigin + localStart);
      await tester.pump();
      await gesture.moveTo(handleOrigin + localEnd);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(composer.selection.center, isNot(before));
      expect(
        composer.selection.center,
        controller.viewportLocalToScene(localEnd),
      );
    },
  );

  testWidgets(
    'dragging the rim handle still resizes the radius, not the centre',
    (tester) async {
      final cubit = await _loadCubit();
      final composer = _buildComposerCubit();
      addTearDown(cubit.close);
      addTearDown(composer.close);

      const size = Size(1200, 900);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: size),
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ConstellationCubit>.value(value: cubit),
                  BlocProvider<ConstellationComposerCubit>.value(
                    value: composer,
                  ),
                  BlocProvider<GraphPersonContextCubit>(
                    create: (_) => _StubContextCubit(),
                  ),
                  BlocProvider<ScreenCubit>(
                    create: (_) => ScreenCubit(FakeUiEffectPort()),
                  ),
                ],
                child: ConstellationBody(
                  legendExpanded: false,
                  onToggleLegend: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      composer.start(
        BeaconKind.post,
        cubit.graphController.viewportLocalToScene(const Offset(600, 450)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final beforeCentre = composer.selection.center;
      final beforeRadius = composer.selection.radius;
      final handleFinder = find.byType(ConstellationComposerHandle);
      final handleOrigin = tester.getTopLeft(handleFinder);
      // The handle's own visual rect, placed by `_handleAt`.
      final handleBox = tester
          .widgetList<Positioned>(
            find.descendant(
              of: handleFinder,
              matching: find.byType(Positioned),
            ),
          )
          .first;
      final handleLocal = Offset(
        handleBox.left! + handleBox.width! / 2,
        handleBox.top! + handleBox.height! / 2,
      );

      final gesture = await tester.startGesture(handleOrigin + handleLocal);
      await tester.pump();
      await gesture.moveTo(handleOrigin + handleLocal + const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(composer.selection.center, beforeCentre);
      expect(composer.selection.radius, isNot(beforeRadius));
    },
  );
}
