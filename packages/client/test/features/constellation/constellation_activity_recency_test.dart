import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_filter_bar.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';

final _asOf = DateTime.utc(2026, 6, 10, 12);
const _author = 'peer-author';
const _egoProfile = Profile(id: 'ego', displayName: 'Ego');

ConstellationRequest _authorRequest(String id, Duration ago) => ConstellationRequest(
  id: id,
  authorId: _author,
  title: 'Request $id',
  status: 0,
  lastActivityAt: _asOf.subtract(ago),
);

ConstellationField _fieldWithAuthorRequests(List<ConstellationRequest> requests) {
  return ConstellationField(
    loadedAt: _asOf,
    context: 'ctx',
    peers: const [
      ConstellationPerson(id: _author, displayName: 'Author'),
      ConstellationPerson(id: 'ego', displayName: 'Ego'),
    ],
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: _author, tier: 1),
    ],
    requests: requests,
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision.zero,
      anchors: const [],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

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

Future<ConstellationCubit> _loadCubit(ConstellationField field) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    ).store,
    viewer: _egoProfile,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  cubit.updateLabelBudgetContext(
    viewport: const Size(375, 667),
    textScaleFactor: 1,
  );
  return cubit;
}

void main() {
  group('activity recency composition', () {
    test('shows three newest request labels and +2 overflow for five', () {
      final requests = [
        _authorRequest('r-old-1', const Duration(days: 50)),
        _authorRequest('r-old-2', const Duration(days: 40)),
        _authorRequest('r-new-1', const Duration(days: 1)),
        _authorRequest('r-new-2', const Duration(days: 2)),
        _authorRequest('r-new-3', const Duration(days: 3)),
      ];
      final composed = composeConstellationPresentation(
        viewerId: 'ego',
        field: _fieldWithAuthorRequests(requests),
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          activityRecency: ActivityRecencyFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: _asOf,
        labelBudget: (perPerson: 3, total: 150),
      );

      final drawnAutomatic = [
        for (final id in composed.labelPlan.layoutRequestsByAuthor[_author]!)
          if (composed.labelPlan.drawnRequestIds.contains(id)) id,
      ];
      expect(drawnAutomatic, ['r-new-1', 'r-new-2', 'r-new-3']);
      expect(composed.labelPlan.overflowHiddenCountByAuthor[_author], 2);
    });

    test('7-day activity filter hides stale automatic request, keeps pinned', () {
      final stale = _authorRequest('stale', const Duration(days: 10));
      final recent = _authorRequest('recent', const Duration(days: 1));
      final pinnedOld = ConstellationRequest(
        id: 'pinned-old',
        authorId: _author,
        title: 'Pinned old',
        status: 0,
        pinState: 'pinned',
        lastActivityAt: _asOf.subtract(const Duration(days: 30)),
      );
      final field = ConstellationField(
        loadedAt: _asOf,
        context: 'ctx',
        peers: const [
          ConstellationPerson(id: _author, displayName: 'Author'),
          ConstellationPerson(id: 'ego', displayName: 'Ego'),
        ],
        edges: const [
          ConstellationTrustEdgeEntity(src: 'ego', dst: _author, tier: 1),
        ],
        requests: [stale, recent],
        anchorProjection: ConstellationAnchorProjection(
          revision: ConstellationAnchorRevision.zero,
          anchors: [
            ConstellationAnchor(
              target: ConstellationAnchorTarget.beacon('pinned-old'),
              position: const ConstellationAnchorPosition(
                xUnits: 1,
                yUnits: 1,
                coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
              ),
              revision: ConstellationAnchorRevision.zero,
              placedAt: _asOf,
            ),
          ],
          pinnedPeers: const [],
          pinnedRequests: [pinnedOld],
          supportPeers: const [],
          supportEdges: const [],
          serverFilteredBeaconIds: const [],
          serverFilteredBeaconCount: 0,
        ),
      );

      final composed = composeConstellationPresentation(
        viewerId: 'ego',
        field: field,
        localFilters: (
          capabilitySlugs: const {},
          location: LocationFilter.any,
          timing: const TimingFilterAny(),
          activityRecency: activityRecencyFilterWithinDays(7),
          includeUnspecified: true,
        ),
        asOfUtc: _asOf,
        labelBudget: (perPerson: 10, total: 150),
      );

      expect(composed.labelPlan.drawnRequestIds, contains('recent'));
      expect(composed.labelPlan.drawnRequestIds, isNot(contains('stale')));
      expect(composed.labelPlan.drawnRequestIds, contains('pinned-old'));
    });
  });

  group('activity recency list + filter sheet', () {
    testWidgets('Happening heading and list order (375×667 RU)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final requests = [
        _authorRequest('r-old', const Duration(days: 20)),
        _authorRequest('r-new', const Duration(days: 1)),
      ];
      final cubit = await _loadCubit(_fieldWithAuthorRequests(requests));
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(375, 667)),
            child: TenturaResponsiveScope(
              child: BlocProvider<ConstellationCubit>.value(
                value: cubit,
                child: const ConstellationFilterBar(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Когда'), findsOneWidget);
      expect(find.text('Активность за последние'), findsOneWidget);

      cubit.setFilterActivityRecency(activityRecencyFilterWithinDays(7));
      await tester.pump();

      final listed = cubit.discoverableRequestsForPerson(_author);
      expect(listed.map((r) => r.id).toList(), ['r-new']);
    });
  });
}
