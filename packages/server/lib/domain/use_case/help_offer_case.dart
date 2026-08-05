import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';
import 'package:tentura_server/domain/coordination/withdraw_reason.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'capability_case.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class HelpOfferCase extends UseCaseBase {
  HelpOfferCase(
    this._helpOfferRepository,
    this._beaconRepository,
    this._commitmentRepository,
    this._inboxRepository,
    this._capabilityCase,
    this._guard, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final HelpOfferRepositoryPort _helpOfferRepository;
  final BeaconRepositoryPort _beaconRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final InboxRepositoryPort _inboxRepository;
  final CapabilityCase _capabilityCase;
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
      final existingOffers =
          await _helpOfferRepository.fetchByBeaconId(beaconId);
      final existingOfferKind = existingOffers
          .firstWhere((o) => o.userId == userId)
          .offerKind;
      await _helpOfferRepository.upsert(
        beaconId: beaconId,
        userId: userId,
        message: message,
        helpTypes: helpTypes,
        offerKind: existingOfferKind,
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
    final offerKind =
        beacon.status == BeaconStatus.enoughHelp ? 1 : 0;
    await _attention!.runAction<void>(
      actorUserId: userId,
      action: (transaction) async {
        await _helpOfferRepository.upsert(
          beaconId: beaconId,
          userId: userId,
          message: message,
          helpTypes: helpTypes,
          offerKind: offerKind,
        );
        await _commitmentRepository.record(
          beaconId: beaconId,
          userId: userId,
          actorUserId: userId,
          kind: CommitmentEventKind.offered,
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
        await _commitmentRepository.record(
          beaconId: beaconId,
          userId: userId,
          actorUserId: userId,
          kind: CommitmentEventKind.withdrawnByHelper,
          reason: withdrawReason,
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
