import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';
import 'package:tentura_server/domain/policy/beacon_forward_policy.dart';
import 'package:tentura_server/domain/policy/post_expiry_policy.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_wake_port.dart';
import 'package:tentura_server/domain/port/phantom_pending_forward_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/entity/invite_preview_result.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';
import 'contact_case.dart';

@Injectable(order: 2)
final class InvitationCase extends UseCaseBase {
  InvitationCase(
    this._invitationRepository,
    this._userRepository,
    this._beaconRepository,
    this._friendshipLookup,
    this._contactRepository,
    this._guard,
    this._forwardEdgeRepository,
    this._userBlockRepository, {
    PostLockPort? postLock,
    BeaconRoomRepositoryPort? room,
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    this._pendingForwards,
    this._phantomMergeWake = const PhantomMergeWakePort.disabled(),
    required super.env,
    required super.logger,
  }) : _postLock = postLock,
       _room = room,
       _attentionIntents = attentionIntents,
       _attention = attention;

  final InvitationRepositoryPort _invitationRepository;

  final UserRepositoryPort _userRepository;

  final BeaconRepositoryPort _beaconRepository;

  final VoteUserFriendshipLookupPort _friendshipLookup;

  final UserContactRepositoryPort _contactRepository;

  final BeaconAccessGuard _guard;

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;

  final BeaconRoomRepositoryPort? _room;

  final UserBlockRepositoryPort _userBlockRepository;

  final PostLockPort? _postLock;

  final AttentionIntentCase? _attentionIntents;

  final TransactionalAttentionCase? _attention;
  final PhantomMergeWakePort _phantomMergeWake;
  final PhantomPendingForwardRepositoryPort? _pendingForwards;

  Future<InvitationEntity> create({
    required String userId,
    required String addresseeName,
    String? beaconId,
  }) async {
    if (beaconId == null) {
      return _invitationRepository.create(
        issuerId: userId,
        addresseeName: ContactCase.normalizeOptionalName(addresseeName),
      );
    }
    if (!await _guard.canReadContent(beaconId: beaconId, viewerId: userId)) {
      throw const UnauthorizedException(
        description: 'Issuer cannot read request content',
      );
    }

    Future<InvitationEntity> createForBeacon(BeaconEntity beacon) async {
      if (!beacon.allowsForward ||
          await isExpiredPost(_beaconRepository, beacon)) {
        if (beacon.kind == BeaconKind.post) {
          throw const PostNotOpenException();
        }
        throw const UnauthorizedException(
          description: 'Request does not allow forwarding',
        );
      }
      if (!BeaconForwardPolicy.canForward(beacon: beacon, senderId: userId)) {
        throw const UnauthorizedException(
          description: 'Forwarding is off for this post',
        );
      }
      final inbound = await _forwardEdgeRepository.fetchActiveInboundEdges(
        beaconId: beaconId,
        recipientId: userId,
      );
      return _invitationRepository.create(
        issuerId: userId,
        addresseeName: ContactCase.normalizeOptionalName(addresseeName),
        beaconId: beaconId,
        parentForwardEdgeId: resolveForwardParentEdgeId(
          clientParentEdgeId: null,
          activeInboundEdges: inbound,
          senderId: userId,
          authorId: beacon.author.id,
        ),
      );
    }

    final firstRead = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (firstRead.kind != BeaconKind.post) return createForBeacon(firstRead);
    return _attention!.runAction(
      actorUserId: userId,
      action: (_) async => createForBeacon(await _postUnderLock(beaconId)),
    );
  }

  /// Reads the Post under its mutation lock in the caller's transaction.
  Future<BeaconEntity> _postUnderLock(String beaconId) async {
    await _postLock!.lockForPostMutation(beaconId);
    return _beaconRepository.getBeaconById(beaconId: beaconId);
  }

