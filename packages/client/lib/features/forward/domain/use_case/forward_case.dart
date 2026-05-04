import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';

import '../../data/repository/forward_repository.dart';

@singleton
final class ForwardCase extends UseCaseBase {
  ForwardCase(
    this._forwardRepository,
    this._authLocalRepository,
    this._factCards, {
    required super.env,
    required super.logger,
  });

  final ForwardRepository _forwardRepository;

  final AuthLocalRepositoryPort _authLocalRepository;

  final BeaconFactCardRepository _factCards;

  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      _forwardRepository.fetchForwardCandidates(context: context);

  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) =>
      _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId);

  Future<String> getCurrentAccountId() =>
      _authLocalRepository.getCurrentAccountId();

  Future<List<BeaconFactCard>> fetchPublicFactCards(String beaconId) async {
    final rows = await _factCards.list(beaconId: beaconId);
    return [
      for (final f in rows)
        if (f.visibility == BeaconFactCardVisibilityBits.public) f,
    ];
  }

  Future<Map<String, List<String>>> fetchTopCapabilitiesForCandidates(
    List<String> subjectIds, {
    int limit = 2,
  }) => GetIt.I<CapabilityRepositoryPort>().fetchTopCapabilitiesBatch(
    subjectIds: subjectIds,
    limit: limit,
  );

  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
  }) =>
      _forwardRepository.forwardBeacon(
        beaconId: beaconId,
        recipientIds: recipientIds,
        note: note,
        perRecipientNotes: perRecipientNotes,
        recipientReasons: recipientReasons,
        context: context,
        parentEdgeId: parentEdgeId,
      );
}
