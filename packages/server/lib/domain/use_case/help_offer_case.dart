import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';
import 'package:tentura_server/domain/coordination/withdraw_reason.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';

import 'capability_case.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class HelpOfferCase extends UseCaseBase {
  HelpOfferCase(
    this._helpOfferRepository,
    this._beaconRepository,
    this._coordinationRepository,
    this._inboxRepository,
    this._capabilityCase,
    this._beaconRoomRepository,
    this._friendshipLookup,
    this._forwardEdgeRepository,
    this._roomPush, {
    required super.env,
    required super.logger,
  });

  final HelpOfferRepositoryPort _helpOfferRepository;
  final BeaconRepositoryPort _beaconRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final InboxRepositoryPort _inboxRepository;
  final CapabilityCase _capabilityCase;
  final BeaconRoomRepository _beaconRoomRepository;
  final VoteUserFriendshipLookup _friendshipLookup;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final BeaconRoomPushService _roomPush;

  Future<void> offerHelp({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
  }) async {
    if (helpTypes != null) {
      for (final type in helpTypes) {
        if (!isAllowedHelpType(type)) {
          throw HelpOfferCoordinationException(
            coordinationCode: HelpOfferCoordinationExceptionCode.invalidHelpType,
          );
        }
      }
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.state != 0) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.beaconNotOpen,
      );
    }
    final hasActive = await _helpOfferRepository.hasActiveHelpOffer(
      beaconId: beaconId,
      userId: userId,
    );
    if (hasActive) {
      await _helpOfferRepository.upsert(
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
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.authorCannotCommit,
      );
    }
    await _helpOfferRepository.upsert(
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
    await _autoAdmitIfTrusted(
      beacon: beacon,
      helpOffererId: userId,
    );
    unawaited(
      _roomPush.notifyHelpOfferToAuthor(
        beaconId: beaconId,
        helpOffererId: userId,
        authorId: beacon.author.id,
      ).catchError((Object e) {
        logger.warning('HelpOfferCase: failed to enqueue help offer notification: $e');
      }),
    );
  }

  /// Auto-admits [helpOffererId] to the beacon room without waiting for explicit
  /// author approval when the offering user is "trusted":
  ///   1. the author directly forwarded this beacon to them, OR
  ///   2. they share a mutual (reciprocal) explicit subscription with the author.
  /// Skipped when the author previously revoked room access for this user.
  Future<void> _autoAdmitIfTrusted({
    required BeaconEntity beacon,
    required String helpOffererId,
  }) async {
    final isTrusted =
        await _forwardEdgeRepository.isDirectAuthorForward(
          beaconId: beacon.id,
          authorId: beacon.author.id,
          userId: helpOffererId,
        ) ||
        await _friendshipLookup.isReciprocalSubscribe(
          viewerId: beacon.author.id,
          peerId: helpOffererId,
        );
    if (!isTrusted) return;

    final existing = await _beaconRoomRepository.findParticipant(
      beaconId: beacon.id,
      userId: helpOffererId,
    );
    if (existing != null && existing.roomAccess == RoomAccessBits.none) return;

    await _beaconRoomRepository.inviteOfferUserToBeaconRoom(
      beaconId: beacon.id,
      offerUserId: helpOffererId,
      authorUserId: beacon.author.id,
    );
    unawaited(
      _roomPush.notifyRoomAdmitted(
        receiverId: helpOffererId,
        beaconId: beacon.id,
      ),
    );
  }

  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  }) async {
    if (!isAllowedWithdrawReason(withdrawReason)) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.invalidWithdrawReason,
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsBeaconWithdraw) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.beaconWithdrawForbidden,
      );
    }
    await _coordinationRepository.deleteForCommit(
      beaconId: beaconId,
      userId: userId,
    );
    await _helpOfferRepository.withdraw(
      beaconId: beaconId,
      userId: userId,
      message: message,
      withdrawReason: withdrawReason,
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
