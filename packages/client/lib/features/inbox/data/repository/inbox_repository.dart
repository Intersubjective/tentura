import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/inbox_item.dart';
import '../gql/_g/inbox_fetch.req.gql.dart';
import '../gql/_g/inbox_set_hidden.req.gql.dart';
import '../gql/_g/inbox_set_watching.req.gql.dart';

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
                isHidden: e.is_hidden,
                isWatching: e.is_watching,
                beacon: (e.beacon as BeaconModel).toEntity(),
              ),
            )
            .toList(),
      );

  Future<void> setHidden({
    required String beaconId,
    required bool isHidden,
  }) => _remoteApiService
      .request(
        GInboxSetHiddenReq(
          (r) => r..vars.beaconId = beaconId..vars.isHidden = isHidden,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<void> setWatching({
    required String beaconId,
    required bool isWatching,
  }) => _remoteApiService
      .request(
        GInboxSetWatchingReq(
          (r) => r..vars.beaconId = beaconId..vars.isWatching = isWatching,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  static const _label = 'Inbox';
}
