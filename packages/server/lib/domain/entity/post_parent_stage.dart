import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

/// Post-parent stage of the child pipeline (budding, Arch §4.2 step 2).
///
/// `createChildUnderPost` calls it inside the bud transaction, after the
/// child is published and before the `childCreated` notice is inserted, with
/// every lock of Arch §4.1 up to the child row already held. The stage writes
/// the observers snapshot and the invites, and returns what the pipeline
/// needs to finish: the invite count for the notice and the result to store.
typedef PostParentStage =
    Future<PostParentStageResult> Function(PostParentStageContext context);

/// What the pipeline hands to a [PostParentStage].
final class PostParentStageContext {
  const PostParentStageContext({
    required this.transaction,
    required this.actorUserId,
    required this.postId,
    required this.sourceMessageId,
    required this.child,
  });

  /// Record attention intents (for example `authorInviteReceived`) here.
  final AttentionTransaction transaction;

  /// The budder.
  final String actorUserId;
  final String postId;
  final String sourceMessageId;

  /// The published child Request.
  final BeaconEntity child;
}

/// What a [PostParentStage] returns.
final class PostParentStageResult {
  const PostParentStageResult({
    this.invitedCount = 0,
    this.invitees = const [],
    this.afterNotice,
  });

  /// `invitedCount` of the `childCreated` notice payload.
  final int invitedCount;

  /// Per-invitee outcomes (`{userId, outcome}` JSON objects), stored verbatim
  /// as `bud_result.invitees` and returned on replay.
  final List<Map<String, Object?>> invitees;

  /// Runs after the `childCreated` notice, still inside the transaction and
  /// before the result is stored (for example closing the Post, so its
  /// closed notice follows the bud notice).
  final Future<void> Function()? afterNotice;
}

/// `bud_result` JSON keys and outcome values (Arch §2.6).
abstract final class PostBudResultJson {
  PostBudResultJson._();

  static const outcome = 'outcome';
  static const childBeaconId = 'childBeaconId';
  static const invitees = 'invitees';

  static const outcomeCreated = 'created';
  static const outcomeAlreadyPromoted = 'alreadyPromoted';

  static Map<String, Object?> build({
    required String outcome,
    required String? childBeaconId,
    List<Map<String, Object?>> invitees = const [],
  }) => {
    PostBudResultJson.outcome: outcome,
    PostBudResultJson.childBeaconId: childBeaconId,
    PostBudResultJson.invitees: invitees,
  };
}
