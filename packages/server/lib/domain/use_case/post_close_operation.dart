import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

/// Closes a Post when a Request buds from it with `closePost` (Arch §2.3,
/// plan C5).
///
/// A closed Post (status 6) stays readable for its members and stays in their
/// conversation list; every ordinary write is refused. It is reachable only
/// through budding, so this is the one place that sets it.
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
  Future<void> closeForBud({
    required String postId,
    required String childBeaconId,
    required String title,
    required String actorId,
  }) async {
    final post = await _beacons.getBeaconById(beaconId: postId);
    if (post.kind != BeaconKind.post || post.status != BeaconStatus.open) {
      throw const PostNotOpenException();
    }
    if (post.author.id != actorId) {
      throw const BeaconChildCreateForbiddenException(
        description: 'Only the author of the Post can close it',
      );
    }
    final verdict = validateBeaconStatusTransition(
      from: post.status,
      to: BeaconStatus.closed,
    ).verdict;
    if (verdict != BeaconStatusTransitionVerdict.allowed) {
      throw const PostNotOpenException();
    }
    await _beacons.recordBeaconStatusTransition(
      beaconId: postId,
      fromStatus: post.status,
      toStatus: BeaconStatus.closed,
      reason: BeaconLifecycleChangeReason.directClose,
      actorId: actorId,
    );
    await _beacons.postClosedMessage(
      postId: postId,
      childBeaconId: childBeaconId,
      title: title,
    );
  }
}
