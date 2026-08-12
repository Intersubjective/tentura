import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/projection_tier.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';

import '../gql/_g/capability_private_label_set.req.gql.dart';
import '../gql/_g/capability_set_viewer_visible.req.gql.dart';
import '../gql/_g/forward_context_fetch.data.gql.dart';
import '../gql/_g/forward_context_fetch.req.gql.dart';
import '../gql/_g/invite_seed_prompt_answer.req.gql.dart';
import '../gql/_g/invite_seed_prompt_fetch.data.gql.dart';
import '../gql/_g/invite_seed_prompt_fetch.req.gql.dart';
import '../gql/_g/invite_seed_prompt_skip.req.gql.dart';
import '../gql/_g/my_private_labels_for_user.req.gql.dart';
import '../gql/_g/my_routing_tags_fetch.req.gql.dart';
import '../gql/_g/person_capability_cues_fetch.req.gql.dart';
import '../gql/_g/person_friend_context_batch_fetch.req.gql.dart';
import '../gql/_g/person_top_capabilities_batch_fetch.req.gql.dart';
import '../gql/_g/revoke_acknowledgement.req.gql.dart';
import '../gql/_g/seed_routing_attestation.req.gql.dart';
import '../gql/_g/set_routing_mute.req.gql.dart';
import '../gql/_g/subjective_tags_fetch.data.gql.dart';
import '../gql/_g/subjective_tags_fetch.req.gql.dart';
import '../gql/_g/tag_explanation_fetch.req.gql.dart';

