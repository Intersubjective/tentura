import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

/// Closes a Post (status 6): when a Request buds from it with `closePost`
/// (Arch §2.3, plan C5), when it expires, or when its author closes it.
///
/// A closed Post stays readable for its members and stays in their
/// conversation list; every ordinary write is refused. This is the one place
/// that sets it.
///
/// It runs inside the caller's mutating unit, after the caller took the Post
/// lock (Arch §4.1); it re-checks that the Post is still an open Post.
///
/// Only the Post's author may close it (#666): a member who buds a Request
/// cannot end the author's conversation for everyone. A close asked for by
/// anyone else fails the whole bud, so nothing is half-applied.
@Singleton(order: 2)
final class PostCloseOperation {
  const PostCloseOperation(this._beacons);

  final BeaconRepositoryPort _beacons;

  /// Moves [postId] from open to closed and inserts the kind-5 notice that
  /// points at the budded Request [childBeaconId] with a [title] snapshot.
  ///
  /// The status transition is recorded **without**
  /// `BeaconLifecycleEffectsCase.recordEligibleSourceTransition`: that would
  /// deliver a «parent closed» hierarchy notice to the child, which is wrong —
  /// the child is where the conversation continues.
  ///
  /// A Post that is already closed stays as it is: no transition and no
  /// second notice, so a member may bud from an archived Post.
  Future<void> closeForBud({
    required String postId,
    required String childBeaconId,
    required String title,
    required String actorId,
  }) async {
    final post = await _beacons.getBeaconById(beaconId: postId);
    if (post.kind == BeaconKind.post && post.status == BeaconStatus.closed) {
      return;
    }
    if (post.kind != BeaconKind.post || post.status != BeaconStatus.open) {
      throw const PostNotOpenException();
    }
    if (post.author.id != actorId) {
      throw const BeaconChildCreateForbiddenException(
        description: 'Only the author of the Post can close it',
      );
    }
    await _close(
      post,
      lifecycleReason: BeaconLifecycleChangeReason.directClose,
      noticeReason: PostClosedNoticeReason.budded,
      actorId: actorId,
      childBeaconId: childBeaconId,
      title: title,
    );
  }

  /// Closes [postId] because its `expires_at` passed; the system is the actor.
  Future<void> expire({required String postId}) async {
    await _close(
      await _requireOpenPost(postId),
      lifecycleReason: BeaconLifecycleChangeReason.postExpired,
      noticeReason: PostClosedNoticeReason.expired,
      actorId: null,
      endNow: true,
    );
  }

  /// Closes [postId] on [actorId]'s request before it expired. The caller
  /// checks that [actorId] is the Post's author.
  Future<void> closeByAuthor({
    required String postId,
    required String actorId,
  }) async {
    await _close(
      await _requireOpenPost(postId),
      lifecycleReason: BeaconLifecycleChangeReason.postClosedByAuthor,
      noticeReason: PostClosedNoticeReason.closedByAuthor,
      actorId: actorId,
      endNow: true,
    );
  }

  Future<BeaconEntity> _requireOpenPost(String postId) async {
    final post = await _beacons.getBeaconById(beaconId: postId);
    if (post.kind != BeaconKind.post || post.status != BeaconStatus.open) {
      throw const PostNotOpenException();
    }
    return post;
  }

  Future<void> _close(
    BeaconEntity post, {
    required String lifecycleReason,
    required String noticeReason,
    required String? actorId,
    String? childBeaconId,
    String? title,
    bool endNow = false,
  }) async {
    final verdict = validateBeaconStatusTransition(
      from: post.status,
      to: BeaconStatus.closed,
    ).verdict;
    if (verdict != BeaconStatusTransitionVerdict.allowed) {
      throw const PostNotOpenException();
    }
    await _beacons.recordBeaconStatusTransition(
      beaconId: post.id,
      fromStatus: post.status,
      toStatus: BeaconStatus.closed,
      reason: lifecycleReason,
      actorId: actorId,
    );
    if (endNow) await _beacons.endPostNow(post.id);
    await _beacons.postClosedMessage(
      postId: post.id,
      reason: noticeReason,
      childBeaconId: childBeaconId,
      title: title,
    );
  }
}
