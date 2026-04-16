import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';

import '../../data/repository/forward_repository.dart';

@singleton
final class ForwardCase extends UseCaseBase {
  ForwardCase(
    this._forwardRepository,
    this._authLocalRepository, {
    required super.env,
    required super.logger,
  });

  final ForwardRepository _forwardRepository;

  final AuthLocalRepositoryPort _authLocalRepository;

  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      _forwardRepository.fetchForwardCandidates(context: context);

  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) =>
      _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId);

  Future<String> getCurrentAccountId() =>
      _authLocalRepository.getCurrentAccountId();

  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    String? context,
    String? parentEdgeId,
  }) =>
      _forwardRepository.forwardBeacon(
        beaconId: beaconId,
        recipientIds: recipientIds,
        note: note,
        perRecipientNotes: perRecipientNotes,
        context: context,
        parentEdgeId: parentEdgeId,
      );
}
