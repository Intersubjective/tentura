import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_requests_port.dart';

import '_use_case_base.dart';

/// Targeted Request read for an open field (#671). It does not scan the
/// viewer's visible set for authors: readability (`beacon_readable_ids`) is
/// the gate, and the client places a Request only when its author is already
/// on the field. Readability itself serves the viewer's visible set from the
/// cross-request cache (m0235) and computes it (one MeritRank call) on a miss,
/// as any Request read does.
@Singleton(order: 2)
final class ConstellationFieldRequestsCase extends UseCaseBase {
  ConstellationFieldRequestsCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationFieldRequestsPort _port;

  Future<List<ConstellationRequestRecord>> discoverableRequestsByIds({
    required String viewerId,
    required Set<String> beaconIds,
    required ConstellationFieldMembershipFilters filters,
  }) {
    if (viewerId.trim().isEmpty || beaconIds.isEmpty) {
      return Future.value(const []);
    }
    return _port.discoverableRequestsByIds(
      viewerId: viewerId,
      beaconIds: beaconIds,
      filters: filters,
    );
  }
}
