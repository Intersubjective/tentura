import 'dart:async';
import 'dart:convert' show jsonEncode;

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';

import '../../domain/entity/commitment_event.dart';
import '../../domain/entity/forward_edge.dart';
import '../gql/_g/beacon_involvement_data.data.gql.dart';
import '../gql/_g/beacon_involvement_data.req.gql.dart';
import '../gql/_g/forward_beacon.req.gql.dart';
import '../gql/_g/forward_candidates_fetch.req.gql.dart';
import '../gql/_g/forward_edges_fetch.req.gql.dart';
import '../gql/_g/beacon_commit.req.gql.dart';
import '../gql/_g/beacon_withdraw.req.gql.dart';
import '../gql/_g/commitments_fetch.req.gql.dart';
import '../gql/_g/beacon_updates_fetch.req.gql.dart';

typedef BeaconInvolvementData = ({
  Beacon beacon,
  Set<String> forwardedToIds,
  Set<String> committedIds,
  Set<String> withdrawnIds,
  Set<String> rejectedIds,
  Set<String> watchingIds,
  Set<String> onwardForwarderIds,
  Map<String, String> myForwardedRecipientNotes,
});

@Singleton(env: [Environment.dev, Environment.prod])
class ForwardRepository {
  ForwardRepository(
    this._remoteApiService,
    this._beaconRepository,
    InvalidationService invalidationService,
  ) {
    _commitmentInvalidationSub =
        invalidationService.commitmentInvalidations.listen(
      (id) => _commitmentController.add(CommitmentInvalidated(id)),
    );
    _forwardInvalidationSub =
        invalidationService.forwardInvalidations.listen(
      (id) {
        if (!_forwardCompletedController.isClosed) {
          _forwardCompletedController.add(id);
        }
      },
    );
  }

  final RemoteApiService _remoteApiService;
  final BeaconRepository _beaconRepository;

  late final StreamSubscription<String> _commitmentInvalidationSub;
  late final StreamSubscription<String> _forwardInvalidationSub;

  final _commitmentController =
      StreamController<CommitmentEvent>.broadcast();

  Stream<CommitmentEvent> get commitmentChanges =>
      _commitmentController.stream;

  final _forwardCompletedController = StreamController<String>.broadcast();

  /// Fires after a successful [forwardBeacon] (sender may move to Watching).
  /// Carries the beacon ID that was forwarded.
  Stream<String> get forwardCompleted => _forwardCompletedController.stream;

