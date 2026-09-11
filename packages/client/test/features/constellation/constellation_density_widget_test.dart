import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_filter_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
      logger: Logger('ConstellationDensityWidgetTest'),
    );

Future<ConstellationCubit> _loadCubit(
  ConstellationField field, {
  Size viewport = const Size(1200, 900),
  double textScale = 1.0,
}) async {
  final cubit = ConstellationCubit(
    case_: _caseForField(field),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  cubit.updateLabelBudgetContext(
    viewport: viewport,
    textScaleFactor: textScale,
  );
  return cubit;
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required double width,
  required double textScale,
  List<Widget> extra = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: TenturaResponsiveScope(
          child: BlocProvider<ConstellationCubit>.value(
            value: cubit,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConstellationFieldNotices(),
                  const ConstellationEmptyFilterBanner(),
                  const ConstellationFilterBar(),
                  ...extra,
                  _AbsenceProbeList(cubit: cubit),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _absenceLabel(L10n l10n, ConstellationCubit cubit, String personId) {
  final absence = cubit.absenceForPerson(personId);
  return switch (absence) {
    ConstellationNodeAbsence.none => '',
    ConstellationNodeAbsence.filterHidden => l10n.constellationAbsenceFilterHidden,
    ConstellationNodeAbsence.spaceCollapsed =>
      l10n.constellationAbsenceSpaceCollapsed,
    ConstellationNodeAbsence.ring => cubit.peersCapped
        ? l10n.constellationAbsencePathNotShown
        : l10n.constellationAbsenceRing,
    ConstellationNodeAbsence.capDisplaced =>
      l10n.constellationAbsenceCapDisplaced,
    ConstellationNodeAbsence.ringBudgetOmitted =>
      l10n.constellationAbsenceRingBudgetOmitted,
  };
}

String _requestAbsenceLabel(L10n l10n, ConstellationCubit cubit, String id) {
  return switch (cubit.absenceForRequest(id)) {
    ConstellationNodeAbsence.none => '',
    ConstellationNodeAbsence.filterHidden =>
      l10n.constellationAbsenceFilterHidden,
    ConstellationNodeAbsence.spaceCollapsed =>
      l10n.constellationAbsenceSpaceCollapsed,
    _ => '',
  };
}

Map<String, Offset> _personPositions(ConstellationCubit cubit) {
  final resolved = cubit.state.resolvedField;
  if (resolved == null) {
    return const {};
  }
  final layout = computeConstellationLayout(
    egoId: cubit.viewerId,
    paths: resolved.paths,
    keptPeerIds: resolved.keptPeerIds,
    visibleRequestsByAuthor: cubit.layoutVisibleRequestsByAuthor,
    egoOwnRequestIds: cubit.layoutEgoOwnRequestIds,
  );
  return {
    for (final entry in layout.positions.entries)
      if (!entry.key.startsWith('req-'))
        entry.key: Offset(entry.value.x, entry.value.y),
  };
}

ConstellationField _baseField({
  bool peersCapped = false,
  bool requestsCapped = false,
  List<ConstellationRequest> requests = const [],
  List<ConstellationPerson> peers = const [],
  List<ConstellationTrustEdgeEntity> edges = const [],
}) {
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 9, 12),
    context: '',
    peers: peers,
    edges: edges,
    requests: requests,
    peersCapped: peersCapped,
    requestsCapped: requestsCapped,
  );
}

class _AbsenceProbeList extends StatelessWidget {
  const _AbsenceProbeList({required this.cubit});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final probes = <Widget>[];
    final field = cubit.state.field;
    if (field != null) {
      for (final peer in field.peers) {
        final label = _absenceLabel(l10n, cubit, peer.id);
        if (label.isNotEmpty) {
          probes.add(Text(label, key: Key('absence.person.${peer.id}')));
        }
      }
      for (final request in field.requests) {
        final label = _requestAbsenceLabel(l10n, cubit, request.id);
        if (label.isNotEmpty) {
          probes.add(Text(label, key: Key('absence.request.${request.id}')));
        }
      }
    }
    return Column(children: probes);
  }
}

void main() {
  group('Constellation density and filter widgets', () {
    testWidgets('compact and expanded layouts keep controls readable at text scales',
        (tester) async {
      for (final width in [390.0, 900.0]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          final cubit = await _loadCubit(
            _baseField(
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
                  needs: ['tools'],
                ),
              ],
            ),
            viewport: Size(width, 800),
            textScale: scale,
          );
          await _pumpHarness(
            tester,
            cubit: cubit,
            width: width,
            textScale: scale,
          );

          final filterBar = tester.getSize(
            find.byKey(const Key('constellation.filter_bar')),
          );
          expect(filterBar.width, greaterThan(0));
          expect(filterBar.height, greaterThan(44 * scale));

          final chip = tester.getSize(
            find.byKey(const Key('constellation.filter.location.any')),
          );
          expect(chip.height, greaterThanOrEqualTo(44));
        }
      }
    });

    testWidgets('changing filters does not move person anchors', (tester) async {
      final field = _baseField(
        peers: [
          const ConstellationPerson(id: 'a'),
          const ConstellationPerson(id: 'b'),
        ],
        edges: [
          const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
        ],
        requests: [
          const ConstellationRequest(
            id: 'req-a',
            authorId: 'a',
            title: 'Tools',
            status: 0,
            needs: ['tools'],
          ),
          const ConstellationRequest(
            id: 'req-b',
            authorId: 'b',
            title: 'Ride',
            status: 0,
            needs: ['ride'],
          ),
        ],
      );
      final cubit = await _loadCubit(field);
      final before = _personPositions(cubit);

      cubit.setFilterCapabilitySlugs({'tools'});
      final filtered = _personPositions(cubit);
      expect(filtered['a'], before['a']);
      expect(filtered['b'], before['b']);

      cubit.clearFilters();
      final restored = _personPositions(cubit);
      expect(restored['a'], before['a']);
      expect(restored['b'], before['b']);
    });

    testWidgets('four per-node absence states render distinctly', (tester) async {
      final prolific = List.generate(
        6,
        (i) => ConstellationRequest(
          id: 'req-p$i',
          authorId: 'p',
          title: 'Need $i',
          status: 0,
          needs: ['tools'],
        ),
      );
      final cubit = await _loadCubit(
        _baseField(
          peers: [
            const ConstellationPerson(id: 'p'),
            const ConstellationPerson(id: 'r'),
            const ConstellationPerson(id: 'd'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'p', tier: 1),
          ],
          requests: [
            ...prolific,
            const ConstellationRequest(
              id: 'req-hidden',
              authorId: 'p',
              title: 'Hidden ride',
              status: 0,
              needs: ['ride'],
            ),
            const ConstellationRequest(id: 'req-r', authorId: 'r', title: 'Ring', status: 0),
          ],
        ),
        viewport: const Size(400, 400),
        textScale: 1.0,
      );

      cubit.setFilterCapabilitySlugs({'tools'});
      cubit.droppedHolderIds = {'d'};
      cubit.emit(cubit.state.copyWith(capped: true));

      await _pumpHarness(tester, cubit: cubit, width: 400, textScale: 1.0);

      expect(
        find.text('Hidden by your filters'),
        findsOneWidget,
      );
      expect(find.text('Collapsed to save space'), findsWidgets);
      expect(
        find.text("Connection not explained within this map's path rules"),
        findsOneWidget,
      );
      expect(
        find.text('Known connection omitted by the map\'s render budget'),
        findsOneWidget,
      );
    });

    testWidgets('peersCapped alone shows path notice and fallback link', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peersCapped: true,
          peers: [
            const ConstellationPerson(id: 'r'),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-ego',
              authorId: 'ego',
              title: 'My need',
              status: 0,
              isMine: true,
            ),
            const ConstellationRequest(
              id: 'req-r',
              authorId: 'r',
              title: 'Ring need',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(
        find.text('Some connection paths are not shown'),
        findsOneWidget,
      );
      expect(find.textContaining('field too large'), findsNothing);
      expect(find.textContaining('requests are hidden'), findsNothing);
      expect(find.byKey(const Key('constellation.notice.fallback_list')), findsOneWidget);
      expect(cubit.displayedRequestIds, contains('req-ego'));
      expect(
        find.text('Path not shown'),
        findsOneWidget,
      );
      expect(
        find.text("Connection not explained within this map's path rules"),
        findsNothing,
      );
      expect(find.byKey(const Key('constellation.notice.requests_capped')), findsNothing);
      expect(
        find.byKey(const Key('constellation.notice.render_budget_capped')),
        findsNothing,
      );
    });

    testWidgets('requestsCapped alone shows distinct copy without path notice', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(requestsCapped: true),
      );
      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(find.text('Some requests could not be loaded'), findsOneWidget);
      expect(
        find.text('Some connection paths are not shown'),
        findsNothing,
      );
    });

    testWidgets('client render budget capped alone shows budget notice', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peers: [
            const ConstellationPerson(id: 'a'),
            const ConstellationPerson(id: 'b'),
            const ConstellationPerson(id: 'h'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'b', dst: 'h', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-h',
              authorId: 'h',
              title: 'Deep',
              status: 0,
            ),
          ],
        ),
      );
      cubit.droppedHolderIds = {'h'};
      cubit.emit(cubit.state.copyWith(capped: true));

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(
        find.text('Some people were omitted to keep the map readable'),
        findsOneWidget,
      );
      expect(
        find.text('Some connection paths are not shown'),
        findsNothing,
      );
      expect(
        find.text('Known connection omitted by the map\'s render budget'),
        findsOneWidget,
      );
    });

    testWidgets('ring-only budget omission stays ring classification', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peers: [
            const ConstellationPerson(id: 'a'),
            const ConstellationPerson(id: 'b'),
            const ConstellationPerson(id: 'h'),
            const ConstellationPerson(id: 'r'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'b', dst: 'h', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-h',
              authorId: 'h',
              title: 'Attributed',
              status: 0,
            ),
            const ConstellationRequest(
              id: 'req-r',
              authorId: 'r',
              title: 'Ring only',
              status: 0,
            ),
          ],
        ),
      );
      cubit.droppedHolderIds = const {};
      cubit.emit(
        cubit.state.copyWith(
          capped: true,
          keptPeerIds: {...cubit.state.keptPeerIds}..remove('r'),
        ),
      );

      expect(cubit.droppedHolderIds, isEmpty);
      expect(cubit.absenceForPerson('r'), ConstellationNodeAbsence.ringBudgetOmitted);
      expect(cubit.absenceForPerson('h'), isNot(ConstellationNodeAbsence.capDisplaced));

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);
      expect(
        find.text('This ring connection is not drawn on the map'),
        findsOneWidget,
      );
      expect(
        find.text('Known connection omitted by the map\'s render budget'),
        findsNothing,
      );
    });

    testWidgets('all three field-level caps show distinguishable notices', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peersCapped: true,
          requestsCapped: true,
        ),
      );
      cubit.emit(cubit.state.copyWith(capped: true));

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(
        find.text('Some connection paths are not shown'),
        findsOneWidget,
      );
      expect(find.text('Some requests could not be loaded'), findsOneWidget);
      expect(
        find.text('Some people were omitted to keep the map readable'),
        findsOneWidget,
      );
    });

    testWidgets('overflow group expands labelled satellites', (tester) async {
      final requests = List.generate(
        5,
        (i) => ConstellationRequest(
          id: 'req-$i',
          authorId: 'a',
          title: 'Need $i',
          status: 0,
        ),
      );
      final cubit = await _loadCubit(
        _baseField(
          peers: [const ConstellationPerson(id: 'a')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: requests,
        ),
        viewport: const Size(400, 400),
      );

      await _pumpHarness(
        tester,
        cubit: cubit,
        width: 400,
        textScale: 1.0,
        extra: [
          ConstellationOverflowGroup(authorId: 'a', hiddenCount: 3),
        ],
      );

      final control = find.byKey(const Key('constellation.overflow.a'));
      expect(control, findsOneWidget);
      final size = tester.getSize(control);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));

      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(cubit.isSatelliteOverflowExpanded('a'), isTrue);
      expect(cubit.displayedRequestIds.length, 5);
    });

    testWidgets('empty filtered result offers clear filters without despair copy', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Tools',
              status: 0,
              needs: ['tools'],
            ),
          ],
        ),
      );
      cubit.setFilterCapabilitySlugs({'ride'});
      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(find.text('No requests match these filters'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
      expect(find.textContaining('nobody'), findsNothing);
      expect(find.textContaining('no one needs'), findsNothing);

      await tester.tap(find.byKey(const Key('constellation.filter.clear')));
      await tester.pumpAndSettle();
      expect(cubit.hasActiveFilters, isFalse);
    });

    test('filters use snapshot loadedAt not wall clock', () async {
      final loadedAt = DateTime.utc(2026, 1, 1, 12);
      final cubit = await _loadCubit(
        _baseField(
          requests: [
            ConstellationRequest(
              id: 'req-future',
              authorId: 'a',
              title: 'Soon',
              status: 0,
              startAt: loadedAt.add(const Duration(days: 3)),
            ),
          ],
        ).copyWith(loadedAt: loadedAt),
      );
      cubit.setFilterTiming(timingFilterWithinDays(7));
      final visible = cubit.discoverableRequestsForPerson('a');
      expect(visible.map((r) => r.id), ['req-future']);
    });
  });
}
