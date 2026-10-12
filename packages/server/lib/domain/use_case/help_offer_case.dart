import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';
import 'package:tentura_server/domain/coordination/withdraw_reason.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/beacon_kind_policy.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/author_invite_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/use_case/admission_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
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
    required BeaconRoomRepositoryPort roomRepository,
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    AttentionSystemSettlementPort? attentionSystemSettlement,
    ClosureCase? closureCase,
    AuthorInvitePort? authorInvites,
    CoordinationRepositoryPort? coordinationRepository,
    required super.env,
    required super.logger,
  }) : _roomRepository = roomRepository,
       _attentionIntents = attentionIntents,
       _attention = attention,
       _attentionSystemSettlement = attentionSystemSettlement,
       _closureCase = closureCase,
       _authorInvites = authorInvites,
       _inviteAdmission =
           authorInvites == null || coordinationRepository == null
           ? null
           : AdmissionOperation(
               _helpOfferRepository,
               coordinationRepository,
               _commitmentRepository,
               closureCase,
               attentionSystemSettlement,
             );

  final BeaconRoomRepositoryPort _roomRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final BeaconRepositoryPort _beaconRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final InboxRepositoryPort _inboxRepository;
  final CapabilityCase _capabilityCase;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;
  final AttentionSystemSettlementPort? _attentionSystemSettlement;
  final BeaconAccessGuard _guard;
  final ClosureCase? _closureCase;

  /// Budding supersede (Arch §5.4): set only when both the invite port and
  /// the coordination repository are wired.
  final AuthorInvitePort? _authorInvites;
  final AdmissionOperation? _inviteAdmission;

  Future<void> offerHelp({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
    int? expectedOfferKind,
  }) async {
    if (helpTypes != null) {
      if (helpTypes.length > kMaxHelpOfferHelpTypes) {
        throw HelpOfferCoordinationException(
          coordinationCode: HelpOfferCoordinationExceptionCode.invalidHelpType,
        );
      }
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
    // A pending author invite turns the offer into an accept (Arch §5.4);
    // its locks (hierarchy, Post, child advisory) come before the Request row
    // (Arch §4.1).
    final pendingInvite = _inviteAdmission == null
        ? null
        : await _authorInvites!.fetchPending(
            beaconId: beaconId,
            inviteeId: userId,
          );
    await _attention!.runAction<void>(
      actorUserId: userId,
      action: (transaction) async {
        if (pendingInvite != null) {
          await _authorInvites!.lockScope(pendingInvite.sourcePostId);
          // Child advisory lock before the child row and the invite row.
          await _closureCase?.lockRequest(beaconId);
        }
        await _beaconRepository.runInBeaconStateTransaction(
          beaconId: beaconId,
          userId: userId,
          fn: (lockedBeacon) async {
            BeaconKindPolicy.requireRequest(lockedBeacon);
            if (!await _guard.canReadContent(
              beaconId: beaconId,
              viewerId: userId,
            )) {
              throw const UnauthorizedException(
                description: 'Viewer cannot read request content',
              );
            }
            if (!lockedBeacon.status.isOpenFamily) {
              throw HelpOfferCoordinationException(
                coordinationCode:
                    HelpOfferCoordinationExceptionCode.beaconNotOpen,
              );
            }

            final hasActive = await _helpOfferRepository.hasActiveHelpOffer(
              beaconId: beaconId,
              userId: userId,
            );

            if (hasActive) {
              final existingOffers = await _helpOfferRepository.fetchByBeaconId(
                beaconId,
              );
              final existingOfferKind = existingOffers
                  .firstWhere((o) => o.userId == userId)
                  .offerKind;
              _rejectOfferKindMismatch(
                expectedOfferKind: expectedOfferKind,
                permissibleKind: existingOfferKind,
              );
              await _helpOfferRepository.upsert(
                beaconId: beaconId,
                userId: userId,
                message: message,
                helpTypes: helpTypes,
                offerKind: existingOfferKind,
              );
              await _recordHelpTypeCapabilities(
                userId: userId,
                beaconId: beaconId,
                helpTypes: helpTypes,
              );
              // The offer predates the invite: it is still the second
              // confirmation, and no second `offered` event is recorded.
              final invite = pendingInvite == null
                  ? null
                  : await _authorInvites!.lockPendingUnblocked(
                      beaconId: beaconId,
                      inviteeId: userId,
                    );
              if (invite != null) {
                await _admitInvitee(
                  beacon: lockedBeacon,
                  invite: invite,
                  transaction: transaction,
                );
              }
              return;
            }

            if (lockedBeacon.author.id == userId) {
              throw HelpOfferCoordinationException(
                coordinationCode:
                    HelpOfferCoordinationExceptionCode.authorCannotCommit,
              );
            }

            final permissibleKind =
                lockedBeacon.status == BeaconStatus.enoughHelp ? 1 : 0;
            _rejectOfferKindMismatch(
              expectedOfferKind: expectedOfferKind,
              permissibleKind: permissibleKind,
            );
            final offerKind = permissibleKind;
            final invite = pendingInvite == null
                ? null
                : await _authorInvites!.lockPendingUnblocked(
                    beaconId: beaconId,
                    inviteeId: userId,
                  );
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
            await _recordHelpTypeCapabilities(
              userId: userId,
              beaconId: beaconId,
              helpTypes: helpTypes,
            );
            if (invite != null) {
              await _admitInvitee(
                beacon: lockedBeacon,
                invite: invite,
                transaction: transaction,
              );
              return;
            }
            final intents = _attentionIntents;
            if (intents == null) return;
            await transaction.record(
              await intents.helpOfferSubmitted(
                beaconId: beaconId,
                helpOffererId: userId,
                authorId: lockedBeacon.author.id,
                sourceEventKey: 'help_offer:${generateId('A')}',
                isBackupOffer: offerKind == 1,
                message: message,
              ),
            );
          },
        );
      },
    );
  }

  /// Supersede (Arch §5.4): the invitee offered while the author's invite is
  /// pending, so both confirmations exist. The offer is admitted through the
  /// shared operation with the inviter as the confirming author, no
  /// `helpOfferSubmitted` obligation is created, and the invite is accepted.
  Future<void> _admitInvitee({
    required BeaconEntity beacon,
    required AuthorInvite invite,
    required AttentionTransaction transaction,
  }) async {
    await _inviteAdmission!.admitWithConfirmations(
      beacon: beacon,
      helperId: invite.inviteeId,
      confirmingAuthorId: invite.inviterId,
      actorId: invite.inviteeId,
      transaction: transaction,
      invite: invite,
      attention: () => _attentionIntents!.authorInviteAccepted(
        beaconId: beacon.id,
        inviterUserId: invite.inviterId,
        inviteeUserId: invite.inviteeId,
        sourceEventKey: 'author_invite_accepted:${invite.id}',
      ),
    );
    await _authorInvites!.resolve(
      inviteId: invite.id,
      status: AuthorInviteStatus.accepted,
      resolvedBy: invite.inviteeId,
    );
    await _attentionSystemSettlement?.clearAuthorInviteReceived(
      beaconId: beacon.id,
      inviteeId: invite.inviteeId,
    );
  }

  Future<void> setRoleLabel({
    required String beaconId,
    required String actorUserId,
    required String offerUserId,
    required String roleLabel,
  }) async {
    final trimmed = roleLabel.trim();
    if (trimmed.contains('\n') ||
        trimmed.contains('\r') ||
        trimmed.length > kMaxHelpOfferRoleLabelLength) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.invalidRoleLabel,
      );
    }
    if (!await _guard.canReadContent(
      beaconId: beaconId,
      viewerId: actorUserId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    final hasActive = await _helpOfferRepository.hasActiveHelpOffer(
      beaconId: beaconId,
      userId: offerUserId,
    );
    if (!hasActive) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.helpOfferNotActive,
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    BeaconKindPolicy.requireRequest(beacon);
    final isAuthor = beacon.author.id == actorUserId;
    final isSelf = actorUserId == offerUserId;
    final isSteward = await _roomRepository.isBeaconSteward(
      beaconId: beaconId,
      userId: actorUserId,
    );
    if (!isSelf && !isAuthor && !isSteward) {
      throw const UnauthorizedException(
        description: 'Not allowed to edit this role label',
      );
    }
    await _helpOfferRepository.setRoleLabel(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      roleLabel: trimmed.isEmpty ? null : trimmed,
    );
  }

  void _rejectOfferKindMismatch({
    required int? expectedOfferKind,
    required int permissibleKind,
  }) {
    if (expectedOfferKind != null && expectedOfferKind != permissibleKind) {
      throw HelpOfferCoordinationException(
        coordinationCode: HelpOfferCoordinationExceptionCode.offerKindChanged,
      );
    }
  }

  Future<void> _recordHelpTypeCapabilities({
    required String userId,
    required String beaconId,
    required List<String>? helpTypes,
  }) async {
    if (helpTypes == null || helpTypes.isEmpty) {
      return;
    }
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
    BeaconKindPolicy.requireRequest(beacon);
    if (!beacon.allowsBeaconWithdraw) {
      throw HelpOfferCoordinationException(
        coordinationCode:
            HelpOfferCoordinationExceptionCode.beaconWithdrawForbidden,
      );
    }
    await _attention!.runAction<void>(
      actorUserId: userId,
      action: (transaction) async {
        // Lock order (Arch §4.1): hierarchy before the child lock, as the
        // same helper's invite accept takes them; the participant trigger
        // takes the hierarchy lock anyway, so taking it last deadlocks.
        await _authorInvites?.lockScope(null);
        await _closureCase?.lockRequest(beaconId);
        // Re-read after locking: a closure may have won the hierarchy lock.
        final locked = await _beaconRepository.getBeaconById(
          beaconId: beaconId,
        );
        if (!locked.allowsBeaconWithdraw) {
          throw HelpOfferCoordinationException(
            coordinationCode:
                HelpOfferCoordinationExceptionCode.beaconWithdrawForbidden,
          );
        }
        await _commitmentRepository.record(
          beaconId: beaconId,
          userId: userId,
          actorUserId: userId,
          kind: CommitmentEventKind.withdrawnByHelper,
          reason: withdrawReason,
        );
        await _closureCase?.applyMembershipEvent(beaconId, userId);
        await _closureCase?.retractApprovalEdge(beaconId, userId);
        await _helpOfferRepository.withdraw(
          beaconId: beaconId,
          userId: userId,
          message: message,
          withdrawReason: withdrawReason,
        );
        await _roomRepository.revokeOfferUserBeaconRoomAccess(
          beaconId: beaconId,
          offerUserId: userId,
          authorUserId: userId,
        );
        // D04: the offer is gone, so the author's `helpOfferSubmitted`
        // obligation ends here — as `superseded`, never `resolved`: the author
        // never answered it. Same transaction as the withdrawal itself.
        await _attentionSystemSettlement?.supersedeAuthorHelpOfferSubmitted(
          beaconId: beaconId,
          authorAccountId: beacon.author.id,
          helpOffererUserId: userId,
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
