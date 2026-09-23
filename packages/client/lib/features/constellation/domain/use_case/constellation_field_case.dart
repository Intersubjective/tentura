import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../constellation_anchor_composition.dart';
import '../constellation_density.dart';
import '../constellation_filters.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import '../entity/constellation_anchor_projection.dart';
import '../entity/constellation_field.dart';
import '../port/constellation_repository_port.dart';

typedef ConstellationFieldResolved = ({
  ConstellationField field,
  ConstellationComposedPresentation composition,
  ConstellationPathResolution paths,
  Set<String> keptPeerIds,
  Set<String> droppedHolderIds,
  bool capped,
});

@Order(2)
@singleton
final class ConstellationFieldCase extends UseCaseBase {
  ConstellationFieldCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationRepositoryPort _repository;

  Future<ConstellationFieldResolved> load({
    required String viewerId,
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
    ConstellationFilters localFilters = const (
      capabilitySlugs: {},
      location: LocationFilter.any,
      timing: TimingFilterAny(),
      includeUnspecified: true,
    ),
    DateTime? asOfUtc,
    ConstellationLabelBudget labelBudget = const (perPerson: 3, total: 150),
  }) async {
    final field = await _repository.fetch(
      membershipFilters: membershipFilters,
      projection: projection,
    );
    final loadedAt = asOfUtc ?? field.loadedAt;
    final composition = composeConstellationPresentation(
      viewerId: viewerId,
      field: field,
      localFilters: localFilters,
      asOfUtc: loadedAt,
      labelBudget: labelBudget,
    );

    return (
      field: field,
      composition: composition,
      paths: composition.paths,
      keptPeerIds: composition.keptPeerIds,
      droppedHolderIds: composition.droppedHolderIds,
      capped: composition.renderBudgetCapped,
    );
  }
}
