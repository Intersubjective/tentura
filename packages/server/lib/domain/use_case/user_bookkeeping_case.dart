import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/entity/user_bookkeeping_result.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_admission_repository_port.dart';
import 'package:tentura_server/domain/port/user_bookkeeping_repository_port.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class UserBookkeepingCase extends UseCaseBase {
  UserBookkeepingCase(
    this._bookkeepingRepository,
    this._coordinationRepository,
    this._admissionRepository,
    this._forwardEdgeRepository, {
    required super.env,
    required super.logger,
  });

  final UserBookkeepingRepositoryPort _bookkeepingRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final HelpOfferAdmissionRepositoryPort _admissionRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;

  Future<UserBookkeepingResult> recalculateForUser({
    required String userId,
  }) async {
    final affectedBeaconIds = <String>{};
    var coordinationRepairedCount = 0;

    final gaps = await _bookkeepingRepository
        .listAdmittedOffersMissingCoordination(userId);
    for (final gap in gaps) {
      affectedBeaconIds.add(gap.beaconId);
      await _coordinationRepository.upsertResponse(
        beaconId: gap.beaconId,
        offerUserId: gap.offerUserId,
        authorUserId: gap.authorUserId,
        responseType: CoordinationResponseType.useful.smallintValue,
      );

      final existingAdmission = await _admissionRepository.latestFor(
        beaconId: gap.beaconId,
        offerUserId: gap.offerUserId,
      );
      if (existingAdmission == null) {
        final isAutoAdmit = await _forwardEdgeRepository.isDirectAuthorForward(
          beaconId: gap.beaconId,
          authorId: gap.authorUserId,
          userId: gap.offerUserId,
        );
        await _admissionRepository.record(
          beaconId: gap.beaconId,
          offerUserId: gap.offerUserId,
          actorUserId: gap.authorUserId,
          action: isAutoAdmit
              ? HelpOfferAdmissionAction.autoAdmit
              : HelpOfferAdmissionAction.accept,
        );
      }

      coordinationRepairedCount++;
    }

    final inbox = await _bookkeepingRepository.reconcileInboxForUser(userId);
    affectedBeaconIds.addAll(inbox.beaconIds);

    return UserBookkeepingResult(
      coordinationRepairedCount: coordinationRepairedCount,
      inboxRowsRepairedCount: inbox.repairedCount,
      inboxRowsInsertedCount: inbox.insertedCount,
      affectedBeaconIds: affectedBeaconIds.toList(growable: false),
    );
  }
}
