import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

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
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

Future<ConstellationCubit> _loadCubit({bool withPost = false}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          posts: withPost
              ? [
                  ConstellationPost(
                    id: 'post-a',
                    authorId: 'a',
                    rootExcerpt: 'Selected Post excerpt',
                    lastActivityAt: DateTime.utc(2026, 9, 9),
                  ),
                ]
              : [],
          context: '',
          peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: const [
            ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: const [
            ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
              needs: ['tools'],
            ),
          ],
        ),
      ),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationScreenLayoutTest'),
    ),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required Size size,
  ConstellationComposerCubit? composer,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              if (composer != null)
                BlocProvider<ConstellationComposerCubit>.value(value: composer),
              BlocProvider(create: (_) => HomeTabReselectCubit()),
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
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final size in [const Size(400, 800), const Size(1200, 800)]) {
    testWidgets(
      'selecting a Post shows and closes its map context card at $size',
      (tester) async {
        final cubit = await _loadCubit(withPost: true);
        addTearDown(cubit.close);
        await _pumpScreen(tester, cubit: cubit, size: size);
        cubit.selectRequest('post-a');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('constellation.post_preview')),
          findsOneWidget,
        );
        expect(find.text('Selected Post excerpt'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(cubit.state.selectedRequestId, isNull);
        expect(
          find.byKey(const Key('constellation.post_preview')),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'map composer drives people-only scene and survives an overlaid route',
    (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final composer = ConstellationComposerCubit(
        positions: const {'a': Offset(350, 350)},
        eligible: const {'a'},
        createCubitFactory: (kind) => BeaconCreateCubit(
          kind: kind,
          beaconCreateCase: fakeBeaconCreateCase(),
          effects: FakeUiEffectPort(),
        ),
        forwardCubitFactory: (id) =>
            ForwardCubit(beaconId: id, effects: FakeUiEffectPort()),
        personName: (_) => 'Ann',
      );
      addTearDown(composer.close);
      await _pumpScreen(
        tester,
        cubit: cubit,
        size: const Size(1280, 800),
        composer: composer,
      );
      composer.start(BeaconKind.post, const Offset(400, 400));
      composer.setRadius(5);
      await tester.pumpAndSettle();
      expect(cubit.state.placementPhase, ConstellationPlacementPhase.composing);
      expect(cubit.graphController.nodePayloadForId('fr:req-a'), isNull);
      final person = cubit.graphController.nodePayloadForId('fp:a')!;
      cubit.selectMapNode(person);
      expect(
        composer.selection.selected,
        isEmpty,
        reason: 'manual mode is off',
      );
      composer.toggleManualSelection();
      cubit.selectMapNode(person);
      await tester.pumpAndSettle();
      expect(composer.selection.manualAdded, {'a'});
      expect(
        cubit.graphController.edges.map((e) => e.semanticId),
        contains('fd:draft->fp:a#draftRecipient'),
      );
      final selectionBefore = composer.selection;
      final navigator = Navigator.of(
        tester.element(find.byType(ConstellationScreen)),
      );
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('full form')),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(composer.selection, same(selectionBefore));
      expect(cubit.state.placementPhase, ConstellationPlacementPhase.composing);
      expect(
        cubit.graphController.edges.map((e) => e.semanticId),
        contains('fd:draft->fp:a#draftRecipient'),
      );
      cubit.selectMapNode(person);
      await tester.pumpAndSettle();
      expect(composer.selection.selected, isEmpty);
      await tester.tap(
        find.byKey(const Key('constellation.app_bar.cancel_composer')),
      );
      await tester.pumpAndSettle();
      expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
      expect(cubit.graphController.nodePayloadForId('fr:req-a'), isNotNull);
    },
  );
  group('ConstellationScreen desktop centering', () {
    testWidgets(
      'app bar sits in the centered column while the graph canvas is full-bleed',
      (tester) async {
        const size = Size(1280, 800);
        const contentMaxWidth = 720.0;
        final cubit = await _loadCubit();
        await _pumpScreen(tester, cubit: cubit, size: size);

        final bodyRect = tester.getRect(find.byType(ConstellationBody));
        expect(bodyRect.width, closeTo(size.width, 1));
        expect(bodyRect.left, closeTo(0, 1));

        final columnLeft = (size.width - contentMaxWidth) / 2;
        final columnRight = columnLeft + contentMaxWidth;
        final toggle = find.byKey(const Key('constellation.app_bar.view_mode'));
        final filters = find.byKey(const Key('constellation.app_bar.filters'));
        expect(
          tester.getRect(toggle).right,
          lessThanOrEqualTo(columnRight + 1),
        );
        expect(
          tester.getRect(toggle).left,
          greaterThanOrEqualTo(columnLeft - 1),
        );
        expect(
          tester.getRect(filters).right,
          lessThanOrEqualTo(columnRight + 1),
        );
        expect(
          tester.getRect(filters).left,
          greaterThanOrEqualTo(columnLeft - 1),
        );
        await cubit.close();
      },
    );

    testWidgets('compact keeps the graph full-bleed', (tester) async {
      const size = Size(390, 800);
      final cubit = await _loadCubit();
      await _pumpScreen(tester, cubit: cubit, size: size);

      final bodyRect = tester.getRect(find.byType(ConstellationBody));
      expect(bodyRect.width, closeTo(size.width, 1));
      expect(bodyRect.left, closeTo(0, 1));
      await cubit.close();
    });
  });
}
