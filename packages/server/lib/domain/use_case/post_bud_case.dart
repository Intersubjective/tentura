import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura_server/domain/entity/post_parent_stage.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_child_create_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/post_bud_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/utils/id.dart';

/// Budding a Request from a Post (Arch §4.2, plan C3): the
/// `beaconBudFromPost` mutation and the `postBudInviteCandidates` query.
///
/// The bud runs as one transaction through
/// [BeaconChildCreatePort.createChildUnderPost] (global lock, replay, Post
/// lock and asserts, child create + publish); this case supplies the
/// Post-parent stage: the observers snapshot, the author invites with their
/// delivery edges, and closing the Post.
@Singleton(order: 2)
class PostBudCase {
  const PostBudCase(
    this._children,
    this._postBud,
    this._forwardEdges,
    this._inbox,
    this._intents,
    this._postClose,
  );

  final BeaconChildCreatePort _children;
  final PostBudPort _postBud;
  final ForwardEdgeRepositoryPort _forwardEdges;
  final InboxRepositoryPort _inbox;
  final AttentionIntentCase _intents;
  final PostCloseOperation _postClose;

  /// Buds a Request from [sourceMessageId] in [postId] (Arch §4.2).
  ///
  /// Invitees are de-duplicated in request order. A per-invitee failure does
  /// not fail the bud; it is part of the stored result. A repeated
  /// [clientCommandId] with the same input returns the stored result.
  Future<PostBudResult> budFromPost({
    required String actorUserId,
    required String postId,
    required String sourceMessageId,
    required String clientCommandId,
    required String title,
    String? description,
    String? context,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    bool primaryNeedSlugProvided = false,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? addressLabel,
    bool isDiscoverable = false,
    List<PostBudInvitee> invitees = const [],
    bool closePost = false,
  }) async {
    final normalized = _normalizeInvitees(invitees);
    final result = await _children.createChildUnderPost(
      actorUserId: actorUserId,
      postId: postId,
      sourceMessageId: sourceMessageId,
      clientCommandId: clientCommandId,
      title: title,
      description: description,
      context: context,
      tags: tags,
      needs: needs,
      primaryNeedSlug: primaryNeedSlug,
      primaryNeedSlugProvided: primaryNeedSlugProvided,
      endAt: endAt,
      startAt: startAt,
      coordinates: coordinates,
      addressLabel: addressLabel,
      isDiscoverable: isDiscoverable,
      budInput: {
        'invitees': [
          for (final invitee in normalized)
            {'userId': invitee.userId, 'note': invitee.note},
        ],
        'closePost': closePost,
      },
      stage: (stageContext) => _stage(
        stageContext,
        invitees: normalized,
        closePost: closePost,
      ),
    );
    // TODO(C8): after commit, nudge the anchor inheritance sweep (Arch §8.1,
    // same pattern as `TrustPublisherCase.nudge()`); the sweep itself and its
    // nudge hook land in plan unit C8. No anchor work inside the bud
    // transaction.
    return PostBudResult.fromJson(
      result.budResult ??
          PostBudResultJson.build(
            outcome: PostBudResultJson.outcomeCreated,
            childBeaconId: result.beaconId,
          ),
    );
  }

