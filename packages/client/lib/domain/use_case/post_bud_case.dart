import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/port/post_bud_port.dart';

import 'use_case_base.dart';

/// Budding a Request from a Post (plan C3/D1). Entry points that start a bud
/// check `kPostBuddingEnabled`; this case does not.
@singleton
final class PostBudCase extends UseCaseBase {
  PostBudCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final PostBudPort _port;

  static const _uuid = Uuid();

  /// One id per bud screen session, so repeated submits replay (plan D1).
  String newClientCommandId() => _uuid.v4();

  Future<List<PostBudInviteCandidate>> inviteCandidates(String postId) =>
      _port.inviteCandidates(postId: postId);

  Future<PostBudResult> budFromPost({
    required String postId,
    required String sourceMessageId,
    required String clientCommandId,
    required String title,
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
  }) => _port.budFromPost(
    postId: postId,
    sourceMessageId: sourceMessageId,
    clientCommandId: clientCommandId,
    title: title,
    description: description,
    context: context,
    coordinates: coordinates,
    startAt: startAt,
    endAt: endAt,
    tags: tags,
    needs: needs,
    primaryNeedSlug: primaryNeedSlug,
    addressLabel: addressLabel,
    isDiscoverable: isDiscoverable,
    invitees: invitees,
    closePost: closePost,
  );
}
