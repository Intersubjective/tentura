import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';

/// Budding a Request from a Post (plan C3, Arch §4.2).
abstract interface class PostBudPort {
  /// Members of the Post the caller may invite, writers first.
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String postId,
  });

  /// Creates a child Request under Post [postId]. [sourceMessageId] is
  /// optional own-message prefill only; budding is unlimited.
  /// Idempotent per [clientCommandId].
  Future<PostBudResult> budFromPost({
    required String postId,
    required String clientCommandId,
    required String title,
    String? sourceMessageId,
    String? description,
    String? context,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    bool isDiscoverable = false,
    List<PostBudInvitee> invitees = const [],
    bool closePost = false,
  });
}
