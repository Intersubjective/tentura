import 'package:freezed_annotation/freezed_annotation.dart';

import 'constellation_anchor_projection.dart';

part 'constellation_projection_params.freezed.dart';

/// Values that bind a FULL or ANCHORS read to its projection.
///
/// Membership filters use two non-null boolean values, so omitted switches
/// and explicitly disabled switches have the same normalized identity.
@freezed
abstract class ConstellationProjectionParams
    with _$ConstellationProjectionParams {
  const factory ConstellationProjectionParams({
    @Default('') String context,
    @Default(ConstellationFieldMembershipFilters.defaults)
    ConstellationFieldMembershipFilters membershipFilters,
  }) = _ConstellationProjectionParams;
}
