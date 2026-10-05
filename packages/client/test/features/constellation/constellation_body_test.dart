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
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';
import 'package:flutter/gestures.dart';

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {
    emit(
      state.copyWith(
        selectedProfile: profile,
        dismissedFocusId: null,
      ),
    );
  }

  @override
  void dismiss() {
    final id = state.selectedProfile?.id;
    if (id == null || id.isEmpty) {
      return;
    }
    emit(state.copyWith(dismissedFocusId: id));
  }

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {
    emit(const GraphPersonContextState());
  }
}

const _ego = Profile(id: 'ego', displayName: 'Ego');

ConstellationEdgeKind? _edgeKindBetween(
  ConstellationCubit cubit,
  String srcId,
  String dstId,
) {
  for (final entry in cubit.edgeKinds.entries) {
    if (entry.key.contains(srcId) && entry.key.contains(dstId)) {
      return entry.value;
    }
  }
  return null;
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

ConstellationFieldCase _caseForField(ConstellationField field) =>
    ConstellationFieldCase(
      _StubRepository(field),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationBodyTest'),
    );

Future<ConstellationCubit> _loadCubit(ConstellationField field) async {
  final cubit = ConstellationCubit(
    case_: _caseForField(field),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Future<FakeUiEffectPort> _pumpBody(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Size size = const Size(1200, 900),
  FakeUiEffectPort? effects,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fx = effects ?? FakeUiEffectPort();
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
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(fx),
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
  return fx;
}

Finder _requestNodeFinder() =>
    find.byKey(TestIds.key(TestIds.graphNode('req-a')));

Finder _personNodeFinder(String personId) =>
    find.byKey(TestIds.key(TestIds.graphNode(personId)));

final class _CountingContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _CountingContextCubit() : super(const GraphPersonContextState());

  int selectProfileCalls = 0;

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {
    selectProfileCalls++;
    emit(state.copyWith(selectedProfile: profile));
  }

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {
    emit(const GraphPersonContextState());
  }
}

Future<void> _pumpWithContext(
  WidgetTester tester,
  ConstellationCubit cubit,
  GraphPersonContextCubit contextCubit, {
  Locale locale = const Locale('en'),
}) async {
  const size = Size(375, 547);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<GraphPersonContextCubit>.value(
                  value: contextCubit,
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
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  group('Constellation graph edges', () {
    test(
      'ring holder gets ego stub only, not a keep-tree parent edge',
      () async {
        final cubit = await _loadCubit(
          ConstellationField(
            loadedAt: DateTime.utc(2026, 9, 9),
            context: '',
            peers: [
              const ConstellationPerson(id: 'a'),
              const ConstellationPerson(id: 'h'),
            ],
            edges: [
              const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
              const ConstellationTrustEdgeEntity(
                src: 'a',
                dst: 'ghost',
                tier: 1,
              ),
              const ConstellationTrustEdgeEntity(
                src: 'ghost',
                dst: 'h',
                tier: 1,
              ),
            ],
            requests: [
              const ConstellationRequest(
                id: 'req-h',
                authorId: 'h',
                title: 'Help',
                status: 0,
              ),
            ],
          ),
        );
        cubit.selectPerson('h');

        expect(
          _edgeKindBetween(cubit, 'ego', 'h'),
          ConstellationEdgeKind.ringStub,
        );
        expect(
          cubit.edgeKinds.entries.where(
            (entry) =>
                entry.key.endsWith('\0h') &&
                entry.value != ConstellationEdgeKind.ringStub,
          ),
          isEmpty,
        );
        expect(cubit.edgeKinds.containsKey('a\0h'), isFalse);
      },
    );

    test(
      'tier-2 keep-tree edge is classified separately from tier-1',
      () async {
        final cubit = await _loadCubit(
          ConstellationField(
            loadedAt: DateTime.utc(2026, 9, 9),
            context: '',
            peers: [
              const ConstellationPerson(id: 'a'),
              const ConstellationPerson(id: 'b'),
            ],
            edges: [
              const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
              const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 2),
            ],
            requests: [
              const ConstellationRequest(
                id: 'req-b',
                authorId: 'b',
                title: 'Need help',
                status: 0,
              ),
            ],
          ),
        );
        cubit.selectPerson('b');

        expect(
          _edgeKindBetween(cubit, 'ego', 'a'),
          ConstellationEdgeKind.tier1Path,
        );
        expect(
          _edgeKindBetween(cubit, 'a', 'b'),
          ConstellationEdgeKind.tier2Path,
        );
      },
    );

    test('ego edges are drawn only toward the selected person', () async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [
            const ConstellationPerson(id: 'a'),
            const ConstellationPerson(id: 'b'),
            const ConstellationPerson(id: 'c'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'c', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-b',
              authorId: 'b',
              title: 'Need help',
              status: 0,
            ),
            const ConstellationRequest(
              id: 'req-c',
              authorId: 'c',
              title: 'Need help too',
              status: 0,
            ),
          ],
        ),
      );
      addTearDown(cubit.close);
      Set<String> egoEdgeIds() => {
        for (final edge in cubit.graphController.edges)
          if (edge.source.id == 'ego') edge.semanticId,
      };

      expect(egoEdgeIds(), isEmpty);
      expect(_edgeKindBetween(cubit, 'a', 'b'), ConstellationEdgeKind.tier1Path);

      cubit.selectPerson('b');
      expect(egoEdgeIds(), {'fp:ego->fp:a#tier1Path'});

      cubit.selectRequest('req-c');
      expect(egoEdgeIds(), {'fp:ego->fp:c#tier1Path'});

      cubit.selectRequest(null);
      expect(egoEdgeIds(), isEmpty);
    });

    test('attachment edge kind differs from path stroke kinds', () async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );

      expect(
        _edgeKindBetween(cubit, 'a', 'req-a'),
        ConstellationEdgeKind.attachment,
      );
      expect(
        _edgeKindBetween(cubit, 'a', 'req-a'),
        isNot(
          anyOf(
            ConstellationEdgeKind.tier1Path,
            ConstellationEdgeKind.tier2Path,
          ),
        ),
      );
    });
  });

  group('Constellation pin badge zoom LOD', () {
    List<ConstellationAnchor> pinnedAnchors() => [
      ConstellationAnchor(
        target: ConstellationAnchorTarget.beacon('req-in-2'),
        position: const ConstellationAnchorPosition(
          xUnits: -3,
          yUnits: 4,
          coordinateSpaceVersion: 1,
        ),
        revision: ConstellationAnchorRevision(BigInt.one),
        placedAt: DateTime.utc(2026, 9, 9, 12),
      ),
    ];

    Finder inNode(String nodeId, String key) => find.descendant(
      of: find
          .ancestor(
            of: find.byKey(TestIds.key(TestIds.graphNode(nodeId))),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Stack &&
                  widget.clipBehavior == Clip.none &&
                  widget.alignment == Alignment.center,
            ),
          )
          .first,
      matching: find.byKey(TestIds.key(key)),
    );

    Finder inRequestNode(String key) => inNode('req-in-2', key);

    Future<void> zoomUntil(
      WidgetTester tester,
      ConstellationCubit cubit,
      double factor,
      bool Function(double scale) done,
    ) async {
      for (var i = 0; i < 20 && !done(cubit.graphController.cameraScale); i++) {
        cubit.graphController.zoomBy(factor);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(done(cubit.graphController.cameraScale), isTrue);
    }

    testWidgets('pin hides at overview zoom and returns at normal zoom', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit(
        field: constellationReferenceField(anchors: pinnedAnchors()),
      );
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      final pin = inRequestNode(TestIds.constellationPinMarker);
      final status = inRequestNode(TestIds.constellationRequestStatusMarker);
      expect(
        cubit.graphController.cameraScale,
        greaterThanOrEqualTo(kConstellationNormalDetailScale),
      );
      expect(pin, findsOneWidget);
      expect(status, findsOneWidget);

      await zoomUntil(
        tester,
        cubit,
        0.8,
        (s) => s < kConstellationOverviewDetailScale,
      );
      expect(pin, findsNothing);
      expect(status, findsOneWidget);

      await zoomUntil(
        tester,
        cubit,
        1.25,
        (s) => s >= kConstellationNormalDetailScale,
      );
      expect(pin, findsOneWidget);
      expect(status, findsOneWidget);
    });

    testWidgets(
      'node recreated inside the hysteresis band keeps shared detail',
      (
        tester,
      ) async {
        final cubit = await loadReferenceCubit(
          field: constellationReferenceField(
            anchors: [
              ...pinnedAnchors(),
              ConstellationAnchor(
                target: ConstellationAnchorTarget.person('am'),
                position: const ConstellationAnchorPosition(
                  xUnits: 4,
                  yUnits: -2,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.one),
                placedAt: DateTime.utc(2026, 9, 9, 12),
              ),
            ],
          ),
        );
        addTearDown(cubit.close);
        await pumpConstellationBody(tester, cubit);
        await tester.pumpAndSettle();

        final requestPin = inRequestNode(TestIds.constellationPinMarker);
        final personPin = inNode('am', TestIds.constellationPinMarker);
        expect(requestPin, findsOneWidget);
        expect(personPin, findsOneWidget);

        await zoomUntil(
          tester,
          cubit,
          0.8,
          (s) => s < kConstellationOverviewDetailScale,
        );
        expect(requestPin, findsNothing);
        expect(personPin, findsNothing);

        bool inBand(double s) =>
            s >= kConstellationOverviewDetailScale &&
            s < kConstellationNormalDetailScale;
        await zoomUntil(tester, cubit, 1.02, inBand);
        expect(requestPin, findsNothing);
        expect(personPin, findsNothing);

        // Filter the request out so its node widget is destroyed, then restore.
        cubit
          ..setFilterIncludeUnspecified(false)
          ..setFilterCapabilitySlugs({'tools'});
        await tester.pump();
        expect(
          find.byKey(TestIds.key(TestIds.graphNode('req-in-2'))),
          findsNothing,
        );
        expect(
          find.byKey(TestIds.key(TestIds.graphNode('am'))),
          findsOneWidget,
        );

        await cubit.clearFilters();
        await tester.pumpAndSettle();
        expect(inBand(cubit.graphController.cameraScale), isTrue);
        expect(
          find.byKey(TestIds.key(TestIds.graphNode('req-in-2'))),
          findsOneWidget,
        );
        expect(personPin, findsNothing);
        expect(requestPin, findsNothing);
      },
    );
  });

  group('ConstellationBody', () {
    testWidgets('renders ring holder node without tier-2 edge labels', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [
            const ConstellationPerson(id: 'a'),
            const ConstellationPerson(id: 'b'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 2),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-b',
              authorId: 'b',
              title: 'Need help',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit);

      expect(find.byType(GraphNodeWidget), findsWidgets);
      expect(find.textContaining('weight'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('derived'), findsNothing);
    });

    testWidgets('request attachment uses request node, not path styling', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit);

      expect(find.text('Need tools'), findsOneWidget);
      expect(
        _edgeKindBetween(cubit, 'a', 'req-a'),
        ConstellationEdgeKind.attachment,
      );
    });

    testWidgets('a Post renders as a node, not just an edge', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          posts: [
            ConstellationPost(
              id: 'post-a',
              authorId: 'a',
              rootExcerpt: 'Anyone free Saturday?',
              lastActivityAt: DateTime.utc(2026, 9, 9),
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit);

      expect(
        find.byKey(TestIds.key(TestIds.graphNode('post-a'))),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(
        _edgeKindBetween(cubit, 'a', 'post-a'),
        ConstellationEdgeKind.attachment,
      );
    });

    testWidgets('tapping a Post node selects it', (tester) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          posts: [
            ConstellationPost(
              id: 'post-a',
              authorId: 'a',
              rootExcerpt: 'Anyone free Saturday?',
              lastActivityAt: DateTime.utc(2026, 9, 9),
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit);

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('post-a'))));
      await tester.pump();

      expect(cubit.state.selectedRequestId, 'post-a');
    });

    testWidgets('tapping a request node opens the preview panel', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit);

      await tester.tap(_requestNodeFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('constellation.request_preview')),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Need tools'), findsWidgets);
      expect(find.text('By Ann'), findsOneWidget);
    });

    testWidgets('dismiss and re-tap reopens the request preview panel', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit);

      await tester.tap(_requestNodeFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('constellation.request_preview')),
        findsOneWidget,
      );

      final close = find.descendant(
        of: find.byKey(const Key('constellation.request_preview')),
        matching: find.byIcon(Icons.close),
      );
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pump();
      expect(
        find.byKey(const Key('constellation.request_preview')),
        findsNothing,
      );
      expect(cubit.state.selectedRequestId, isNull);

      await tester.tap(_requestNodeFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('constellation.request_preview')),
        findsOneWidget,
      );
    });

    testWidgets('wide 900x600 person panel uses token rail width', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit, size: const Size(900, 600));

      cubit.selectPerson('a');
      await tester.pump();

      final panel = find.byKey(TestIds.key(TestIds.graphPersonContextPanel));
      expect(panel, findsOneWidget);
      expect(tester.getSize(panel).width, 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide 900x600 request preview uses token rail width', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit, size: const Size(900, 600));

      cubit.selectRequest('req-a');
      await tester.pump();

      final panel = find.byKey(const Key('constellation.request_preview'));
      expect(panel, findsOneWidget);
      expect(tester.getSize(panel).width, 320);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a person node opens the discoverable-requests panel', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpBody(tester, cubit);

      await tester.tap(_personNodeFinder('a'));
      await tester.pump();

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        findsOneWidget,
      );
      expect(find.text('Ann'), findsWidgets);
      expect(find.textContaining('Show 1 request'), findsOneWidget);
    });

    testWidgets(
      'compact person panel with pin control does not overflow',
      (tester) async {
        final cubit = await _loadCubit(
          ConstellationField(
            loadedAt: DateTime.utc(2026, 9, 9),
            context: '',
            peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
            edges: [
              const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            ],
            requests: [
              const ConstellationRequest(
                id: 'req-a',
                authorId: 'a',
                title: 'Need tools',
                status: 0,
              ),
            ],
          ),
        );

        // iPhone SE: compact maxHeight is 667 * 0.42 ≈ 280.
        await _pumpBody(tester, cubit, size: const Size(375, 667));

        await tester.tap(_personNodeFinder('a'));
        await tester.pump();

        final panel = find.byKey(TestIds.key(TestIds.graphPersonContextPanel));
        final pin = find.byKey(TestIds.key(TestIds.constellationPinTarget));
        expect(panel, findsOneWidget);
        expect(pin, findsOneWidget);

        final panelRect = tester.getRect(panel);
        final pinRect = tester.getRect(pin);
        expect(
          panelRect.inflate(0.5).contains(pinRect.topLeft),
          isTrue,
          reason:
              'Pin control must sit on the person-card surface, not over the graph',
        );
        expect(
          panelRect.inflate(0.5).contains(pinRect.bottomRight),
          isTrue,
          reason:
              'Pin control must sit on the person-card surface, not over the graph',
        );
        expect(panelRect.height, lessThanOrEqualTo(667 * 0.42 + 1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping Profile on the person panel emits profile navigation',
      (tester) async {
        final cubit = await _loadCubit(
          ConstellationField(
            loadedAt: DateTime.utc(2026, 9, 9),
            context: '',
            peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
            edges: [
              const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            ],
            requests: [
              const ConstellationRequest(
                id: 'req-a',
                authorId: 'a',
                title: 'Need tools',
                status: 0,
              ),
            ],
          ),
        );

        final effects = await _pumpBody(
          tester,
          cubit,
          size: const Size(1200, 900),
        );

        await tester.tap(_personNodeFinder('a'));
        await tester.pump();

        final profileButton = find.byKey(
          TestIds.key(TestIds.graphPersonContextViewProfile),
        );
        expect(profileButton, findsOneWidget);
        await tester.tap(profileButton);
        await tester.pump();

        expect(
          effects.emitted.whereType<NavigatePush>().map((e) => e.path).toList(),
          ['$kPathProfileView/a'],
        );
      },
    );
  });

  // --- merged from constellation_node_tap_dispatch_test.dart ---

  group('Constellation node tap dispatch (R06)', () {
    testWidgets('single pointer dispatch calls selectProfile once', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      final contextCubit = _CountingContextCubit();
      addTearDown(contextCubit.close);

      await _pumpWithContext(tester, cubit, contextCubit);

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('am'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(contextCubit.selectProfileCalls, 1);
      expect(cubit.state.selectedPersonId, 'am');
    });

    testWidgets('request node tap opens preview panel', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit, locale: const Locale('en'));

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('req-ego-1'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.selectedRequestId, 'req-ego-1');
      expect(
        find.byKey(const Key('constellation.request_preview')),
        findsOneWidget,
      );
    });

    testWidgets('pan starting on label moves camera not placement', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit, locale: const Locale('en'));
      final label = find.byKey(
        const ValueKey('constellation.label.fr:req-ego-1'),
      );
      final rect = tester.getRect(label);
      final revisionBefore = cubit.graphController.cameraRevision.value;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(rect.center);
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        cubit.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
      expect(
        cubit.graphController.cameraRevision.value,
        greaterThan(revisionBefore),
      );
    });

    test(
      'later placedAt anchor sorts above earlier at same position (D22)',
      () {
        const shared = ConstellationAnchorPosition(
          xUnits: 4,
          yUnits: -2,
          coordinateSpaceVersion: 1,
        );
        final earlier = ConstellationAnchor(
          target: ConstellationAnchorTarget.beacon('req-in-1'),
          position: shared,
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: DateTime.utc(2026, 1, 1),
        );
        final later = ConstellationAnchor(
          target: ConstellationAnchorTarget.beacon('req-in-2'),
          position: shared,
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: DateTime.utc(2026, 6, 1),
        );
        expect(
          ConstellationAnchor.comparePaintOrder(earlier, later),
          lessThan(0),
        );
      },
    );

    testWidgets('combined semantics: one node label with status', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(
        tester,
        cubit,
        locale: const Locale('en'),
      );

      final nodeFinder = find.byKey(TestIds.key(TestIds.graphNode('req-sm-1')));
      final semantics = tester.getSemantics(nodeFinder);
      expect(semantics.label, contains('I need documents'));
      expect(semantics.label, contains('Open'));
      expect(
        find.bySemanticsLabel(RegExp(r'I need documents')),
        findsOneWidget,
      );
    });

    testWidgets('placement drag gates camera until cancel', (tester) async {
      final cubit = await loadReferenceCubit(
        field: constellationReferenceField(
          anchors: _pinnedReferenceAnchors(),
        ),
      );
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);

      cubit.beginDragExisting(
        target: ConstellationAnchorTarget.person('am'),
      );
      expect(
        cubit.state.placementPhase,
        ConstellationPlacementPhase.draggingExisting,
      );
      expect(cubit.graphController.isCameraGated, isTrue);

      cubit.cancelPlacement();
      expect(cubit.graphController.isCameraGated, isFalse);
      expect(
        cubit.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
    });
  });
}

List<ConstellationAnchor> _pinnedReferenceAnchors() {
  final loadedAt = DateTime.utc(2026, 9, 9, 12);
  final revision = ConstellationAnchorRevision(BigInt.one);
  return [
    ConstellationAnchor(
      target: ConstellationAnchorTarget.person('am'),
      position: const ConstellationAnchorPosition(
        xUnits: 4,
        yUnits: -2,
        coordinateSpaceVersion: 1,
      ),
      revision: revision,
      placedAt: loadedAt,
    ),
  ];
}
