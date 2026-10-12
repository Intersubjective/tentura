import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/port/post_bud_port.dart';

import '../gql/_g/post_bud_from_post.req.gql.dart';
import '../gql/_g/post_bud_invite_candidates.req.gql.dart';

@Singleton(as: PostBudPort, env: [Environment.dev, Environment.prod])
class PostBudRepository implements PostBudPort {
  const PostBudRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'PostBud';

  @override
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String postId,
  }) async {
    final rows = await _remoteApiService
        .request(GPostBudInviteCandidatesReq((b) => b.vars.postId = postId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).postBudInviteCandidates);
    return [
      for (final row in rows)
        PostBudInviteCandidate(
          userId: row.userId,
          warm: row.warm,
          outcome: PostBudInviteOutcome.fromWire(row.outcome.name),
          pretick: row.pretick,
          hasWritten: row.hasWritten,
          viaUserId: row.viaUserId,
        ),
    ];
  }

  @override
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
  }) async {
    final source = sourceMessageId?.trim();
    final data = await _remoteApiService
        .request(
          GPostBudFromPostReq(
            (b) => b.vars
              ..postId = postId
              ..sourceMessageId =
                  (source == null || source.isEmpty) ? null : source
              ..clientCommandId = clientCommandId
              ..title = title
              ..description = description
              ..context = context
              ..coordinates = coordinates == null
                  ? null
                  : (Gv2_CoordinatesBuilder()
                      ..lat = coordinates.lat
                      ..long = coordinates.long)
              ..startAt = startAt?.toUtc().toIso8601String()
              ..endAt = endAt?.toUtc().toIso8601String()
              ..tags = tags
              ..needs = needs
              ..primaryNeedSlug = primaryNeedSlug
              ..addressLabel = addressLabel
              ..isDiscoverable = isDiscoverable
              ..invitees = ListBuilder([
                for (final invitee in invitees)
                  Gv2_PostBudInviteeInput(
                    (i) => i
                      ..userId = invitee.userId
                      ..note = invitee.note,
                  ),
              ])
              ..closePost = closePost,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconBudFromPost);
    return PostBudResult(
      outcome: PostBudOutcome.fromWire(data.outcome),
      childBeaconId: data.childBeaconId,
      invitees: [
        for (final invitee in data.invitees)
          PostBudInviteeResult(
            userId: invitee.userId,
            outcome: PostBudInviteOutcome.fromWire(invitee.outcome.name),
          ),
      ],
    );
  }
}
