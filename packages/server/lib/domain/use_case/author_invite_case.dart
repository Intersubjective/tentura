import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/author_invite_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/post_bud_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/admission_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

/// The author-invite lifecycle (Arch §5, plan C4): later invites, accept,
/// decline and withdraw. Supersede lives in `HelpOfferCase.offerHelp` and
/// `CoordinationCase.acceptHelpOffer`; expiry is the m0245 trigger; block
/// cleanup is in `UserBlockCase`.
///
/// Every operation runs in one mutating unit and takes the locks of Arch §4.1
/// in order: the global hierarchy lock and the source Post
/// ([AuthorInvitePort.lockScope]), the child (advisory 4242 + row), then the
/// invite row; mutable state is re-validated after locking.
@Singleton(order: 2)
class AuthorInviteCase {
  const AuthorInviteCase(
    this._attention,
    this._intents,
    this._settlement,
    this._admission,
    this._invites,
    this._postBud,
    this._beacons,
    this._closure,
    this._forwardEdges,
    this._inbox,
    this._blocks,
    this._commitments,
    this._forwardCase,
  );

  final TransactionalAttentionCase _attention;
  final AttentionIntentCase _intents;
  final AttentionSystemSettlementPort _settlement;
  final AdmissionOperation _admission;
  final AuthorInvitePort _invites;
  final PostBudPort _postBud;
  final BeaconRepositoryPort _beacons;
  final ClosureCase _closure;
  final ForwardEdgeRepositoryPort _forwardEdges;
  final InboxRepositoryPort _inbox;
  final UserBlockRepositoryPort _blocks;
  final CommitmentRepositoryPort _commitments;
  final ForwardCase _forwardCase;

  /// The caller's pending invites, for the «Для вас» invite card (plan C6).
  Future<List<PendingAuthorInvite>> myPendingInvites({
    required String actorUserId,
  }) => _invites.listPendingForInvitee(actorUserId);

  /// Every invite on [beaconId] for its author's People tab (plan C6). Anyone
  /// else, an invitee or an observer included, gets an empty list rather than
  /// an error, so the call is no oracle for the invites of others.
  Future<List<AuthorInvite>> beaconInvites({
    required String actorUserId,
    required String beaconId,
  }) => _invites.listForAuthor(beaconId: beaconId, authorId: actorUserId);

  /// The snapshot observers of [beaconId] for its author's People tab, the
  /// targets of a later invite (plan D4). Anyone but the author gets an
  /// empty list, like [beaconInvites].
  Future<List<String>> budObservers({
    required String actorUserId,
    required String beaconId,
  }) => _postBud.observerIdsForAuthor(
    childId: beaconId,
    authorId: actorUserId,
  );