@LazySingleton(
  as: CapabilityRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class CapabilityRepository implements CapabilityRepositoryPort {
  CapabilityRepository(
    RemoteRequestClient remoteApiService,
    RealtimeSyncPort realtimeSync,
  ) : _remoteApiService = remoteApiService {
    _capabilityInvalidationSub = realtimeSync.entityChanges
        .where((change) => change.kind == RealtimeEntityKind.capability)
        .listen((_) => _changesController.add(null));
  }

  final RemoteRequestClient _remoteApiService;

  late final StreamSubscription<RealtimeEntityChange>
  _capabilityInvalidationSub;

  final _changesController = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changesController.stream;

  @override
  @disposeMethod
  Future<void> dispose() async {
    await _capabilityInvalidationSub.cancel();
    await _changesController.close();
  }

  @override
  Future<List<String>> fetchMyPrivateLabelsForUser(String subjectId) =>
      _remoteApiService
          .request(
            GMyPrivateLabelsForUserReq(
              (r) => r..vars.subjectUserId = subjectId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) =>
                r.dataOrThrow(label: _label).myPrivateLabelsForUser?.toList() ??
                const [],
          );

  @override
  Future<void> setPrivateLabels({
    required String subjectId,
    required List<String> slugs,
  }) => _remoteApiService
      .request(
        GCapabilityPrivateLabelSetReq(
          (r) => r
            ..vars.subjectUserId = subjectId
            ..vars.slugs.addAll(slugs),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) => _remoteApiService
      .request(
        GPersonCapabilityCuesReq(
          (r) => r..vars.subjectUserId = subjectId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).personCapabilityCues)
      .then((p) {
        return PersonCapabilityCues(
          privateLabels: p.privateLabels?.toList() ?? [],
          forwardReasonsByMe:
              p.forwardReasonsByMe
                  ?.map(
                    (e) => TagCount(
                      slug: e.slug,
                      count: e.count,
                      lastSeenAt: e.lastSeenAt,
                    ),
                  )
                  .toList() ??
              [],
          commitRoles:
              p.commitRoles
                  ?.map(
                    (e) => TagBeaconRef(
                      slug: e.slug,
                      beaconId: e.beaconId,
                      beaconTitle: e.beaconTitle,
                      createdAt: e.createdAt,
                    ),
                  )
                  .toList() ??
              [],
          closeAckByMe:
              p.closeAckByMe
                  ?.map(
                    (e) => TagBeaconRef(
                      slug: e.slug,
                      beaconId: e.beaconId,
                      beaconTitle: e.beaconTitle,
                      createdAt: e.createdAt,
                    ),
                  )
                  .toList() ??
              [],
          closeAckAboutMe:
              p.closeAckAboutMe
                  ?.map(
                    (e) => TagBeaconRef(
                      slug: e.slug,
                      beaconId: e.beaconId,
                      beaconTitle: e.beaconTitle,
                      createdAt: e.createdAt,
                    ),
                  )
                  .toList() ??
              [],
          viewerVisible:
              p.viewerVisible
                  ?.map(
                    (e) => CapabilityWithSource(
                      slug: e.slug,
                      hasManualLabel: e.hasManualLabel,
                    ),
                  )
                  .toList() ??
              [],
        );
      });

  @override
  Future<void> setViewerVisible({
    required String subjectId,
    required List<String> slugs,
  }) => _remoteApiService
      .request(
        GCapabilitySetViewerVisibleReq(
          (r) => r
            ..vars.subjectUserId = subjectId
            ..vars.slugs.addAll(slugs),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  @override
  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required List<String> subjectIds,
    int limit = 2,
    List<String> prioritizeSlugs = const [],
  }) => _remoteApiService
      .request(
        GPersonTopCapabilitiesBatchReq(
          (r) => r
            ..vars.subjectUserIds.addAll(subjectIds)
            ..vars.limit = limit
            ..vars.prioritizeSlugs.replace(
              BuiltList<String>.from(prioritizeSlugs),
            ),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final entries = r
            .dataOrThrow(label: _label)
            .personTopCapabilitiesBatch
            ?.toList() ??
            const [];
        return {
          for (final e in entries)
            e.subjectId: e.slugs?.toList() ?? const [],
        };
      });

  @override
  Future<Map<String, FriendContext>> fetchFriendContextsBatch({
    required List<String> subjectIds,
  }) {
    if (subjectIds.isEmpty) return Future.value({});

    return _remoteApiService
        .request(
          GPersonFriendContextBatchReq(
            (r) => r..vars.subjectUserIds.addAll(subjectIds),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).personFriendContextBatch)
        .then(
          (rows) => {
            for (final row in [...?rows])
              row.subjectId: FriendContext(
                activeForwardsToCount: row.activeForwardsToCount,
                coInvolvedBeaconsCount: row.coInvolvedBeaconsCount,
              ),
          },
        );
  }

  @override
  Future<List<TagProjection>> fetchSubjectiveTags(String targetId) =>
      _remoteApiService
          .request(
            GSubjectiveTagsReq((r) => r..vars.targetId = targetId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).subjectiveTags)
          .then(
            (rows) =>
                rows?.map(_tagProjectionFromGql).toList() ?? const [],
          );

  @override
  Future<List<ForwardBandRow>> fetchForwardContext({
    required String beaconId,
    String? context,
  }) => _remoteApiService
      .request(
        GForwardContextReq(
          (r) => r
            ..vars.beaconId = beaconId
            ..vars.context = context,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).forwardContext)
      .then(
        (rows) => rows?.map(_forwardBandRowFromGql).toList() ?? const [],
      );

  @override
  Future<List<String>> fetchMyRoutingTags() => _remoteApiService
      .request(GMyRoutingTagsReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).myRoutingTags.toList());

  @override
  Future<String?> fetchTagExplanation({
    required String targetId,
    required String slug,
  }) => _remoteApiService
      .request(
        GTagExplanationReq(
          (r) => r
            ..vars.targetId = targetId
            ..vars.slug = slug,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).tagExplanation);

  @override
  Future<void> seedRoutingAttestation({
    required String subjectId,
    required List<String> slugs,
  }) => _remoteApiService
      .request(
        GSeedRoutingAttestationReq(
          (r) => r
            ..vars.subjectId = subjectId
            ..vars.slugs.addAll(slugs),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  @override
  Future<void> revokeAcknowledgement({
    required String beaconId,
    required String subjectId,
    required String slug,
  }) => _remoteApiService
      .request(
        GRevokeAcknowledgementReq(
          (r) => r
            ..vars.beaconId = beaconId
            ..vars.subjectId = subjectId
            ..vars.slug = slug,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  @override
  Future<void> setRoutingMute({
    required String slug,
    required bool muted,
  }) => _remoteApiService
      .request(
        GSetRoutingMuteReq(
          (r) => r
            ..vars.slug = slug
            ..vars.muted = muted,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  @override
  Future<InviteSeedPromptState> fetchInviteSeedPromptState(
    String subjectId,
  ) => _remoteApiService
      .request(
        GInviteSeedPromptStateReq((r) => r..vars.subjectId = subjectId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).inviteSeedPromptState)
      .then(_inviteSeedPromptStateFromGql);

  @override
  Future<void> inviteSeedPromptAnswer({
    required String subjectId,
    required List<String> slugs,
  }) => _remoteApiService
      .request(
        GInviteSeedPromptAnswerReq(
          (r) => r
            ..vars.subjectId = subjectId
            ..vars.slugs.addAll(slugs),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  @override
  Future<void> inviteSeedPromptSkip(String subjectId) => _remoteApiService
      .request(
        GInviteSeedPromptSkipReq((r) => r..vars.subjectId = subjectId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  TagProjection _tagProjectionFromGql(GSubjectiveTagsData_subjectiveTags row) =>
      TagProjection(
        subjectUserId: row.subjectUserId,
        tagSlug: row.tagSlug,
        tier: ProjectionTier.fromWire(row.tier),
      );

  TagProjection _forwardBandLabelFromGql(
    GForwardContextData_forwardContext_labels row,
  ) => TagProjection(
    subjectUserId: row.subjectUserId,
    tagSlug: row.tagSlug,
    tier: ProjectionTier.fromWire(row.tier),
  );

  ForwardBandRow _forwardBandRowFromGql(
    GForwardContextData_forwardContext row,
  ) => ForwardBandRow(
    userId: row.userId,
    rowTier: row.rowTier == null
        ? null
        : ProjectionTier.fromWire(row.rowTier!),
    labels: row.labels.map(_forwardBandLabelFromGql).toList(),
    rank: row.rank,
    isExploration: row.isExploration,
  );

  InviteSeedPromptState _inviteSeedPromptStateFromGql(
    GInviteSeedPromptStateData_inviteSeedPromptState row,
  ) => InviteSeedPromptState(
    inviterUserId: row.inviterUserId,
    inviteeUserId: row.inviteeUserId,
    state: PromptStateValue.fromWire(row.state),
  );

  static const _label = 'Capability';
}
