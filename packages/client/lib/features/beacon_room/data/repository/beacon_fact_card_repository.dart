import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';

import '../gql/_g/beacon_fact_card_correct.req.gql.dart';
import '../gql/_g/beacon_fact_card_list.data.gql.dart';
import '../gql/_g/beacon_fact_card_list.req.gql.dart';
import '../gql/_g/beacon_fact_card_pin.req.gql.dart';
import '../gql/_g/beacon_fact_card_remove.req.gql.dart';

@lazySingleton
class BeaconFactCardRepository {
  BeaconFactCardRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'BeaconFactCard';

  BeaconFactCard _mapRow(GBeaconFactCardListData_BeaconFactCardList row) =>
      BeaconFactCard(
        id: row.id,
        beaconId: row.beaconId,
        factText: row.factText,
        visibility: row.visibility,
        pinnedBy: row.pinnedBy,
        createdAt: DateTime.parse(row.createdAt),
        status: row.status,
        sourceMessageId: row.sourceMessageId,
        updatedAt:
            row.updatedAt != null ? DateTime.parse(row.updatedAt!) : null,
      );

  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    final r = await _remoteApiService
        .request(GBeaconFactCardListReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final raw = r.dataOrThrow(label: _label).BeaconFactCardList.toList();
    return raw.map(_mapRow).toList(growable: false);
  }

  Future<void> pin({
    required String beaconId,
    required String factText,
    required int visibility,
    String? sourceMessageId,
  }) async {
    await _remoteApiService
        .request(
          GBeaconFactCardPinReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factText = factText
              ..visibility = visibility
              ..sourceMessageId = sourceMessageId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconFactCardPin);
  }

  Future<void> correct({
    required String beaconId,
    required String factCardId,
    required String newText,
  }) async {
    await _remoteApiService
        .request(
          GBeaconFactCardCorrectReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factCardId = factCardId
              ..newText = newText,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconFactCardCorrect);
  }

  Future<void> remove({
    required String beaconId,
    required String factCardId,
  }) async {
    await _remoteApiService
        .request(
          GBeaconFactCardRemoveReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factCardId = factCardId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconFactCardRemove);
  }
}