  Future<BeaconEntity> _lockPostInvite({
    required InvitationEntity invitation,
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _postUnderLock(beaconId);
    await _requireUnblockedInvite(invitation, userId);
    if (!beacon.allowsForward ||
        await isExpiredPost(_beaconRepository, beacon)) {
      throw const PostNotOpenException();
    }
    if (!BeaconForwardPolicy.canForward(
      beacon: beacon,
      senderId: invitation.issuer.id,
    )) {
      throw const UnauthorizedException(
        description: 'Forwarding is off for this post',
      );
    }
    return beacon;
  }

  /// Renames the addressee of the caller's own, unconsumed ordinary invite.
  Future<InvitationEntity> update({
    required String invitationId,
    required String userId,
    required String addresseeName,
  }) async => _invitationRepository.updateAddresseeName(
    invitationId: invitationId,
    userId: userId,
    addresseeName: ContactCase.normalizeName(addresseeName),
  );

  Future<InvitationEntity> fetchById({
    required String invitationId,
  }) async {
    final invitation = await _invitationRepository.getById(
      invitationId: invitationId,
    );
    if (invitation == null ||
        invitation.isAccepted ||
        invitation.isExpiredWithTtl(env.invitationTTL)) {
      throw IdNotFoundException(id: invitationId);
    }
    return invitation;
  }

  /// Read-only preview of what [code] means for [callerUserId] (null =
  /// anonymous). Unlike [fetchById] this never throws on a consumed/expired
  /// code — it reports the state so the landing can render before any UI.
  Future<InvitePreviewResult> preview({
    required String code,
    String? callerUserId,
    String? requestId,
  }) async {
    final invitation = await _invitationRepository.getById(invitationId: code);
    if (invitation == null) {
      return const InvitePreviewResult(
        codeStatus: InviteCodeStatus.invalid,
        callerStatus: InviteCallerStatus.anonymous,
      );
    }

    final codeStatus = invitation.isAccepted
        ? InviteCodeStatus.consumed
        : invitation.isExpiredWithTtl(env.invitationTTL)
        ? InviteCodeStatus.expired
        : InviteCodeStatus.available;

    final beacon = await _previewBeaconForInvite(
      invitation,
      codeStatus,
      requestId,
    );

    final phantomInvite = invitation.phantomId != null;
    final InviteCallerStatus callerStatus;
    if (callerUserId == null) {
      callerStatus = InviteCallerStatus.anonymous;
    } else if (callerUserId == invitation.issuer.id) {
      callerStatus = InviteCallerStatus.isInviter;
    } else if (!phantomInvite &&
        beacon?.kind != BeaconKind.post &&
        await _friendshipLookup.isReciprocalSubscribe(
          viewerId: callerUserId,
          peerId: invitation.issuer.id,
        )) {
      callerStatus = InviteCallerStatus.alreadyFriends;
    } else {
      callerStatus = InviteCallerStatus.existingUser;
    }

    var inviter = invitation.issuer;
    if (callerUserId != null && callerUserId != inviter.id) {
      final contactName = await _contactRepository.getName(
        viewerId: callerUserId,
        subjectId: inviter.id,
      );
      if (contactName != null) {
        inviter = inviter.copyWith(displayName: contactName);
      }
    }

    return InvitePreviewResult(
      codeStatus: codeStatus,
      callerStatus: callerStatus,
      inviter: inviter,
      beacon: beacon,
      phantomInvite: phantomInvite,
    );
  }

  Future<InvitePreviewBeacon?> _previewBeaconForInvite(
    InvitationEntity invitation,
    InviteCodeStatus codeStatus,
    String? requestId,
  ) async {
    final phantomId = invitation.phantomId;
    final beaconId = phantomId == null ? invitation.beaconId : requestId;
    if (beaconId == null) return null;

    if (phantomId != null) {
      final pendingForwards = _pendingForwards;
      if (codeStatus != InviteCodeStatus.available ||
          pendingForwards == null ||
          !await pendingForwards.hasPending(
            phantomId: phantomId,
            senderId: invitation.issuer.id,
            beaconId: beaconId,
          )) {
        return null;
      }
    }

    BeaconEntity beacon;
    try {
      beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    } on OwnerlessRequest catch (request) {
      return phantomId == null && codeStatus == InviteCodeStatus.available
          ? InvitePreviewBeacon.lapsedRequest(
              id: beaconId,
              title: request.title,
            )
          : null;
    } catch (_) {
      return null;
    }
    if (phantomId != null && beacon.kind != BeaconKind.request) return null;

    final issuerId = invitation.issuer.id;
    Future<bool> issuerCanReadContent() => _guard.canReadContent(
      beaconId: beaconId,
      viewerId: issuerId,
    );

    if (beacon.kind == BeaconKind.request) {
      if (codeStatus != InviteCodeStatus.available) return null;
      final canForward = await BeaconForwardPolicy.canForwardRequestInvite(
        beacon: beacon,
        issuerId: issuerId,
        issuerCanReadContent: issuerCanReadContent,
      );
      if (!canForward ||
          !await hasLiveForwardParentChain(
            invitation.parentForwardEdgeId,
            readEdge: (edgeId) async {
              final edge = await _forwardEdgeRepository.fetchById(edgeId);
              return edge == null
                  ? null
                  : (
                      parentEdgeId: edge.parentEdgeId,
                      active: edge.cancelledAt == null,
                    );
            },
          )) {
        return phantomId == null
            ? InvitePreviewBeacon.lapsedRequest(
                id: beacon.id,
                title: beacon.title,
              )
            : null;
      }
      return InvitePreviewBeacon.visible(
        id: beacon.id,
        kind: beacon.kind,
        title: beacon.title,
        description: beacon.description,
      );
    }

    final issuerCanRead = await issuerCanReadContent();
    final canPreview = BeaconVisibility.canPreviewInvite(
      BeaconInvitePreviewFacts(
        invitationExists: true,
        invitationConsumed: codeStatus == InviteCodeStatus.consumed,
        invitationExpired: codeStatus == InviteCodeStatus.expired,
        hasBeaconId: true,
        beaconStatus: beacon.status,
        beaconAllowsForward: beacon.allowsForward,
        issuerCanReadContent: issuerCanRead,
        issuerCanForward: beacon.allowsForward && issuerCanRead,
      ),
    );
    if (!canPreview) {
      return null;
    }

    // A Post has no description of its own: its text is the root message.
    final rootId = beacon.postRootMessageId;
    final description = rootId != null
        ? (await _room?.getRoomMessageById(rootId))?.body ?? ''
        : beacon.description;

    return InvitePreviewBeacon.visible(
      id: beacon.id,
      title: beacon.title,
      description: description,
      kind: beacon.kind,
    );
  }

  Future<InviteAcceptance> accept({
    required String invitationId,
    required String userId,
    bool reportExpiry = false,
  }) =>
      _accept(invitationId, userId, byCode: false, reportExpiry: reportExpiry);

  Future<InviteAcceptance> acceptAsExisting({
    required String code,
    required String userId,
  }) => _accept(code, userId, byCode: true);

  Future<InviteAcceptance> _accept(
    String invitationId,
    String userId, {
    required bool byCode,
    bool reportExpiry = false,
  }) async {
    final invitation = await _invitationRepository.getById(
      invitationId: invitationId,
    );
    if (invitation == null) {
      throw IdNotFoundException(id: invitationId);
    }
    await _requireUnblockedInvite(invitation, userId);
    if (invitation.issuer.id == userId) {
      throw const InvitationWrongException(
        description: 'Cannot accept your own invite',
      );
    }
    if (invitation.phantomId != null && invitation.isAccepted) {
      throw const InvitationWrongException.used();
    }
    final isExpired = invitation.isExpiredWithTtl(env.invitationTTL);
    if (isExpired && reportExpiry) {
      throw const InvitationWrongException.expired();
    }
    if (isExpired || (byCode && invitation.isAccepted)) {
      throw IdNotFoundException(id: invitationId);
    }

    final beaconId = invitation.beaconId;
    if (beaconId != null) {
      final kind = await _inviteBeaconKind(beaconId);
      if (kind == BeaconKind.request) {
        return _acceptAndRecord(
          invitation: invitation,
          userId: userId,
          emitInviteAccepted: false,
          mutation: (_) => _acceptRequestInvite(invitation, userId),
        );
      }
      if (byCode) {
        return _acceptAndRecord(
          invitation: invitation,
          userId: userId,
          emitInviteAccepted: false,
          mutation: (transaction) => _acceptPostInviteOnly(
            invitation: invitation,
            beaconId: beaconId,
            userId: userId,
            transaction: transaction,
          ),
        );
      }
    }
    final alreadyFriends =
        byCode &&
        await _friendshipLookup.isReciprocalSubscribe(
          viewerId: userId,
          peerId: invitation.issuer.id,
        );
    return _acceptAndRecord(
      invitation: invitation,
      userId: userId,
      emitMutualConnection: !alreadyFriends,
      emitInviteAccepted: !alreadyFriends,
      mutation: (_) async {
        if (beaconId == null) {
          await _lockSenderAndCheckInvite(invitation, userId);
        } else {
          await _lockPostInvite(
            invitation: invitation,
            beaconId: beaconId,
            userId: userId,
          );
        }
        final claimed = await _userRepository.bindMutual(
          invitationId: invitationId,
          userId: userId,
          bindFriendship: !alreadyFriends || invitation.phantomId != null,
        );
        return InviteAcceptance.fromClaim(claimed: claimed);
      },
    );
  }

  Future<BeaconKind> _inviteBeaconKind(String beaconId) async {
    try {
      return (await _beaconRepository.getBeaconById(beaconId: beaconId)).kind;
    } on OwnerlessRequest {
      return BeaconKind.request;
    }
  }

  Future<InviteAcceptance> _acceptRequestInvite(
    InvitationEntity invitation,
    String userId,
  ) async {
    await _lockSenderAndCheckInvite(invitation, userId);
    return _userRepository.acceptRequestInvite(
      invitationId: invitation.id,
      userId: userId,
    );
  }

  Future<void> _lockSenderAndCheckInvite(
    InvitationEntity invitation,
    String userId,
  ) async {
    if (_userBlockRepository case final UserBlockWriteLocks locks) {
      await locks.lockInviteSender(invitation.issuer.id);
    }
    await _requireUnblockedInvite(invitation, userId);
  }

  Future<void> _requireUnblockedInvite(
    InvitationEntity invitation,
    String userId,
  ) async {
    if (await _userBlockRepository.isBlockedPair(
      a: userId,
      b: invitation.issuer.id,
    )) {
      throw IdNotFoundException(id: invitation.id);
    }
  }

  Future<InviteAcceptance> _acceptAndRecord({
    required InvitationEntity invitation,
    required String userId,
    required Future<InviteAcceptance> Function(AttentionTransaction transaction)
    mutation,
    bool emitMutualConnection = false,
    bool emitInviteAccepted = true,
  }) async {
    final attention = _attention!;
    Future<InviteAcceptance> acceptInvite() => attention.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final accepted = await mutation(transaction);
        if (accepted == InviteAcceptance.accepted) {
          if (emitInviteAccepted) {
            final accepter = await _userRepository.getById(userId);
            await transaction.record(
              await _attentionIntents!.inviteAccepted(
                notification: InviteAcceptedNotificationIntent(
                  inviterUserId: invitation.issuer.id,
                  accepterUserId: userId,
                  accepterDisplayName: accepter.displayName,
                  actionUrl: '/#/profile/view/$userId',
                  inviteOrigin: 'existing_account',
                  accepterHandle: accepter.handle,
                ),
                sourceEventKey: 'invitation:${invitation.id}:accepted',
              ),
            );
          }
          if (emitMutualConnection) {
            await transaction.record(
              await _attentionIntents!.mutualConnectionFormed(
                actorUserId: invitation.issuer.id,
                counterpartUserId: userId,
                sourceEventKey: 'invitation:${invitation.id}:mutual',
              ),
            );
          }
        }
        return accepted;
      },
    );
    final result = await attention.retryOnConflict(acceptInvite);
    if (invitation.phantomId != null && result.isConsumed) {
      await _phantomMergeWake.wake(invitation.id);
    }
    return result;
  }

  Future<InviteAcceptance> _acceptPostInviteOnly({
    required InvitationEntity invitation,
    required String beaconId,
    required String userId,
    required AttentionTransaction transaction,
  }) async {
    if (!await _guard.canReadContent(
      beaconId: beaconId,
      viewerId: invitation.issuer.id,
    )) {
      throw IdNotFoundException(id: invitation.id);
    }
    final beacon = await _lockPostInvite(
      invitation: invitation,
      beaconId: beaconId,
      userId: userId,
    );

    final claimed = await _userRepository.bindMutual(
      invitationId: invitation.id,
      userId: userId,
      bindFriendship: false,
      onForwardCreated: () async {
        await transaction.record(
          await _attentionIntents!.relayReceived(
            beaconId: beacon.id,
            senderId: invitation.issuer.id,
            beaconAuthorId: beacon.author.id,
            recipientIds: [userId],
            beaconKind: beacon.kind,
            sourceEventKey: 'invitation:${invitation.id}:forward',
          ),
        );
      },
    );
    return InviteAcceptance.fromClaim(claimed: claimed);
  }

  Future<bool> delete({
    required String invitationId,
    required String userId,
  }) => _invitationRepository.deleteById(
    invitationId: invitationId,
    userId: userId,
  );
}
