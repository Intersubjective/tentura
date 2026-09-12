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
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

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
  void clearSelection() {
    emit(const GraphPersonContextState());
  }
}

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
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

Future<void> _pumpBody(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
}

Finder _requestNodeFinder() => find.byKey(TestIds.key(TestIds.graphNode('req-a')));

Finder _personNodeFinder(String personId) =>
    find.byKey(TestIds.key(TestIds.graphNode(personId)));

void main() {
  group('Constellation graph edges', () {
    test('ring holder gets ego stub only, not a keep-tree parent edge', () async {
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
            const ConstellationTrustEdgeEntity(src: 'a', dst: 'ghost', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'ghost', dst: 'h', tier: 1),
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

      expect(cubit.edgeKinds['ego\0h'], ConstellationEdgeKind.ringStub);
      expect(
        cubit.edgeKinds.entries.where(
          (entry) =>
              entry.key.endsWith('\0h') &&
              entry.value != ConstellationEdgeKind.ringStub,
        ),
        isEmpty,
      );
      expect(cubit.edgeKinds.containsKey('a\0h'), isFalse);
    });

    test('tier-2 keep-tree edge is classified separately from tier-1', () async {
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

      expect(cubit.edgeKinds['ego\0a'], ConstellationEdgeKind.tier1Path);
      expect(cubit.edgeKinds['a\0b'], ConstellationEdgeKind.tier2Path);
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

      expect(cubit.edgeKinds['a\0req-a'], ConstellationEdgeKind.attachment);
      expect(
        cubit.edgeKinds['a\0req-a'],
        isNot(anyOf(
          ConstellationEdgeKind.tier1Path,
          ConstellationEdgeKind.tier2Path,
        )),
      );
    });
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
        cubit.edgeKinds['a\0req-a'],
        ConstellationEdgeKind.attachment,
      );
    });

    testWidgets('tapping a request node opens the preview sheet', (
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

      expect(find.byKey(const Key('constellation.request_preview')), findsOneWidget);
      expect(find.text('Need tools'), findsWidgets);
      expect(find.text('By Ann'), findsOneWidget);
    });

    testWidgets('dismiss and re-tap reopens the request preview sheet', (
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
      expect(find.byKey(const Key('constellation.request_preview')), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('constellation.request_preview')), findsNothing);
      expect(cubit.state.selectedRequestId, isNull);

      await tester.tap(_requestNodeFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('constellation.request_preview')), findsOneWidget);
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
          reason: 'Pin control must sit on the person-card surface, not over the graph',
        );
        expect(
          panelRect.inflate(0.5).contains(pinRect.bottomRight),
          isTrue,
          reason: 'Pin control must sit on the person-card surface, not over the graph',
        );
        expect(panelRect.height, lessThanOrEqualTo(667 * 0.42 + 1));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