  /// A later invite from the child's People tab (Arch §3.3): only the child
  /// author, only for a snapshot observer, under the same eligibility rules
  /// as the bud. Ineligible targets are an outcome, not an error.
  Future<AuthorInviteCreateResult> create({
    required String actorUserId,
    required String beaconId,
    required String inviteeId,
    String? note,
  }) async {
    final child = await _beacons.getBeaconById(beaconId: beaconId);
    final postId = _requireBuddedRequest(child);
    if (child.author.id != actorUserId) {
      throw const UnauthorizedException(
        description: 'Only the Request author can invite',
      );
    }
    final trimmedNote = switch (note?.trim()) {
      final String n when n.isNotEmpty => n,
      _ => null,
    };
    return _attention.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        // Steps 1–2: the Post lock keeps N5 from racing a concurrent bud.
        await _invites.lockScope(postId);
        final locked = await _lockChild(beaconId, actorUserId);
        if (locked.author.id != actorUserId) {
          throw const UnauthorizedException(
            description: 'Only the Request author can invite',
          );
        }
        if (!locked.status.isOpenFamily) {
          throw const AuthorInviteRequestNotOpenException();
        }

        final candidate = await _postBud.laterInviteCandidate(
          childId: beaconId,
          postId: postId,
          inviterId: actorUserId,
          inviteeId: inviteeId,
        );
        final outcome = candidate == null
            ? PostBudInviteOutcome.notEligible
            : PostBudInviteOutcome.fromReason(candidate.reason);
        if (outcome != PostBudInviteOutcome.invited) {
          return AuthorInviteCreateResult(outcome: outcome);
        }
        final warm = candidate!.warm;

        final batch = await _forwardEdges.createBatch(
          beaconId: beaconId,
          senderId: actorUserId,
          recipientIds: [inviteeId],
          batchId: generateId('X'),
          // The invite note is not copied into the edge note.
          noteForRecipient: (_) => '',
          sweepExemptFor: (_) => warm,
        );
        if (batch.availabilitySkippedRecipientIds.contains(inviteeId)) {
          return const AuthorInviteCreateResult(
            outcome: PostBudInviteOutcome.recipientPaused,
          );
        }
        // `createBatch` does not report an edge it reused: read it back.
        final edge = await _forwardEdges.findActiveEdge(
          beaconId: beaconId,
          senderId: actorUserId,
          recipientId: inviteeId,
        );
        if (edge == null) {
          return const AuthorInviteCreateResult(
            outcome: PostBudInviteOutcome.notEligible,
          );
        }
        // A reused ordinary edge is not exempt; a warm invite must be (I8).
        if (warm) await _invites.markEdgeSweepExempt(edge.id);

        await _inbox.repinForAuthorInvite(
          userId: inviteeId,
          beaconId: beaconId,
        );
        final inviteId = await _postBud.insertInvite(
          beaconId: beaconId,
          inviterId: actorUserId,
          inviteeId: inviteeId,
          sourcePostId: postId,
          forwardEdgeId: edge.id,
          warm: warm,
          note: trimmedNote,
        );
        if (inviteId == null) {
          return const AuthorInviteCreateResult(
            outcome: PostBudInviteOutcome.alreadyInvited,
          );
        }
        await transaction.record(
          await _intents.authorInviteReceived(
            beaconId: beaconId,
            inviteId: inviteId,
            inviterUserId: actorUserId,
            inviteeUserId: inviteeId,
            sourceEventKey: 'author_invite:$inviteId',
            note: trimmedNote ?? '',
          ),
        );
        return AuthorInviteCreateResult(
          outcome: PostBudInviteOutcome.invited,
          inviteId: inviteId,
        );
      },
    );
  }

  /// The invitee accepts (Arch §5.1): both confirmations exist, so the shared
  /// admission operation admits them with the inviter as the confirming
  /// author. A repeated accept returns the accepted invite without new events.
  /// A Request in review refuses with [AuthorInviteRequestNotOpenException];
  /// the invite stays pending, because review can reopen.
  Future<AuthorInvite> accept({
    required String actorUserId,
    required String inviteId,
  }) async {
    final found = await _findFor(inviteId, inviteeId: actorUserId);
    return _attention.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        final (beacon, invite) = await _lockInvite(found, actorUserId);
        if (invite.status == AuthorInviteStatus.accepted) return invite;
        if (!invite.isPending) throw const AuthorInviteNotPendingException();
        if (!beacon.status.isOpenFamily) {
          throw const AuthorInviteRequestNotOpenException();
        }
        if (await _blocks.isBlockedPair(
          a: invite.inviterId,
          b: invite.inviteeId,
        )) {
          throw const UnauthorizedException(
            description: 'Cannot accept an invitation from a blocked user',
          );
        }
        final events = await _commitments.eventsForPair(
          beaconId: beacon.id,
          userId: actorUserId,
        );
        if (currentStakeState(events) == CommitmentStakeState.acknowledged) {
          throw HelpOfferCoordinationException(
            coordinationCode: HelpOfferCoordinationExceptionCode
                .commitmentAlreadyAcknowledged,
          );
        }

        await _admission.admitWithConfirmations(
          beacon: beacon,
          helperId: actorUserId,
          confirmingAuthorId: invite.inviterId,
          actorId: actorUserId,
          transaction: transaction,
          invite: invite,
          attention: () => _intents.authorInviteAccepted(
            beaconId: beacon.id,
            inviterUserId: invite.inviterId,
            inviteeUserId: actorUserId,
            sourceEventKey: 'author_invite_accepted:${invite.id}',
          ),
        );
        return _end(invite, AuthorInviteStatus.accepted, actorUserId);
      },
    );
  }

  /// «Не смогу» (Arch §5.2): the existing inbox decline (`status = 2`, which
  /// resolves the contact as declined with no evidence) and the invite
  /// becomes declined, in one transaction. A repeated decline is a no-op.
  Future<AuthorInvite> decline({
    required String actorUserId,
    required String inviteId,
  }) async {
    final found = await _findFor(inviteId, inviteeId: actorUserId);
    return _attention.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        final (beacon, invite) = await _lockInvite(found, actorUserId);
        if (invite.status == AuthorInviteStatus.declined) return invite;
        if (!invite.isPending) throw const AuthorInviteNotPendingException();
        await _inbox.setStatus(
          userId: actorUserId,
          beaconId: beacon.id,
          status: 2,
          rejectionMessage: '',
        );
        final ended = await _end(
          invite,
          AuthorInviteStatus.declined,
          actorUserId,
        );
        await transaction.record(
          await _intents.authorInviteDeclined(
            beaconId: beacon.id,
            inviterUserId: invite.inviterId,
            inviteeUserId: actorUserId,
            sourceEventKey: 'author_invite_declined:${invite.id}',
          ),
        );
        return ended;
      },
    );
  }

  /// The inviter withdraws (Arch §5.4): the confirmation is revoked whatever
  /// happens to the edge. The delivery edge is cancelled only when the
  /// ordinary forward-cancel rules allow it; otherwise it stays as an
  /// ordinary forward, and its contact is resolved without evidence.
  Future<AuthorInvite> withdraw({
    required String actorUserId,
    required String inviteId,
  }) async {
    final found = await _invites.fetchById(inviteId);
    if (found == null || found.inviterId != actorUserId) {
      throw const AuthorInviteNotFoundException();
    }
    return _attention.runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        final (_, invite) = await _lockInvite(found, actorUserId);
        if (invite.status == AuthorInviteStatus.withdrawn) return invite;
        if (!invite.isPending) throw const AuthorInviteNotPendingException();
        final ended = await _end(
          invite,
          AuthorInviteStatus.withdrawn,
          actorUserId,
        );
        final edgeId = invite.forwardEdgeId;
        if (edgeId != null) {
          final cancelled = await _forwardCase.cancelForward(
            edgeId: edgeId,
            senderId: actorUserId,
          );
          if (!cancelled) {
            await _invites.resolveContactWithoutEvidence(edgeId);
          }
        }
        return ended;
      },
    );
  }

  /// The parent Post of a budded Request; refuses anything else.
  static String _requireBuddedRequest(BeaconEntity child) {
    final postId = child.parentBeaconId;
    if (child.kind != BeaconKind.request || postId == null) {
      throw const AuthorInviteNotFoundException(
        description: 'Not a Request budded from a Post',
      );
    }
    return postId;
  }

  Future<AuthorInvite> _findFor(
    String inviteId, {
    required String inviteeId,
  }) async {
    final invite = await _invites.fetchById(inviteId);
    if (invite == null || invite.inviteeId != inviteeId) {
      throw const AuthorInviteNotFoundException();
    }
    return invite;
  }

  /// Lock-order step 3: the child advisory lock and its row.
  Future<BeaconEntity> _lockChild(String beaconId, String actorUserId) async {
    await _closure.lockRequest(beaconId);
    return _beacons.runInBeaconStateTransaction(
      beaconId: beaconId,
      userId: actorUserId,
      fn: (locked) async => locked,
    );
  }

  /// Steps 1–4 for an existing invite; returns the locked child and invite.
  Future<(BeaconEntity, AuthorInvite)> _lockInvite(
    AuthorInvite found,
    String actorUserId,
  ) async {
    await _invites.lockScope(found.sourcePostId);
    final beacon = await _lockChild(found.beaconId, actorUserId);
    final invite = await _invites.lockById(found.id);
    if (invite == null) throw const AuthorInviteNotFoundException();
    return (beacon, invite);
  }

  /// Ends the pending [invite] with [status] and clears the invitee's
  /// `authorInviteReceived` receipt.
  Future<AuthorInvite> _end(
    AuthorInvite invite,
    AuthorInviteStatus status,
    String actorUserId,
  ) async {
    final ended = await _invites.resolve(
      inviteId: invite.id,
      status: status,
      resolvedBy: actorUserId,
    );
    if (ended == null) throw const AuthorInviteNotPendingException();
    await _settlement.clearAuthorInviteReceived(
      beaconId: invite.beaconId,
      inviteeId: invite.inviteeId,
    );
    return ended;
  }
}
