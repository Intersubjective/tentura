import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';

const _ego = 'ego';

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

/// The people the real presentation path keeps on the map.
Future<Set<String>> _keptByCubit(
  ConstellationField field, {
  bool? semanticZoomEnabled,
}) async {
  final store = ConstellationStoreFixture(
    _StubRepository(field),
    accountId: _ego,
  ).store;
  final cubit = semanticZoomEnabled == null
      ? ConstellationCubit(
          case_: store,
          viewer: const Profile(id: _ego, displayName: 'Ego'),
        )
      : ConstellationCubit(
          case_: store,
          viewer: const Profile(id: _ego, displayName: 'Ego'),
          semanticZoomEnabled: semanticZoomEnabled,
        );
  addTearDown(cubit.close);
  if (cubit.state.status is! StateIsSuccess) {
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  }
  return cubit.state.keptPeerIds;
}

String _id(int i) => 'p${i.toString().padLeft(3, '0')}';

/// [count] indirect people (no direct contacts, no pins) who each author a
/// Request, so every one of them is a path holder charged against the render
/// budget.
ConstellationField _fieldOfIndirectPeople(int count) {
  final ids = [for (var i = 0; i < count; i++) _id(i)];
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 26),
    context: '',
    peers: [for (final id in ids) ConstellationPerson(id: id)],
    edges: [
      for (final id in ids)
        ConstellationTrustEdgeEntity(src: _ego, dst: id, tier: 1),
    ],
    requests: [
      for (final id in ids)
        ConstellationRequest(
          id: 'R$id',
          authorId: id,
          title: 'Request $id',
          status: 0,
        ),
    ],
  );
}

ConstellationComposedPresentation _compose(
  ConstellationField field, {
  required bool semanticZoomEnabled,
}) => composeConstellationPresentation(
  viewerId: _ego,
  field: field,
  localFilters: const (
    capabilitySlugs: {},
    location: LocationFilter.any,
    timing: TimingFilterAny(),
    includeUnspecified: true,
  ),
  asOfUtc: DateTime.utc(2026, 10, 26),
  labelBudget: (perPerson: 3, total: 150),
  semanticZoomEnabled: semanticZoomEnabled,
);

void main() {
  group('render peer cap by semantic zoom', () {
    test('semantic zoom on lets 400 people be drawn', () {
      expect(
        constellationRenderPeerCap(semanticZoomEnabled: true),
        400,
      );
    });

    test('semantic zoom off keeps the previous 120-person budget', () {
      expect(
        constellationRenderPeerCap(semanticZoomEnabled: false),
        120,
      );
    });

    test('the cap used by default follows the semantic zoom switch', () {
      expect(
        constellationRenderPeerCap(),
        constellationRenderPeerCap(
          semanticZoomEnabled: kFieldSemanticZoomEnabled,
        ),
      );
      expect(
        constellationRenderPeerCap(),
        kFieldSemanticZoomEnabled ? 400 : 120,
      );
    });
  });

  group('composition under the render cap', () {
    test('semantic zoom on composes 400 people and reports no cap', () {
      final composed = _compose(
        _fieldOfIndirectPeople(400),
        semanticZoomEnabled: true,
      );

      expect(composed.keptPeerIds, hasLength(400));
      expect(composed.renderBudgetCapped, isFalse);
    });

    test('semantic zoom on drops only the people beyond 400', () {
      final composed = _compose(
        _fieldOfIndirectPeople(450),
        semanticZoomEnabled: true,
      );

      expect(composed.keptPeerIds, hasLength(400));
      expect(composed.renderBudgetCapped, isTrue);
      // Without a priority signal the cap selects by id order.
      expect(composed.keptPeerIds, contains(_id(399)));
      expect(composed.keptPeerIds, isNot(contains(_id(400))));
    });

    test('semantic zoom off still draws at most 120 of 400 people', () {
      final composed = _compose(
        _fieldOfIndirectPeople(400),
        semanticZoomEnabled: false,
      );

      expect(composed.keptPeerIds, hasLength(120));
      expect(composed.renderBudgetCapped, isTrue);
    });
  });

  group('composition under the default semantic zoom setting', () {
    test('draws as many people as the shipped setting allows', () {
      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldOfIndirectPeople(450),
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: DateTime.utc(2026, 10, 26),
        labelBudget: (perPerson: 3, total: 150),
      );

      expect(
        composed.keptPeerIds,
        hasLength(kFieldSemanticZoomEnabled ? 400 : 120),
      );
    });
  });

  group('cubit render cap', () {
    test('semantic zoom on keeps 400 of 450 people on the map', () async {
      final kept = await _keptByCubit(
        _fieldOfIndirectPeople(450),
        semanticZoomEnabled: true,
      );

      expect(kept, hasLength(400));
      expect(kept, contains(_id(399)));
      expect(kept, isNot(contains(_id(400))));
    });

    test(
      'semantic zoom on keeps all 400 people when 400 are visible',
      () async {
        final kept = await _keptByCubit(
          _fieldOfIndirectPeople(400),
          semanticZoomEnabled: true,
        );

        expect(kept, hasLength(400));
      },
    );

    test('semantic zoom off keeps 120 of 400 people on the map', () async {
      final kept = await _keptByCubit(
        _fieldOfIndirectPeople(400),
        semanticZoomEnabled: false,
      );

      expect(kept, hasLength(120));
    });

    test('the default setting decides the cap', () async {
      final kept = await _keptByCubit(_fieldOfIndirectPeople(450));

      expect(kept, hasLength(kFieldSemanticZoomEnabled ? 400 : 120));
    });
  });
}
