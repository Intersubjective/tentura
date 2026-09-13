import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/entity/inbox_provenance.dart';
import '../../domain/enum.dart';
import '../gql/_g/activity_offers.req.gql.dart';
import '../gql/_g/inbox_fetch.req.gql.dart';
import '../gql/_g/inbox_item_fields.data.gql.dart';
import '../gql/_g/inbox_item_status_for_beacon.req.gql.dart';
import '../gql/_g/inbox_set_status.req.gql.dart';
import '../gql/_g/inbox_tombstone_dismiss.req.gql.dart';

import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class InboxRepository {
  InboxRepository(this._remoteApiService, this._roomHints);

  final RemoteApiService _remoteApiService;

  final BeaconRoomHintsRepository _roomHints;

  final _localMutationController = StreamController<void>.broadcast();

  /// Sentinel cursor for the first paged open-forwards fetch.
  static final activityOffersFirstPageAt = DateTime.utc(9999, 12, 31);

  static const activityOffersPageSize = 20;

  /// Fires after a successful local [setStatus] (e.g. from beacon detail).
  Stream<void> get localMutations => _localMutationController.stream;

  @disposeMethod
  Future<void> dispose() async {
    await _localMutationController.close();
  }

  Future<List<InboxItem>> fetch({required String userId}) async {
    final rows = await _remoteApiService
        .request(GInboxFetchReq((r) => r..vars.userId = userId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).inbox_item);
    return _mapInboxItemRows(rows, userId);
  }

  Future<({List<InboxItem> page, int totalCount})> fetchActivityOffersFirstPage({
    required String userId,
    int limit = activityOffersPageSize,
  }) async {
    final data = await _fetchActivityOffersPageRaw(
      userId: userId,
      at: activityOffersFirstPageAt,
      id: '',
      limit: limit,
      includeAggregate: true,
    );
    final page = await _mapInboxItemRows(data.rows, userId);
    return (page: page, totalCount: data.totalCount ?? 0);
  }

  Future<List<InboxItem>> fetchActivityOffersPage({
    required String userId,
    required DateTime cursorAt,
    required String cursorBeaconId,
    int limit = activityOffersPageSize,
  }) async {
    final data = await _fetchActivityOffersPageRaw(
      userId: userId,
      at: cursorAt,
      id: cursorBeaconId,
      limit: limit,
      includeAggregate: false,
    );
    return _mapInboxItemRows(data.rows, userId);
  }

  Future<int> fetchOpenForwardsCount() async {
    final aggregate = await _remoteApiService
        .request(GActivityOffersCountReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).inbox_item_aggregate);
    return aggregate.aggregate?.count ?? 0;
  }

  Future<InboxItem?> fetchOpenForwardForBeacon({
    required String userId,
    required String beaconId,
  }) async {
    final rows = await _remoteApiService
        .request(
          GActivityOfferForBeaconReq(
            (r) => r
              ..vars.userId = userId
              ..vars.beaconId = beaconId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).inbox_item);
    if (rows.isEmpty) return null;
    final mapped = await _mapInboxItemRows(rows, userId);
    return mapped.first;
  }

  Future<({List<GInboxItemFields> rows, int? totalCount})>
  _fetchActivityOffersPageRaw({
    required String userId,
    required DateTime at,
    required String id,
    required int limit,
    required bool includeAggregate,
  }) async {
    final response = await _remoteApiService
        .request(
          GActivityOffersReq(
            (r) => r
              ..vars.userId = userId
              ..vars.at = at
              ..vars.id = id
              ..vars.limit = limit,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    return (
      rows: response.inbox_item.toList(growable: false),
      totalCount: includeAggregate
          ? response.inbox_item_aggregate.aggregate?.count
          : null,
    );
  }

  Future<List<InboxItem>> _mapInboxItemRows(
    Iterable<GInboxItemFields> rows,
    String userId,
  ) async {
    final rowList = rows.toList(growable: false);
    final hints = await _roomHints.fetchByBeaconIds(
      rowList.map((e) => e.beacon_id),
    );
    return rowList
        .map(
          (e) => InboxItem(
            beaconId: e.beacon_id,
            context: e.context ?? '',
            forwardCount: e.forward_count,
            latestForwardAt: e.latest_forward_at,
            latestNotePreview: e.latest_note_preview,
            status: inboxItemStatusFromSmallint(e.status),
            rejectionMessage: e.rejection_message,
            beforeResponseTerminalAt: e.before_response_terminal_at,
            tombstoneDismissedAt: e.tombstone_dismissed_at,
            provenance: InboxProvenance.parse(
              e.inbox_provenance_data,
            ).withoutViewer(userId),
            isForwardedByMe: e.beacon.my_forward_edges.isNotEmpty,
            beacon: (e.beacon as BeaconModel).toEntity(),
            roomHints: hints[e.beacon_id],
          ),
        )
        .toList();
  }

  /// Current user's inbox row for this beacon (status + forward provenance).
  /// When there is no row, status is null and provenance is empty.
  Future<
    ({
      InboxItemStatus? status,
      InboxProvenance provenance,
      String latestNotePreview,
    })
  >
  fetchInboxContextForBeacon(String beaconId) => _remoteApiService
      .request(
        GInboxItemStatusForBeaconReq(
          (r) => r..vars.beaconId = beaconId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final rows = r.dataOrThrow(label: _label).inbox_item;
        if (rows.isEmpty) {
          return (
            status: null,
            provenance: InboxProvenance.empty,
            latestNotePreview: '',
          );
        }
        final row = rows.first;
        return (
          status: inboxItemStatusFromSmallint(row.status),
          provenance: InboxProvenance.parse(row.inbox_provenance_data),
          latestNotePreview: row.latest_note_preview,
        );
      });

  Future<void> setStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) async {
    await _remoteApiService
        .request(
          GInboxSetStatusReq(
            (r) => r
              ..vars.beaconId = beaconId
              ..vars.status = status.toSmallint
              ..vars.rejectionMessage = rejectionMessage,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    if (!_localMutationController.isClosed) {
      _localMutationController.add(null);
    }
  }

  Future<void> dismissTombstone({
    required String beaconId,
    DateTime? dismissedAt,
  }) async {
    final at = dismissedAt ?? DateTime.now().toUtc();
    await _remoteApiService
        .request(
          GInboxTombstoneDismissReq(
            (r) => r
              ..vars.beaconId = beaconId
              ..vars.dismissedAt = at,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    if (!_localMutationController.isClosed) {
      _localMutationController.add(null);
    }
  }

  static const _label = 'Inbox';
}
