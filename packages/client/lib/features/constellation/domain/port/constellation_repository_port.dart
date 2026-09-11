import '../entity/constellation_anchor_projection.dart';
import '../entity/constellation_field.dart';

abstract interface class ConstellationRepositoryPort {
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  });
}
