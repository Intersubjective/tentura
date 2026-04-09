import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/entity/inbox_provenance.dart';
import '../../domain/enum.dart';
import '../gql/_g/inbox_fetch.req.gql.dart';
import '../gql/_g/inbox_item_status_for_beacon.req.gql.dart';
import '../gql/_g/inbox_set_status.req.gql.dart';
import '../gql/_g/inbox_tombstone_dismiss.req.gql.dart';

@lazySingleton
class InboxRepository {
  InboxRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _localMutationController = StreamController<void>.broadcast();

  /// Fires after a successful local [setStatus] (e.g. from beacon detail).
  Stream<void> get localMutations => _localMutationController.stream;

  @disposeMethod
  Future<void> dispose() => _localMutationController.close();

  Future<List<InboxItem>> fetch({required String context}) => _remoteApiService
      .request(GInboxFetchReq((r) => r..vars.context = context))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).inbox_item)
      .then(
        (v) => v
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
                provenance: InboxProvenance.parse(e.inbox_provenance_data),
                beacon: (e.beacon as BeaconModel).toEntity(),
              ),
            )
            .toList(),
      );

  /// Current user's inbox row for this beacon, if any (`null` = no row).
  Future<InboxItemStatus?> fetchStatusForBeacon(String beaconId) =>
      _remoteApiService
          .request(
            GInboxItemStatusForBeaconReq(
              (r) => r..vars.beaconId = beaconId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final rows = r.dataOrThrow(label: _label).inbox_item;
            if (rows.isEmpty) return null;
            return inboxItemStatusFromSmallint(rows.first.status);
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
