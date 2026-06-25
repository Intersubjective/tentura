import 'dart:async';
import 'dart:convert' show jsonEncode;

import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';

import '../../domain/entity/help_offer_event.dart';
import '../../domain/entity/forward_edge.dart';
import '../../domain/entity/forward_graph.dart';
import '../gql/_g/beacon_involvement_data.data.gql.dart';
import '../gql/_g/beacon_involvement_data.req.gql.dart';
import '../gql/_g/beacon_forward_graph.req.gql.dart';
import '../gql/_g/beacon_help_offerer_forward_path.req.gql.dart';
import '../gql/_g/forward_beacon.req.gql.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart'
    show GForwardRecipientReasonInput;
import '../gql/_g/forward_cancel.req.gql.dart';
import '../gql/_g/forward_update.req.gql.dart';
import '../gql/_g/forward_candidates_fetch.req.gql.dart';
import '../gql/_g/forward_edges_fetch.req.gql.dart';
import '../gql/_g/forward_reasons_fetch.req.gql.dart';
import '../gql/_g/beacon_offer_help.req.gql.dart';
import '../gql/_g/beacon_withdraw.req.gql.dart';
import '../gql/_g/help_offers_fetch.req.gql.dart';
import '../../domain/entity/lineage_suggestion_group.dart';
import '../gql/_g/beacon_lineage_suggestions.data.gql.dart';
import '../gql/_g/beacon_lineage_suggestions.req.gql.dart';

typedef BeaconInvolvementData = ({
  Beacon beacon,
  Set<String> forwardedToIds,
  Set<String> helpOfferedIds,
  Set<String> withdrawnIds,
  Set<String> rejectedIds,
  Set<String> watchingIds,
  Set<String> onwardForwarderIds,
  Map<String, String> myForwardedRecipientNotes,
  Map<String, String> myForwardedRecipientEdgeIds,
  Map<String, DateTime?> myForwardedRecipientReadAts,
});