  /// Invite candidates for a bud from [postId] (plan C3): every member of
  /// `E(P)` except the caller, writers first. `viaUserId` is hidden when it
  /// is the caller. Only a member of `E(P)` may ask.
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String actorUserId,
    required String postId,
  }) async {
    final members = await _postBud.effectiveMemberIds(postId);
    if (!members.contains(actorUserId)) {
      throw const BeaconChildCreateForbiddenException(
        description: 'Only a member of the Post can bud a Request from it',
      );
    }
    final candidates = await _postBud.inviteCandidates(
      postId: postId,
      budderId: actorUserId,
    );
    final sorted = [...candidates]
      ..sort((a, b) {
        if (a.hasWritten != b.hasWritten) return a.hasWritten ? -1 : 1;
        return a.userId.compareTo(b.userId);
      });
    return [
      for (final c in sorted)
        PostBudInviteCandidate(
          userId: c.userId,
          warm: c.warm,
          reason: c.reason,
          hasWritten: c.hasWritten,
          pretick: c.pretick,
          viaUserId: c.viaUserId == actorUserId ? null : c.viaUserId,
        ),
    ];
  }

  /// The Post-parent stage (Arch §4.2 step 2a–b, d), run by
  /// `createChildUnderPost` inside the bud transaction with every lock held.
  Future<PostParentStageResult> _stage(
    PostParentStageContext stage, {
    required List<PostBudInvitee> invitees,
    required bool closePost,
  }) async {
    final child = stage.child;
    final budderId = stage.actorUserId;

    // (a) Observers snapshot.
    await _postBud.writeObservers(
      childId: child.id,
      postId: stage.postId,
      budderId: budderId,
    );

    // (b) Invites: eligibility under the locks (Arch §3.3).
    final candidates = {
      for (final c in await _postBud.inviteCandidates(
        postId: stage.postId,
        budderId: budderId,
      ))
        c.userId: c,
    };
    final outcomes = <String, PostBudInviteOutcome>{};
    final eligible = <PostBudInviteCandidate>[];
    for (final invitee in invitees) {
      final candidate = candidates[invitee.userId];
      final outcome = candidate == null
          ? PostBudInviteOutcome.notEligible
          : PostBudInviteOutcome.fromReason(candidate.reason);
      if (outcome == PostBudInviteOutcome.invited) {
        eligible.add(candidate!);
      } else {
        outcomes[invitee.userId] = outcome;
      }
    }

    if (eligible.isNotEmpty) {
      final warm = {for (final c in eligible) c.userId: c.warm};
      final notes = {for (final i in invitees) i.userId: i.note};
      final batch = await _forwardEdges.createBatch(
        beaconId: child.id,
        senderId: budderId,
        recipientIds: [for (final c in eligible) c.userId],
        batchId: generateId('X'),
        // The invite note is not copied into the edge note.
        noteForRecipient: (_) => '',
        sweepExemptFor: (recipientId) => warm[recipientId] ?? false,
      );
      final edges = {
        for (final created in batch.createdEdges)
          created.recipientId: created.edgeId,
      };
      final paused = batch.availabilitySkippedRecipientIds.toSet();
      for (final candidate in eligible) {
        final inviteeId = candidate.userId;
        final edgeId = edges[inviteeId];
        if (edgeId == null) {
          outcomes[inviteeId] = paused.contains(inviteeId)
              ? PostBudInviteOutcome.recipientPaused
              : PostBudInviteOutcome.notEligible;
          continue;
        }
        await _inbox.repinForAuthorInvite(
          userId: inviteeId,
          beaconId: child.id,
        );
        final note = notes[inviteeId];
        final inviteId = await _postBud.insertInvite(
          beaconId: child.id,
          inviterId: budderId,
          inviteeId: inviteeId,
          sourcePostId: stage.postId,
          forwardEdgeId: edgeId,
          warm: candidate.warm,
          note: note,
        );
        await stage.transaction.record(
          await _intents.authorInviteReceived(
            beaconId: child.id,
            inviteId: inviteId,
            inviterUserId: budderId,
            inviteeUserId: inviteeId,
            sourceEventKey: 'author_invite:$inviteId',
            note: note ?? '',
          ),
        );
        outcomes[inviteeId] = PostBudInviteOutcome.invited;
      }
    }

    final results = [
      for (final invitee in invitees)
        PostBudInviteeResult(
          userId: invitee.userId,
          outcome: outcomes[invitee.userId]!,
        ),
    ];
    return PostParentStageResult(
      invitedCount: results
          .where((r) => r.outcome == PostBudInviteOutcome.invited)
          .length,
      invitees: [for (final r in results) r.toJson()],
      afterNotice: closePost
          ? () => _postClose.closeForBud(
              postId: stage.postId,
              childBeaconId: child.id,
              title: child.title,
              actorId: budderId,
            )
          : null,
    );
  }

  /// Trims ids and notes, drops blank ids, de-duplicates in request order
  /// (first occurrence wins). An empty note is no note.
  static List<PostBudInvitee> _normalizeInvitees(
    List<PostBudInvitee> invitees,
  ) {
    final seen = <String>{};
    return [
      for (final invitee in invitees)
        if (invitee.userId.trim() case final id
            when id.isNotEmpty && seen.add(id))
          PostBudInvitee(
            userId: id,
            note: switch (invitee.note?.trim()) {
              final String n when n.isNotEmpty => n,
              _ => null,
            },
          ),
    ];
  }
}
