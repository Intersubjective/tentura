import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_member_webs_repository_port.dart';

import '_use_case_base.dart';

/// Member web of a Request for the V2 `beaconMemberWebs` query: admitted
/// helpers for every content reader; forward recipients only for viewers who
/// can also read involvement.
@Singleton(order: 2)
final class BeaconMemberWebsCase extends UseCaseBase {
  BeaconMemberWebsCase(
    this._repository,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final BeaconMemberWebsRepositoryPort _repository;
  final BeaconAccessGuard _guard;

  Future<List<ConstellationMemberWebRecord>> memberWebs({
    required String beaconId,
    required String viewerId,
  }) async {
    if (!await _guard.canReadContent(beaconId: beaconId, viewerId: viewerId)) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    return _repository.memberWebs(
      beaconId: beaconId,
      viewerId: viewerId,
      context: kConstellationContext,
      includeForwarded: await _guard.canReadInvolvement(
        beaconId: beaconId,
        viewerId: viewerId,
      ),
    );
  }
}
