import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';
import 'package:tentura_server/domain/coordination/uncommit_reason.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

@Singleton(order: 2)
class CommitmentCase {
  const CommitmentCase(
    this._commitmentRepository,
    this._beaconRepository,
    this._coordinationRepository,
    this._inboxRepository,
  );

  final CommitmentRepository _commitmentRepository;
  final BeaconRepository _beaconRepository;
  final CoordinationRepository _coordinationRepository;
  final InboxRepository _inboxRepository;

  Future<void> commit({
    required String beaconId,
    required String userId,
    String message = '',
    String? helpType,
  }) async {
    if (!isAllowedHelpType(helpType)) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.invalidHelpType,
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.state != 0) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.beaconNotOpen,
      );
    }
    final hasActive = await _commitmentRepository.hasActiveCommitment(
      beaconId: beaconId,
      userId: userId,
    );
    // Same mutation updates note/help-type when already committed; only the
    // initial commit is rejected for author / duplicate-active is N/A (upsert).
    if (hasActive) {
      await _commitmentRepository.upsert(
        beaconId: beaconId,
        userId: userId,
        message: message,
        helpType: helpType,
      );
      await _coordinationRepository.recomputeAndPersistBeaconCoordinationStatus(
        beaconId,
      );
      return;
    }
    if (beacon.author.id == userId) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.authorCannotCommit,
      );
    }
    await _commitmentRepository.upsert(
      beaconId: beaconId,
      userId: userId,
      message: message,
      helpType: helpType,
    );
    await _coordinationRepository.recomputeAndPersistBeaconCoordinationStatus(
      beaconId,
    );
  }

  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String uncommitReason,
    String message = '',
  }) async {
    if (!isAllowedUncommitReason(uncommitReason)) {
      throw CommitmentCoordinationException(
        coordinationCode: CommitmentCoordinationExceptionCode.invalidUncommitReason,
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsBeaconWithdraw) {
      throw CommitmentCoordinationException(
        coordinationCode:
            CommitmentCoordinationExceptionCode.beaconWithdrawForbidden,
      );
    }
    await _coordinationRepository.deleteForCommit(
      beaconId: beaconId,
      userId: userId,
    );
    await _commitmentRepository.withdraw(
      beaconId: beaconId,
      userId: userId,
      message: message,
      uncommitReason: uncommitReason,
    );
    await _coordinationRepository.recomputeAndPersistBeaconCoordinationStatus(
      beaconId,
    );
    final beaconAfter = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beaconAfter.state == 0) {
      await _inboxRepository.upsertWatchingForSender(
        senderId: userId,
        beaconId: beaconId,
        touchForwardOrdering: false,
      );
    } else {
      await _inboxRepository.applyTombstoneAfterWithdraw(
        userId: userId,
        beaconId: beaconId,
      );
    }
  }
}
