import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';
import 'package:tentura_server/domain/coordination/uncommit_reason.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';

import 'capability_case.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class CommitmentCase extends UseCaseBase {
  CommitmentCase(
    this._commitmentRepository,
    this._beaconRepository,
    this._coordinationRepository,
    this._inboxRepository,
    this._capabilityCase,
    this._beaconRoomRepository,
    this._friendshipLookup,
    this._roomPush, {
    required super.env,
    required super.logger,
  });

  final CommitmentRepositoryPort _commitmentRepository;
  final BeaconRepositoryPort _beaconRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final InboxRepositoryPort _inboxRepository;
  final CapabilityCase _capabilityCase;
  final BeaconRoomRepository _beaconRoomRepository;
  final VoteUserFriendshipLookup _friendshipLookup;
  final BeaconRoomPushService _roomPush;

  Future<void> commit({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
  }) async {
    if (helpTypes != null) {
      for (final type in helpTypes) {
        if (!isAllowedHelpType(type)) {
          throw CommitmentCoordinationException(
            coordinationCode: CommitmentCoordinationExceptionCode.invalidHelpType,
          );
        }
      }
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
        helpTypes: helpTypes,
      );
      if (helpTypes != null && helpTypes.isNotEmpty) {
        for (final type in helpTypes) {
          try {
            await _capabilityCase.recordCommitRole(
              observerId: userId,
              subjectId: userId,
              beaconId: beaconId,
              slug: type,
            );
          } catch (e, st) {
            logger.warning('recordCommitRole failed', e, st);
          }
        }
      }
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
      helpTypes: helpTypes,
    );
    if (helpTypes != null && helpTypes.isNotEmpty) {
      for (final type in helpTypes) {
        try {
          await _capabilityCase.recordCommitRole(
            observerId: userId,
            subjectId: userId,
            beaconId: beaconId,
            slug: type,
          );
        } catch (e, st) {
          logger.warning('recordCommitRole failed', e, st);
        }
      }
    }
    await _coordinationRepository.recomputeAndPersistBeaconCoordinationStatus(
      beaconId,
    );
    await _autoAdmitIfDirectFriend(
      beacon: beacon,
      committantId: userId,
    );
    unawaited(
      _roomPush.notifyCommitToAuthor(
        beaconId: beaconId,
        committerId: userId,
        authorId: beacon.author.id,
      ).catchError((Object e) {
        logger.warning('CommitmentCase: failed to enqueue commit notification: $e');
      }),
    );
  }

  /// If the beacon author has a positive trust edge toward [committantId]
  /// (one-way subscription covers mutual friendship too), immediately admit
  /// them to the room without waiting for explicit author approval.
  /// Skipped when the author previously revoked room access for this user.
  Future<void> _autoAdmitIfDirectFriend({
    required BeaconEntity beacon,
    required String committantId,
  }) async {
    final isDirectFriend = await _friendshipLookup.isSubscribedTo(
      viewerId: beacon.author.id,
      peerId: committantId,
    );
    if (!isDirectFriend) return;

    final existing = await _beaconRoomRepository.findParticipant(
      beaconId: beacon.id,
      userId: committantId,
    );
    // Honour explicit author revocation — roomAccess=none means author said no.
    if (existing != null && existing.roomAccess == RoomAccessBits.none) return;

    await _beaconRoomRepository.inviteCommitUserToBeaconRoom(
      beaconId: beacon.id,
      commitUserId: committantId,
      authorUserId: beacon.author.id,
    );
    unawaited(
      _roomPush.notifyRoomAdmitted(
        receiverId: committantId,
        beaconId: beacon.id,
      ),
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