@Singleton(env: [Environment.dev, Environment.prod])
class ForwardRepository {
  ForwardRepository(
    this._remoteApiService,
    this._beaconRepository,
    InvalidationService invalidationService,
  ) {
    _helpOfferInvalidationSub =
        invalidationService.helpOfferInvalidations.listen(
      (id) => _helpOfferController.add(HelpOfferInvalidated(id)),
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

  late final StreamSubscription<String> _helpOfferInvalidationSub;
  late final StreamSubscription<String> _forwardInvalidationSub;

  final _helpOfferController =
      StreamController<HelpOfferEvent>.broadcast();

  Stream<HelpOfferEvent> get helpOfferChanges =>
      _helpOfferController.stream;

  final _forwardCompletedController = StreamController<String>.broadcast();

  /// Fires after a successful [forwardBeacon] (sender may move to Watching).
  /// Carries the beacon ID that was forwarded.
  Stream<String> get forwardCompleted => _forwardCompletedController.stream;

  @disposeMethod
  Future<void> dispose() async {
    await _helpOfferInvalidationSub.cancel();
    await _forwardInvalidationSub.cancel();
    await _helpOfferController.close();
    await _forwardCompletedController.close();
  }

  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
  }) => _remoteApiService
      .request(
        GForwardBeaconReq(
          (r) {
            r
              ..vars.beaconId = beaconId
              ..vars.recipientIds.addAll(recipientIds)
              ..vars.note = note
              ..vars.context = context
              ..vars.parentEdgeId = parentEdgeId
              ..vars.perRecipientNotes = perRecipientNotes == null ||
                      perRecipientNotes.isEmpty
                  ? null
                  : jsonEncode(perRecipientNotes);
            if (recipientReasons != null && recipientReasons.isNotEmpty) {
              r.vars.recipientReasons.addAll(
                recipientReasons.entries
                    .where((e) => e.value.isNotEmpty)
                    .map(
                      (e) => GForwardRecipientReasonInput.create(
                        recipientId: e.key,
                        slugs: BuiltList<String>.from(e.value),
                      ),
                    ),
              );
            }
          },
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

    return mapBeaconInvolvement(beacon: beacon, inv: inv);
  }

  /// Maps V2 `beaconInvolvement` GraphQL payload into [BeaconInvolvementData].
  @visibleForTesting
  static BeaconInvolvementData mapBeaconInvolvement({
    required Beacon beacon,
    required GBeaconInvolvementDataData_beaconInvolvement inv,
  }) {
    final myForwardedRecipientNotes = <String, String>{};
    final myForwardedRecipientEdgeIds = <String, String>{};
    final myForwardedRecipientReadAts = <String, DateTime?>{};
    if (inv.myForwardedRecipients != null) {
      for (final r in inv.myForwardedRecipients!) {
        myForwardedRecipientNotes[r.recipientId] = r.note;
        myForwardedRecipientEdgeIds[r.recipientId] = r.edgeId;
        myForwardedRecipientReadAts[r.recipientId] =
            r.readAt != null ? DateTime.parse(r.readAt!) : null;
      }
    }

    return (
      beacon: beacon,
      forwardedToIds: inv.forwardedToIds?.toSet() ?? {},
      helpOfferedIds: inv.helpOfferedIds?.toSet() ?? {},
      withdrawnIds: inv.withdrawnIds?.toSet() ?? {},
      rejectedIds: inv.rejectedIds?.toSet() ?? {},
      watchingIds: inv.watchingIds?.toSet() ?? {},
      onwardForwarderIds: inv.onwardForwarderIds?.toSet() ?? {},
      myForwardedRecipientNotes: myForwardedRecipientNotes,
      myForwardedRecipientEdgeIds: myForwardedRecipientEdgeIds,
      myForwardedRecipientReadAts: myForwardedRecipientReadAts,
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

  /// Returns capability tags keyed by `'${senderId}__${recipientId}'` for all
  /// forward-reason events on [beaconId] involving the current viewer.
  Future<Map<String, List<String>>> fetchReasonsByBeacon({
    required String beaconId,
  }) =>
      _remoteApiService
          .request(
            GForwardReasonsFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => {
              for (final row
                  in r.dataOrThrow(label: _label).forwardReasonsByBeacon)
                '${row.senderId}__${row.recipientId}': row.slugs.toList(),
            },
          );

  /// Fetches the forwards-graph payload for a beacon (V2 `beaconForwardGraph`).
  ///
  /// Returns the edges visible to the viewer plus the parent_edge_id ancestor
  /// closure and the chains that delivered the beacon to each active
  /// help offerer. The viewer must be the author OR have at least one forward
  /// edge for the beacon OR have an active help offer.
  Future<ForwardGraph> fetchForwardGraph({required String beaconId}) =>
      _remoteApiService
          .request(
            GBeaconForwardGraphReq((r) => r..vars.id = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).beaconForwardGraph)
          .then(
            (g) => ForwardGraph(
              beaconId: g.beaconId,
              authorId: g.authorId,
              viewerId: g.viewerId,
              helpOffererIds: g.helpOffererIds.toSet(),
              edges: g.edges
                  .map(
                    (e) => ForwardGraphEdge(
                      id: e.id,
                      beaconId: e.beaconId,
                      senderId: e.senderId,
                      recipientId: e.recipientId,
                      parentEdgeId: e.parentEdgeId,
                      batchId: e.batchId,
                    ),
                  )
                  .toList(growable: false),
            ),
          );

  /// Fetches the per-help-offerer forward-path payload (V2 `beaconHelpOffererForwardPath`).
  ///
  /// Returns the union of (a) the help offerer's ancestor closure and (b) the
  /// viewer's own forward edges and their ancestor closure, so the screen
  /// can render author + viewer + help offerer simultaneously when the viewer
  /// is an "involved other". `viewerId` is always set on the returned
  /// [ForwardGraph]; the cubit derives the viewer role from it.
  Future<ForwardGraph> fetchHelpOffererForwardPath({
    required String beaconId,
    required String helpOffererId,
  }) => _remoteApiService
      .request(
        GBeaconHelpOffererForwardPathReq(
          (r) => r
            ..vars.id = beaconId
            ..vars.helpOffererId = helpOffererId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beaconHelpOffererForwardPath)
      .then(
        (g) {
          return ForwardGraph(
            beaconId: g.beaconId,
            authorId: g.authorId,
            viewerId: g.viewerId,
            helpOffererIds: g.helpOffererIds.toSet(),
            edges: g.edges
                .map(
                  (e) => ForwardGraphEdge(
                    id: e.id,
                    beaconId: e.beaconId,
                    senderId: e.senderId,
                    recipientId: e.recipientId,
                    parentEdgeId: e.parentEdgeId,
                    batchId: e.batchId,
                  ),
                )
                .toList(growable: false),
          );
        },
      );

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
                    recipientReadAt: e.recipient_read_at,
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
                String? withdrawReason,
                DateTime createdAt,
                DateTime updatedAt,
                bool isWithdrawn,
              })>>
      fetchHelpOffers({required String beaconId}) => _remoteApiService
          .request(
            GHelpOffersFetchReq((r) => r..vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_help_offer
                .map(
                  (e) => (
                    user: (e.user as UserModel).toEntity(),
                    message: e.message,
                    helpType: e.help_type,
                    withdrawReason: e.withdraw_reason,
                    createdAt: e.created_at,
                    updatedAt: e.updated_at,
                    isWithdrawn: e.status == 1,
                  ),
                )
                .toList(),
          );

  Future<bool> cancelForward(String edgeId) => _remoteApiService
      .request(GForwardCancelReq((r) => r..vars.id = edgeId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beaconForwardCancel);

  Future<bool> updateForward({
    required String edgeId,
    String? note,
    List<String>? reasonSlugs,
  }) => _remoteApiService
      .request(
        GForwardUpdateReq(
          (r) => r
            ..vars.id = edgeId
            ..vars.note = note
            ..vars.reasons = reasonSlugs != null
                ? BuiltList<String>.from(reasonSlugs).toBuilder()
                : null,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beaconForwardUpdate);

  Future<bool> offerHelp({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    bool notifyHelpOfferListeners = true,
  }) async {
    final ok = await _remoteApiService
        .request(
          GBeaconOfferHelpReq(
            (r) => r
              ..vars.beaconId = beaconId
              ..vars.message = message
              ..vars.helpTypes = helpTypes != null
                  ? BuiltList<String>(helpTypes).toBuilder()
                  : null,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconOfferHelp);
    if (ok && notifyHelpOfferListeners) {
      _helpOfferController.add(HelpOfferCreated(beaconId));
    }
    return ok;
  }

  Future<bool> withdraw({
    required String beaconId,
    required String withdrawReason,
    String? message,
  }) async {
    final ok = await _remoteApiService
        .request(
          GBeaconWithdrawReq(
            (r) => r
              ..vars.beaconId = beaconId
              ..vars.message = message
              ..vars.withdrawReason = withdrawReason,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconWithdraw);
    if (ok) {
      _helpOfferController.add(HelpOfferWithdrawn(beaconId));
    }
    return ok;
  }

  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) =>
      _remoteApiService
          .request(
            GBeaconLineageForwardSuggestionsReq((r) => r..vars.id = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).beaconLineageForwardSuggestions)
          .then(_mapLineageSuggestions);

  LineageForwardSuggestions _mapLineageSuggestions(
    GBeaconLineageForwardSuggestionsData_beaconLineageForwardSuggestions payload,
  ) {
    final suggestions = <LineageForwardSuggestion>[];
    for (final row in payload.suggestions) {
      final group = LineageSuggestionGroupWire.fromWire(row.group);
      if (group == null) continue;
      suggestions.add(
        LineageForwardSuggestion(
          userId: row.userId,
          group: group,
          reasonCode: row.reasonCode,
          reasonArg: row.reasonArg,
          autoSelect: row.autoSelect,
        ),
      );
    }
    return LineageForwardSuggestions(
      sourceBeaconId: payload.sourceBeaconId,
      rootBeaconId: payload.rootBeaconId,
      suggestedNote: payload.suggestedNote,
      suggestions: suggestions,
    );
  }

  static const _label = 'Forward';
}
