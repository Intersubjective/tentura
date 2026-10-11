import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/post_parent_stage.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_creation_policy.dart';
import 'package:tentura_server/domain/policy/beacon_promotion_eligibility_policy.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_child_create_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/post_bud_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

final class _PromotionRaceLost implements Exception {
  _PromotionRaceLost(this.existingChildBeaconId);

  final String existingChildBeaconId;
}

/// Authorized nested child create/publish command (§3.4).
@Singleton(as: BeaconChildCreatePort, order: 2)
final class BeaconChildCreateCase extends UseCaseBase
    implements BeaconChildCreatePort {
  BeaconChildCreateCase(
    this._beaconRepository,
    this._hierarchyRepository,
    this._commands,
    this._guard,
    this._notificationContext, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    PostLockPort? postLock,
    PostBudPort? postBud,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention,
       _postLock = postLock,
       _postBud = postBud;

  final BeaconRepositoryPort _beaconRepository;
  final BeaconHierarchyRepositoryPort _hierarchyRepository;
  final BeaconHierarchyCommandPort _commands;
  final BeaconAccessGuard _guard;
  final BeaconRoomNotificationContextPort _notificationContext;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;
  final PostLockPort? _postLock;
  final PostBudPort? _postBud;

  /// Prefix of a bud command's `normalized_input_hash` (Arch §2.6), so a
  /// `clientCommandId` reused across the two endpoints conflicts.
  static const budInputHashPrefix = 'bud:';

  Future<BeaconChildCreateResult> createChild({
    required String actorUserId,
    required String parentBeaconId,
    String? sourceMessageId,
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
    required bool draft,
  }) async {
    await _enforceCreateRateLimit(actorUserId);

    final trimmedCommandId = clientCommandId.trim();
    if (trimmedCommandId.isEmpty) {
      throw const BeaconChildCommandConflictException(
        description: 'Client command id is required',
      );
    }

    final normalizedNeeds = BeaconCreationPolicy.normalizeNeeds(needs);
    final resolvedPrimary = BeaconCreationPolicy.resolvePrimaryNeedSlug(
      needs: normalizedNeeds,
      primaryNeedSlug: primaryNeedSlug,
      primaryNeedSlugProvided: primaryNeedSlugProvided,
    );

    final isPromotion =
        sourceMessageId != null && sourceMessageId.trim().isNotEmpty;
    final normalizedSourceMessageId =
        isPromotion ? sourceMessageId.trim() : null;

    var normalizedTitle = title.trim();
    var normalizedDescription = isPromotion
        ? BeaconCreationPolicy.normalizeChildDescription(description)
        : BeaconCreationPolicy.normalizeStandaloneDescription(description);

    if (!isPromotion && !draft) {
      BeaconCreationPolicy.assertPublishTitle(normalizedTitle);
    }

    final normalizedInputHash = _normalizedInputHash(
      parentBeaconId: parentBeaconId,
      sourceMessageId: normalizedSourceMessageId,
      draft: draft,
      title: normalizedTitle,
      description: normalizedDescription,
      context: BeaconCreationPolicy.trimOrNull(context),
      tags: BeaconCreationPolicy.trimOrNull(tags),
      needs: normalizedNeeds?.join(','),
      primaryNeedSlug: resolvedPrimary,
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      startAt: startAt?.toUtc().toIso8601String(),
      endAt: endAt?.toUtc().toIso8601String(),
      addressLabel: BeaconCreationPolicy.trimOrNull(addressLabel),
    );

    final creationContext = isPromotion
        ? BeaconCreationContextPromotedChild(
            parentBeaconId: parentBeaconId,
            sourceMessageId: normalizedSourceMessageId!,
          )
        : BeaconCreationContextChild(parentBeaconId: parentBeaconId);

    try {
      return await _attention!.runAction(
        actorUserId: actorUserId,
        action: (transaction) async {
          await _hierarchyRepository.lockMutationScope();

          final prior = await _commands.findCommand(
            actorUserId: actorUserId,
            clientCommandId: trimmedCommandId,
          );
          if (prior != null) {
            if (prior.deleted) {
              throw const BeaconChildCommandGoneException();
            }
            if (prior.normalizedInputHash != normalizedInputHash) {
              throw const BeaconChildCommandConflictException();
            }
            await _lockCreateScope(
              actorUserId: actorUserId,
              clientCommandId: trimmedCommandId,
              parentBeaconId: parentBeaconId,
              sourceMessageId: normalizedSourceMessageId,
              childBeaconId: prior.resultBeaconId,
            );
            await _assertParentCreateAllowed(
              actorUserId: actorUserId,
              parentBeaconId: parentBeaconId,
            );
            return _replayPriorCommand(
              actorUserId: actorUserId,
              prior: prior,
            );
          }

          await _lockCreateScope(
            actorUserId: actorUserId,
            clientCommandId: trimmedCommandId,
            parentBeaconId: parentBeaconId,
            sourceMessageId: normalizedSourceMessageId,
          );
          await _assertParentCreateAllowed(
            actorUserId: actorUserId,
            parentBeaconId: parentBeaconId,
          );

          BeaconPromotionSourceFacts? sourceFacts;
          if (isPromotion) {
            sourceFacts = await _loadEligibleSourceFacts(
              parentBeaconId: parentBeaconId,
              sourceMessageId: normalizedSourceMessageId!,
            );
            normalizedDescription =
                BeaconCreationPolicy.normalizeChildDescription(
                  sourceFacts.body,
                );
          } else if (!draft) {
            BeaconCreationPolicy.assertPublishTitle(normalizedTitle);
          }

          if (!draft && isPromotion) {
            final existingChildId =
                await _commands.findPublishedChildForSourceMessage(
                  sourceMessageId: normalizedSourceMessageId!,
                );
            if (existingChildId != null) {
              return _recordAndReturnAlreadyPromoted(
                actorUserId: actorUserId,
                clientCommandId: trimmedCommandId,
                normalizedInputHash: normalizedInputHash,
                creationContext: creationContext,
                existingChildBeaconId: existingChildId,
              );
            }
          }

          final child = await _beaconRepository.createChildBeacon(
            authorId: actorUserId,
            parentBeaconId: parentBeaconId,
            title: normalizedTitle,
            description: normalizedDescription,
            context: BeaconCreationPolicy.trimOrNull(context),
            latitude: coordinates?.lat,
            longitude: coordinates?.long,
            startAt: startAt,
            endAt: endAt,
            tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
            needs: normalizedNeeds,
            primaryNeedSlug: resolvedPrimary,
            addressLabel: BeaconCreationPolicy.trimOrNull(addressLabel),
            draft: draft,
          );

          if (isPromotion) {
            await _commands.upsertDraftPromotion(
              childBeaconId: child.id,
              parentBeaconId: parentBeaconId,
              sourceMessageId: normalizedSourceMessageId,
              promoterUserId: actorUserId,
            );
          }

          var outcome = BeaconChildCommandOutcome.created;
          var resultBeacon = child;

          if (!draft) {
            resultBeacon = await _publishChildInTransaction(
              transaction: transaction,
              actorUserId: actorUserId,
              child: child,
              parentBeaconId: parentBeaconId,
              sourceMessageId: normalizedSourceMessageId,
            );
          }

          await _commands.recordCreateOutcome(
            actorUserId: actorUserId,
            clientCommandId: trimmedCommandId,
            normalizedInputHash: normalizedInputHash,
            creationContext: creationContext,
            outcome: outcome,
            resultBeaconId: resultBeacon.id,
          );

          return BeaconChildCreateResult(
            outcome: outcome,
            beaconId: resultBeacon.id,
            beacon: resultBeacon,
          );
        },
      );
    } on _PromotionRaceLost catch (race) {
      return _alreadyPromotedResult(
        actorUserId: actorUserId,
        existingChildBeaconId: race.existingChildBeaconId,
      );
    }
  }

  Future<BeaconEntity> publishDraft({
    required String actorUserId,
    required String childBeaconId,
  }) async {
    final child = await _beaconRepository.getBeaconById(
      beaconId: childBeaconId,
      filterByUserId: actorUserId,
    );
    if (child.parentBeaconId == null) {
      throw const BeaconCreateException(
        description: 'Request not found or not owned',
      );
    }
    if (child.status != BeaconStatus.draft) {
      return child;
    }

    BeaconCreationPolicy.assertPublishTitle(child.title);

    final promotion = await _commands.loadPromotionForChild(childBeaconId);
    final sourceMessageId = promotion?.sourceMessageId;

    try {
      return await _attention!.runAction(
        actorUserId: actorUserId,
        action: (transaction) async {
          await _hierarchyRepository.lockMutationScope();
          await _lockPublishScope(
            childBeaconId: childBeaconId,
            parentBeaconId: child.parentBeaconId!,
            sourceMessageId: sourceMessageId,
          );
          await _assertParentCreateAllowed(
            actorUserId: actorUserId,
            parentBeaconId: child.parentBeaconId!,
          );
          if (sourceMessageId != null) {
            await _loadEligibleSourceFacts(
              parentBeaconId: child.parentBeaconId!,
              sourceMessageId: sourceMessageId,
            );
          } else if (promotion != null) {
            throw const BeaconPromotionSourceInvalidException();
          }

          return _publishChildInTransaction(
            transaction: transaction,
            actorUserId: actorUserId,
            child: child,
            parentBeaconId: child.parentBeaconId!,
            sourceMessageId: sourceMessageId,
          );
        },
      );
    } on _PromotionRaceLost catch (race) {
      final readableId = await _readableChildId(
        viewerId: actorUserId,
        childBeaconId: race.existingChildBeaconId,
      );
      throw BeaconSourceAlreadyPromotedException(
        existingChildBeaconId: readableId,
      );
    }
  }

  /// The only entry point for a child Request under a Post: budding
  /// (Arch §3.1, §4.2). It shares the child pipeline with [createChild] but:
  /// - replays a stored `bud_result` right after the global lock and before
  ///   any parent assert, so a replay works after the Post is closed;
  /// - takes the Post lock (Arch §4.1) before the create-scope locks;
  /// - asserts the Post branch: open Post, actor in `E(P)`, own source
  ///   message;
  /// - keeps the client's title and description (no source-body override);
  /// - persists [isDiscoverable] (part of the input hash);
  /// - runs [stage] after publish, then inserts the `childCreated` notice
  ///   with a title snapshot and `invitedCount`, with no attention receipts;
  /// - stores `bud_result` with the outcome, child id and invitees.
  ///
  /// [budInput] is the rest of the caller's normalised input (invitees and
  /// notes, `closePost`); it goes into the `bud:`-prefixed input hash.
  @override
  Future<BeaconChildCreateResult> createChildUnderPost({
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
    Map<String, Object?> budInput = const {},
    PostParentStage? stage,
  }) async {
    await _enforceCreateRateLimit(actorUserId);

    final trimmedCommandId = clientCommandId.trim();
    if (trimmedCommandId.isEmpty) {
      throw const BeaconChildCommandConflictException(
        description: 'Client command id is required',
      );
    }
    final normalizedSourceMessageId = sourceMessageId.trim();
    if (normalizedSourceMessageId.isEmpty) {
      throw const BeaconPromotionSourceInvalidException(
        description: 'A bud needs a source message',
      );
    }

    final normalizedNeeds = BeaconCreationPolicy.normalizeNeeds(needs);
    final resolvedPrimary = BeaconCreationPolicy.resolvePrimaryNeedSlug(
      needs: normalizedNeeds,
      primaryNeedSlug: primaryNeedSlug,
      primaryNeedSlugProvided: primaryNeedSlugProvided,
    );
    final normalizedTitle = title.trim();
    BeaconCreationPolicy.assertPublishTitle(normalizedTitle);
    final normalizedDescription =
        BeaconCreationPolicy.normalizeChildDescription(description);
    final normalizedContext = BeaconCreationPolicy.trimOrNull(context);
    final normalizedAddressLabel = BeaconCreationPolicy.trimOrNull(
      addressLabel,
    );

    final normalizedInputHash =
        budInputHashPrefix +
        _normalizedInputHash(
          parentBeaconId: postId,
          sourceMessageId: normalizedSourceMessageId,
          draft: false,
          title: normalizedTitle,
          description: normalizedDescription,
          context: normalizedContext,
          tags: BeaconCreationPolicy.trimOrNull(tags),
          needs: normalizedNeeds?.join(','),
          primaryNeedSlug: resolvedPrimary,
          latitude: coordinates?.lat,
          longitude: coordinates?.long,
          startAt: startAt?.toUtc().toIso8601String(),
          endAt: endAt?.toUtc().toIso8601String(),
          addressLabel: normalizedAddressLabel,
          extra: {'bud': budInput, 'isDiscoverable': isDiscoverable},
        );

    final creationContext = BeaconCreationContextPromotedChild(
      parentBeaconId: postId,
      sourceMessageId: normalizedSourceMessageId,
    );

    try {
      return await _attention!.runAction(
        actorUserId: actorUserId,
        action: (transaction) async {
          await _hierarchyRepository.lockMutationScope();

          // Replay before any parent assert (Arch §2.6).
          final prior = await _commands.findCommand(
            actorUserId: actorUserId,
            clientCommandId: trimmedCommandId,
          );
          if (prior != null) {
            return _replayPriorBud(
              actorUserId: actorUserId,
              prior: prior,
              normalizedInputHash: normalizedInputHash,
            );
          }

          await _postLock!.lockForPostMutation(postId);
          await _lockCreateScope(
            actorUserId: actorUserId,
            clientCommandId: trimmedCommandId,
            parentBeaconId: postId,
            sourceMessageId: normalizedSourceMessageId,
          );
          await _assertPostParentBudAllowed(
            actorUserId: actorUserId,
            postId: postId,
          );
          await _loadOwnBudSource(
            actorUserId: actorUserId,
            postId: postId,
            sourceMessageId: normalizedSourceMessageId,
          );

          final existingChildId = await _commands
              .findPublishedChildForSourceMessage(
                sourceMessageId: normalizedSourceMessageId,
              );
          if (existingChildId != null) {
            return _recordAndReturnAlreadyPromoted(
              actorUserId: actorUserId,
              clientCommandId: trimmedCommandId,
              normalizedInputHash: normalizedInputHash,
              creationContext: creationContext,
              existingChildBeaconId: existingChildId,
              storeBudResult: true,
            );
          }

          final created = await _beaconRepository.createChildBeacon(
            authorId: actorUserId,
            parentBeaconId: postId,
            title: normalizedTitle,
            description: normalizedDescription,
            context: normalizedContext,
            latitude: coordinates?.lat,
            longitude: coordinates?.long,
            startAt: startAt,
            endAt: endAt,
            tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
            needs: normalizedNeeds,
            primaryNeedSlug: resolvedPrimary,
            addressLabel: normalizedAddressLabel,
            isDiscoverable: isDiscoverable,
            draft: false,
          );
          await _commands.upsertDraftPromotion(
            childBeaconId: created.id,
            parentBeaconId: postId,
            sourceMessageId: normalizedSourceMessageId,
            promoterUserId: actorUserId,
          );
          final child = await _publishChildInTransaction(
            transaction: transaction,
            actorUserId: actorUserId,
            child: created,
            parentBeaconId: postId,
            sourceMessageId: normalizedSourceMessageId,
            withNotice: false,
          );

          final staged =
              await stage?.call(
                PostParentStageContext(
                  transaction: transaction,
                  actorUserId: actorUserId,
                  postId: postId,
                  sourceMessageId: normalizedSourceMessageId,
                  child: child,
                ),
              ) ??
              const PostParentStageResult();

          // The single notice for a Post parent: a title snapshot (observers
          // only can read the child) and no attention receipts (Arch §4.2c).
          await _commands.insertChildCreationNotice(
            parentBeaconId: postId,
            childBeaconId: child.id,
            sourceMessageId: normalizedSourceMessageId,
            actorUserId: actorUserId,
            title: normalizedTitle,
            invitedCount: staged.invitedCount,
          );
          await staged.afterNotice?.call();

          final budResult = PostBudResultJson.build(
            outcome: PostBudResultJson.outcomeCreated,
            childBeaconId: child.id,
            invitees: staged.invitees,
          );
          await _commands.recordCreateOutcome(
            actorUserId: actorUserId,
            clientCommandId: trimmedCommandId,
            normalizedInputHash: normalizedInputHash,
            creationContext: creationContext,
            outcome: BeaconChildCommandOutcome.created,
            resultBeaconId: child.id,
            budResult: budResult,
          );
          return BeaconChildCreateResult(
            outcome: BeaconChildCommandOutcome.created,
            beaconId: child.id,
            beacon: child,
            budResult: budResult,
          );
        },
      );
    } on _PromotionRaceLost catch (race) {
      // Unreachable while the Post lock serializes buds; kept for parity.
      final result = await _alreadyPromotedResult(
        actorUserId: actorUserId,
        existingChildBeaconId: race.existingChildBeaconId,
      );
      return BeaconChildCreateResult(
        outcome: result.outcome,
        beaconId: result.beaconId,
        budResult: PostBudResultJson.build(
          outcome: PostBudResultJson.outcomeAlreadyPromoted,
          childBeaconId: result.beaconId,
        ),
      );
    }
  }

  Future<BeaconChildCreateResult> _replayPriorBud({
    required String actorUserId,
    required BeaconChildCommandRecord prior,
    required String normalizedInputHash,
  }) async {
    if (prior.deleted) {
      throw const BeaconChildCommandGoneException();
    }
    if (prior.normalizedInputHash != normalizedInputHash) {
      throw const BeaconChildCommandConflictException();
    }
    final budResult = prior.budResult;
    if (budResult == null) {
      // Same `bud:` hash without a stored result: not written by a bud.
      throw const BeaconChildCommandConflictException();
    }
    return BeaconChildCreateResult(
      outcome: BeaconChildCommandOutcome.replayed,
      beaconId: prior.resultBeaconId,
      budResult: budResult,
    );
  }

  /// Post branch of the parent asserts (Arch §3.1). Membership first, so a
  /// non-member learns nothing about the Post's kind or status.
  Future<void> _assertPostParentBudAllowed({
    required String actorUserId,
    required String postId,
  }) async {
    final members = await _postBud!.effectiveMemberIds(postId);
    if (!members.contains(actorUserId)) {
      throw const BeaconChildCreateForbiddenException();
    }
    final post = await _beaconRepository.getBeaconById(beaconId: postId);
    if (post.kind != BeaconKind.post) {
      throw const BeaconChildCreateForbiddenException(
        description: 'Only a Post can be budded',
      );
    }
    if (post.status != BeaconStatus.open) {
      throw const PostNotOpenException();
    }
  }

  /// The source must be an eligible message of the Post written by the
  /// budder; for the Post author that includes the root message.
  Future<BeaconPromotionSourceFacts> _loadOwnBudSource({
    required String actorUserId,
    required String postId,
    required String sourceMessageId,
  }) async {
    final facts = await _commands.loadPromotionSourceFacts(
      parentBeaconId: postId,
      sourceMessageId: sourceMessageId,
    );
    if (facts == null) {
      throw const BeaconPromotionSourceInvalidException();
    }
    if (facts.authorId != actorUserId) {
      throw const BudSourceNotOwnMessageException();
    }
    if (!BeaconPromotionEligibilityPolicy.isEligible(facts)) {
      throw const BeaconPromotionSourceInvalidException();
    }
    return facts;
  }

  Future<BeaconChildCreateResult> _replayPriorCommand({
    required String actorUserId,
    required BeaconChildCommandRecord prior,
  }) async {
    if (prior.outcome == BeaconChildCommandOutcome.alreadyPromoted) {
      return BeaconChildCreateResult(
        outcome: BeaconChildCommandOutcome.alreadyPromoted,
        beaconId: prior.resultBeaconId,
      );
    }
    if (prior.resultBeaconId == null) {
      throw const BeaconChildCommandGoneException();
    }
    final beacon = await _beaconRepository.getBeaconById(
      beaconId: prior.resultBeaconId!,
      filterByUserId: actorUserId,
    );
    return BeaconChildCreateResult(
      outcome: BeaconChildCommandOutcome.replayed,
      beaconId: beacon.id,
      beacon: beacon,
    );
  }

  Future<BeaconChildCreateResult> _recordAndReturnAlreadyPromoted({
    required String actorUserId,
    required String clientCommandId,
    required String normalizedInputHash,
    required BeaconCreationContext creationContext,
    required String existingChildBeaconId,
    bool storeBudResult = false,
  }) async {
    final readableId = await _readableChildId(
      viewerId: actorUserId,
      childBeaconId: existingChildBeaconId,
    );
    final budResult = storeBudResult
        ? PostBudResultJson.build(
            outcome: PostBudResultJson.outcomeAlreadyPromoted,
            childBeaconId: readableId,
          )
        : null;
    await _commands.recordCreateOutcome(
      actorUserId: actorUserId,
      clientCommandId: clientCommandId,
      normalizedInputHash: normalizedInputHash,
      creationContext: creationContext,
      outcome: BeaconChildCommandOutcome.alreadyPromoted,
      resultBeaconId: readableId,
      budResult: budResult,
    );
    return BeaconChildCreateResult(
      outcome: BeaconChildCommandOutcome.alreadyPromoted,
      beaconId: readableId,
      budResult: budResult,
    );
  }

  Future<BeaconEntity> _publishChildInTransaction({
    required AttentionTransaction transaction,
    required String actorUserId,
    required BeaconEntity child,
    required String parentBeaconId,
    String? sourceMessageId,
    bool withNotice = true,
  }) async {
    if (sourceMessageId != null) {
      try {
        await _commands.markPromotionPublished(
          childBeaconId: child.id,
          parentBeaconId: parentBeaconId,
          sourceMessageId: sourceMessageId,
          promoterUserId: actorUserId,
        );
      } on BeaconPromotionPublishConflict catch (conflict) {
        throw _PromotionRaceLost(conflict.existingChildBeaconId);
      }
    }

    final published = await _beaconRepository.publishChildDraft(
      childBeaconId: child.id,
      actorId: actorUserId,
    );
    if (!withNotice) {
      return published;
    }

    final noticeMessageId = await _commands.insertChildCreationNotice(
      parentBeaconId: parentBeaconId,
      childBeaconId: child.id,
      sourceMessageId: sourceMessageId,
      actorUserId: actorUserId,
    );

    await _recordCreationNoticeAttention(
      transaction: transaction,
      parentBeaconId: parentBeaconId,
      messageId: noticeMessageId,
      actorUserId: actorUserId,
    );

    return published;
  }

  Future<void> _recordCreationNoticeAttention({
    required AttentionTransaction transaction,
    required String parentBeaconId,
    required String messageId,
    required String actorUserId,
  }) async {
    final context = await _notificationContext.loadContextForBeacon(
      parentBeaconId,
    );
    final recipientUserIds = <String>{
      context.beaconAuthorId,
      ...context.stewardUserIds,
      ...context.admittedUserIds,
    }..removeWhere((id) => id.isEmpty || id == actorUserId);

    final intent = await _attentionIntents!.roomMessagePosted(
      beaconId: parentBeaconId,
      messageId: messageId,
      actorUserId: actorUserId,
      recipientUserIds: recipientUserIds,
      excerpt: '',
      sourceEventKey: 'child_created_notice:$messageId',
    );
    if (intent.recipients.isNotEmpty) {
      await transaction.record(intent);
    }
  }

  Future<void> _enforceCreateRateLimit(String userId) async {
    final recent = await _beaconRepository.countRecentByAuthor(
      userId: userId,
      window: env.beaconCreateRateWindow,
    );
    if (recent >= env.beaconCreateMaxPerUser) {
      logger.info('beacon child create rate-limited for user $userId');
      throw const RateLimitedException(
        description: 'Too many requests created recently, please wait',
      );
    }
  }

  Future<void> _assertParentCreateAllowed({
    required String actorUserId,
    required String parentBeaconId,
  }) async {
    final admitted = await _commands.effectiveAdmission(
      beaconId: parentBeaconId,
      viewerId: actorUserId,
    );
    if (!admitted) {
      throw const BeaconChildCreateForbiddenException();
    }

    final parentBeacon = await _beaconRepository.getBeaconById(
      beaconId: parentBeaconId,
    );
    if (parentBeacon.kind == BeaconKind.post) {
      throw const PostChildRequiresBudException();
    }

    final parent = await _commands.loadParentValidationRow(parentBeaconId);
    if (parent == null || !parent.isPublished) {
      throw const BeaconParentNotCoordinatableException();
    }
    if (!parent.status.allowsCoordination) {
      throw const BeaconParentNotCoordinatableException();
    }
  }

  Future<BeaconPromotionSourceFacts> _loadEligibleSourceFacts({
    required String parentBeaconId,
    required String sourceMessageId,
  }) async {
    final facts = await _commands.loadPromotionSourceFacts(
      parentBeaconId: parentBeaconId,
      sourceMessageId: sourceMessageId,
    );
    if (facts == null || !BeaconPromotionEligibilityPolicy.isEligible(facts)) {
      throw const BeaconPromotionSourceInvalidException();
    }
    return facts;
  }

  Future<BeaconChildCreateResult> _alreadyPromotedResult({
    required String actorUserId,
    required String existingChildBeaconId,
  }) async {
    final readableId = await _readableChildId(
      viewerId: actorUserId,
      childBeaconId: existingChildBeaconId,
    );
    return BeaconChildCreateResult(
      outcome: BeaconChildCommandOutcome.alreadyPromoted,
      beaconId: readableId,
    );
  }

  Future<String?> _readableChildId({
    required String viewerId,
    required String childBeaconId,
  }) async {
    final canRead = await _guard.canReadContent(
      beaconId: childBeaconId,
      viewerId: viewerId,
    );
    return canRead ? childBeaconId : null;
  }

  Future<void> _lockCreateScope({
    required String actorUserId,
    required String clientCommandId,
    required String parentBeaconId,
    String? sourceMessageId,
    String? childBeaconId,
  }) async {
    final beaconIds = <String>{
      parentBeaconId,
      if (childBeaconId != null) childBeaconId,
    }.toList();
    await _commands.lockBeaconRows(beaconIds);
    await _commands.lockPromotionRows(
      childBeaconId: childBeaconId,
      sourceMessageId: sourceMessageId,
    );
    await _commands.lockChildCommandRow(
      actorUserId: actorUserId,
      clientCommandId: clientCommandId,
    );
  }

  Future<void> _lockPublishScope({
    required String childBeaconId,
    required String parentBeaconId,
    String? sourceMessageId,
  }) async {
    await _commands.lockBeaconRows([childBeaconId, parentBeaconId]..sort());
    await _commands.lockPromotionRows(
      childBeaconId: childBeaconId,
      sourceMessageId: sourceMessageId,
    );
  }

  static String _normalizedInputHash({
    required String parentBeaconId,
    required String? sourceMessageId,
    required bool draft,
    required String title,
    required String description,
    required String? context,
    required String? tags,
    required String? needs,
    required String? primaryNeedSlug,
    required double? latitude,
    required double? longitude,
    required String? startAt,
    required String? endAt,
    required String? addressLabel,
    Map<String, Object?> extra = const {},
  }) {
    final payload = <String, Object?>{
      ...extra,
      'addressLabel': addressLabel,
      'context': context,
      'description': description,
      'draft': draft,
      'endAt': endAt,
      'latitude': latitude,
      'longitude': longitude,
      'needs': needs,
      'parentBeaconId': parentBeaconId,
      'primaryNeedSlug': primaryNeedSlug,
      'sourceMessageId': sourceMessageId,
      'startAt': startAt,
      'tags': tags,
      'title': title,
    };
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalJson(payload))))
        .toString();
  }

  /// Sorts map keys at every depth, so the hash is stable.
  static Object? _canonicalJson(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final key in map.keys.toList()..sort())
        key: _canonicalJson(map[key]),
    },
    final List<Object?> list => [for (final item in list) _canonicalJson(item)],
    _ => value,
  };
}
