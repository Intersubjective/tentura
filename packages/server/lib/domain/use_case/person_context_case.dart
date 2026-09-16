import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';

import '_use_case_base.dart';

/// Person-profile context shared between the viewer and a peer.
@Injectable(order: 2)
final class PersonContextCase extends UseCaseBase {
  PersonContextCase(
    this._personVisibility, {
    required super.env,
    required super.logger,
  });

  final PersonVisibilityRepositoryPort _personVisibility;

  /// Active requests shared by [viewerId] and [peerId].
  Future<List<({String beaconId, String title})>> sharedContexts({
    required String viewerId,
    required String peerId,
  }) => _personVisibility.sharedContexts(viewerId: viewerId, peerId: peerId);
}