  @disposeMethod
  Future<void> dispose() async {
    await _commitmentInvalidationSub.cancel();
    await _forwardInvalidationSub.cancel();
    await _commitmentController.close();
    await _forwardCompletedController.close();
  }

  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    String? context,
    String? parentEdgeId,
  }) => _remoteApiService
      .request(
        GForwardBeaconReq(
          (r) => r..vars.beaconId = beaconId
            ..vars.recipientIds.addAll(recipientIds)
            ..vars.note = note
            ..vars.context = context
            ..vars.parentEdgeId = parentEdgeId
            ..vars.perRecipientNotes = perRecipientNotes == null ||
                    perRecipientNotes.isEmpty
                ? null
                : jsonEncode(perRecipientNotes),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final id = r.dataOrThrow(label: _label).beaconForward;
        if (!_forwardCompletedController.isClosed) {
          _forwardCompletedController.add(beaconId);
        }
        return id;
      });

  /// Users with two-way positive MeritRank scores (Hasura `rating` + filter).
  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      _remoteApiService
          .request(
            GForwardCandidatesFetchReq((r) => r..vars.context = context),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).rating)
          .then(
            (rows) => rows
                .where((e) => e.user != null)
                .map((e) => (e.user! as UserModel).toEntity()),
          );

  /// Loads beacon header + forward-screen involvement in parallel.
  ///
  /// **Do not** merge Hasura `beacon_by_pk { rejected_user_ids, ... }` into one
  /// request: when `public.beacon_get_rejected_user_ids` returns zero rows,
  /// Hasura drops the entire `beacon_by_pk` row (see `packages/server/WORKAROUNDS.md`).
  /// Involvement ids come from the V2 `beaconInvolvement` query instead.
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async {
    final results = await Future.wait([
      _beaconRepository.fetchBeaconById(beaconId),
      _remoteApiService
          .request(
            GBeaconInvolvementDataReq((r) => r..vars.id = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r.dataOrThrow(label: _label).beaconInvolvement,
          ),
    ]);

    final beacon = results[0] as Beacon;
    final inv = results[1] as GBeaconInvolvementDataData_beaconInvolvement;

    final myForwardedRecipientNotes = <String, String>{};
    if (inv.myForwardedRecipients != null) {
      for (final r in inv.myForwardedRecipients!) {
        myForwardedRecipientNotes[r.recipientId] = r.note;
      }
    }

    return (
      beacon: beacon,
      forwardedToIds: inv.forwardedToIds?.toSet() ?? {},
      committedIds: inv.committedIds?.toSet() ?? {},
      withdrawnIds: inv.withdrawnIds?.toSet() ?? {},
      rejectedIds: inv.rejectedIds?.toSet() ?? {},
      watchingIds: inv.watchingIds?.toSet() ?? {},
      onwardForwarderIds: inv.onwardForwarderIds?.toSet() ?? {},
      myForwardedRecipientNotes: myForwardedRecipientNotes,
    );
  }

  /// Whether the current user has at least one forward edge from this beacon.
  Future<bool> currentUserHasForwardedBeacon(String beaconId) =>
      _remoteApiService
          .request(
            GBeaconInvolvementDataReq((r) => r..vars.id = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final inv = r.dataOrThrow(label: _label).beaconInvolvement;
            final list = inv.myForwardedRecipients;
            return list != null && list.isNotEmpty;
          });

  Future<List<ForwardEdge>> fetchMyForwardEdges({
    required String beaconId,
    required String myUserId,
  }) => fetchEdges(beaconId: beaconId)
      .then((edges) => edges.where((e) => e.sender.id == myUserId).toList());

  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) =>
      _remoteApiService
          .request(
            GForwardEdgesFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_forward_edge
                .map(
                  (e) => ForwardEdge(
                    id: e.id,
                    beaconId: e.beacon_id,
                    context: e.context ?? '',
                    note: e.note,
                    parentEdgeId: e.parent_edge_id,
                    batchId: e.batch_id,
                    createdAt: e.created_at,
                    sender: (e.sender as UserModel).toEntity(),
                    recipient: (e.recipient as UserModel).toEntity(),
                    recipientRejected: e.recipient_rejected,
                    recipientRejectionMessage: e.recipient_rejection_message,
                  ),
                )
                .toList(),
          );

  Future<
          List<
              ({
                Profile user,
                String message,
                String? helpType,
                String? uncommitReason,
                DateTime createdAt,
                DateTime updatedAt,
                bool isWithdrawn,
              })>>
      fetchCommitments({required String beaconId}) => _remoteApiService
          .request(
            GCommitmentsFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_commitment
                .map(
                  (e) => (
                    user: (e.user as UserModel).toEntity(),
                    message: e.message,
                    helpType: e.help_type,
                    uncommitReason: e.uncommit_reason,
                    createdAt: e.created_at,
                    updatedAt: e.updated_at,
                    isWithdrawn: e.status == 1,
                  ),
                )
                .toList(),
          );

  Future<
      List<
          ({
            String id,
            int number,
            Profile author,
            String content,
            DateTime createdAt,
          })>>
      fetchUpdates({required String beaconId}) => _remoteApiService
          .request(
            GBeaconUpdatesFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_update
                .map(
                  (e) => (
                    id: e.id,
                    number: e.number,
                    author: (e.author as UserModel).toEntity(),
                    content: e.content,
                    createdAt: e.created_at,
                  ),
                )
                .toList(),
          );

  Future<bool> commit({
    required String beaconId,
    String? message,
    String? helpType,
    bool notifyCommitmentListeners = true,
  }) async {
    final ok = await _remoteApiService
        .request(
          GBeaconCommitReq(
            (r) => r
              ..vars.beaconId = beaconId
              ..vars.message = message
              ..vars.helpType = helpType,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconCommit);
    if (ok && notifyCommitmentListeners) {
      _commitmentController.add(CommitmentCreated(beaconId));
    }
    return ok;
  }

  Future<bool> withdraw({
    required String beaconId,
    required String uncommitReason,
    String? message,
  }) async {
    final ok = await _remoteApiService
        .request(
          GBeaconWithdrawReq(
            (r) => r
              ..vars.beaconId = beaconId
              ..vars.message = message
              ..vars.uncommitReason = uncommitReason,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconWithdraw);
    if (ok) {
      _commitmentController.add(CommitmentWithdrawn(beaconId));
    }
    return ok;
  }

  static const _label = 'Forward';
}
