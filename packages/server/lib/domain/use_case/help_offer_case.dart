import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_admission_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';
import 'package:tentura_server/domain/coordination/withdraw_reason.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

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
    this._forwardEdgeRepository,
    this._admissionRepository,
    BeaconRoomNotificationPort legacyNotificationPort,
    this._guard, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final HelpOfferRepositoryPort _helpOfferRepository;
  final BeaconRepositoryPort _beaconRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final InboxRepositoryPort _inboxRepository;
  final CapabilityCase _capabilityCase;
  final BeaconRoomRepositoryPort _beaconRoomRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferAdmissionRepositoryPort _admissionRepository;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;
  final BeaconAccessGuard _guard;

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
            coordinationCode:
                HelpOfferCoordinationExceptionCode.invalidHelpType,
          );
        }
      }
    }
    if (!await _guard.canReadContent(beaconId: beaconId, viewerId: userId)) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.status.isOpenFamily) {
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
      return;
    }
    if (beacon.author.id == userId) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.authorCannotCommit,
      );
    }
    await _attention!.runAction<void>(
      actorUserId: userId,
      action: (transaction) async {
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
        await transaction.record(
          await _attentionIntents!.helpOfferSubmitted(
            beaconId: beaconId,
            helpOffererId: userId,
            authorId: beacon.author.id,
            sourceEventKey: 'help_offer:${generateId('A')}',
          ),
        );
      },
    );
    await _autoAdmitIfTrusted(
      beacon: beacon,
      helpOffererId: userId,
    );
  }

  /// Auto-admits [helpOffererId] to the beacon room without waiting for explicit
  /// author approval when the author directly forwarded this beacon to them.
  /// Skipped when the author previously revoked room access for this user.
  Future<void> _autoAdmitIfTrusted({
    required BeaconEntity beacon,
    required String helpOffererId,
  }) async {
    final isTrusted = await _forwardEdgeRepository.isDirectAuthorForward(
      beaconId: beacon.id,
      authorId: beacon.author.id,
      userId: helpOffererId,
    );
    if (!isTrusted) return;

    final existing = await _beaconRoomRepository.findParticipant(
      beaconId: beacon.id,
      userId: helpOffererId,
    );
    if (existing != null && existing.roomAccess == RoomAccessBits.none) return;

    await _attention!.runAction<void>(
      actorUserId: beacon.author.id,
      action: (transaction) async {
        await _beaconRoomRepository.inviteOfferUserToBeaconRoom(
          beaconId: beacon.id,
          offerUserId: helpOffererId,
          authorUserId: beacon.author.id,
        );
        await _coordinationRepository.upsertResponse(
          beaconId: beacon.id,
          offerUserId: helpOffererId,
          authorUserId: beacon.author.id,
          responseType: CoordinationResponseType.useful.smallintValue,
        );
        await _admissionRepository.record(
          beaconId: beacon.id,
          offerUserId: helpOffererId,
          actorUserId: beacon.author.id,
          action: HelpOfferAdmissionAction.autoAdmit,
        );
        await transaction.record(
          await _attentionIntents!.offerAccepted(
            receiverId: helpOffererId,
            beaconId: beacon.id,
            actorUserId: beacon.author.id,
            sourceEventKey: 'admission:${generateId('A')}',
          ),
        );
      },
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
        coordinationCode:
            HelpOfferCoordinationExceptionCode.invalidWithdrawReason,
      );
    }
    if (!await _guard.canReadContent(beaconId: beaconId, viewerId: userId)) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsBeaconWithdraw) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.beaconWithdrawForbidden,
      );
    }
    await _attention!.runAction<void>(
      actorUserId: userId,
      action: (transaction) async {
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
        final beaconAfter = await _beaconRepository.getBeaconById(
          beaconId: beaconId,
        );
        if (beaconAfter.status.isOpenFamily) {
          await _inboxRepository.upsertWatchingForSender(
            senderId: userId,
            beaconId: beaconId,
            touchForwardOrdering: false,
          );
          await transaction.record(
            await _attentionIntents!.helpWithdrawn(
              beaconId: beaconId,
              withdrawerUserId: userId,
              sourceEventKey: 'help_withdrawn:${generateId('A')}',
            ),
          );
        } else {
          await _inboxRepository.applyTombstoneAfterWithdraw(
            userId: userId,
            beaconId: beaconId,
          );
        }
      },
    );
  }
}
