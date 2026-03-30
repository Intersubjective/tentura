import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/entity/inbox_provenance.dart';
import '../../domain/enum.dart';
import '../gql/_g/inbox_fetch.req.gql.dart';
import '../gql/_g/inbox_set_status.req.gql.dart';

@lazySingleton
class InboxRepository {
  InboxRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

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
                provenance: InboxProvenance.parse(e.inbox_provenance_data),
                beacon: (e.beacon as BeaconModel).toEntity(),
              ),
            )
            .toList(),
      );

  Future<void> setStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) => _remoteApiService
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

  static const _label = 'Inbox';
}
