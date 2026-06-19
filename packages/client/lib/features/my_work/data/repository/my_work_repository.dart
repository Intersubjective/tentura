import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../model/beacon_model_with_help_offer_users.dart';
import '../../domain/entity/my_work_last_event.dart';
import '../../domain/entity/my_work_fetch_types.dart';
import '../gql/_g/my_work_coordination_activity.req.gql.dart';
import '../gql/_g/my_work_fetch.data.gql.dart';
import '../gql/_g/my_work_fetch.req.gql.dart';
import '../gql/_g/my_work_last_activity_event.req.gql.dart';

export '../../domain/entity/my_work_fetch_types.dart'
    show MyWorkClosedResult, MyWorkHelpOfferedRow, MyWorkInitResult;

@Singleton(env: [Environment.dev, Environment.prod])
class MyWorkRepository {
  MyWorkRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _kNetworkTimeout = Duration(seconds: 60);

  Future<MyWorkInitResult> fetchInit({required String userId}) async {
    final r = await _remoteApiService
        .request(
          GMyWorkInitReq((b) => b..vars.userId = userId),
        )
        .timeout(_kNetworkTimeout)
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final d = r.dataOrThrow(label: _label);
    final beaconIds = <String>{
      for (final e in d.authoredNonClosed) e.id,
      for (final e in d.helpOfferedNonClosed) e.beacon.id,
    }.toList();
    final itemActivity = await _fetchItemDiscussionActivity(beaconIds);
    return (
      authoredNonClosed: d.authoredNonClosed
          .map((e) => BeaconModelWithHelpOfferUsers(e).toEntity())
          .toList(),
      helpOfferedNonClosed:
          d.helpOfferedNonClosed.map(_mapInitHelpOfferedRow).toList(),
      authoredClosedIds: d.authoredClosedIds.map((e) => e.id).toList(),
      helpOfferedClosedIds:
          d.helpOfferedClosedIds.map((e) => e.beacon.id).toList(),
      lastItemDiscussionMessageAtByBeaconId: itemActivity,
    );
  }

  Future<Map<String, DateTime>> _fetchItemDiscussionActivity(
    List<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) {
      return const {};
    }
    final r = await _remoteApiService
        .request(
          GMyWorkCoordinationItemActivityReq(
            (b) => b.vars.beaconIds.replace(beaconIds),
          ),
        )
        .timeout(_kNetworkTimeout)
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final rows = r.dataOrThrow(label: _label).myWorkCoordinationItemActivity;
    final out = <String, DateTime>{};
    for (final row in rows) {
      final at = row.lastCoordinationItemMessageAt;
      if (at != null && at.isNotEmpty) {
        out[row.beaconId] = DateTime.parse(at);
      }
    }
    return out;
  }

  Future<Map<String, MyWorkLastEvent?>> fetchLastActivityEventsByBeaconId(
    List<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) {
      return const {};
    }
    final r = await _remoteApiService
        .request(
          GMyWorkLastActivityEventReq(
            (b) => b.vars.beaconIds.replace(beaconIds),
          ),
        )
        .timeout(_kNetworkTimeout)
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final rows = r.dataOrThrow(label: _label).myWorkLastActivityEvent;
    final out = <String, MyWorkLastEvent?>{};
    for (final row in rows) {
      final eventId = row.id;
      final eventType = row.type;
      final createdAtRaw = row.createdAt;
      if (eventId == null ||
          eventType == null ||
          createdAtRaw == null ||
          createdAtRaw.isEmpty) {
        out[row.beaconId] = null;
        continue;
      }
      final actorId = row.actorId ?? '';
      final actor = Profile(
        id: actorId,
        displayName: row.actorTitle ?? '',
        contactName: actorId.isEmpty ? '' : contactNameOf(actorId),
        image: (row.actorImageId ?? '').isEmpty
            ? null
            : ImageEntity(id: row.actorImageId!),
      );
      out[row.beaconId] = MyWorkLastEvent(
        event: BeaconActivityEvent(
          id: eventId,
          beaconId: row.beaconId,
          visibility: 0,
          type: eventType,
          createdAt: DateTime.parse(createdAtRaw).toLocal(),
          actorId: actorId.isEmpty ? null : actorId,
        ),
        actor: actor,
      );
    }
    return out;
  }

  Future<MyWorkClosedResult> fetchClosed({required String userId}) async {
    final r = await _remoteApiService
        .request(
          GMyWorkClosedReq((b) => b..vars.userId = userId),
        )
        .timeout(_kNetworkTimeout)
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final d = r.dataOrThrow(label: _label);
    return (
      authoredClosed:
          d.authoredClosed.map((e) => BeaconModelWithHelpOfferUsers(e).toEntity()).toList(),
      helpOfferedClosed:
          d.helpOfferedClosed.map(_mapClosedHelpOfferedRow).toList(),
    );
  }

  static MyWorkHelpOfferedRow _mapInitHelpOfferedRow(
    GMyWorkInitData_helpOfferedNonClosed e,
  ) {
    final b = e.beacon;
    final beacon = BeaconModelWithHelpOfferUsers(b).toEntity();
    final forwarders = b.forward_edges
        .map((fe) => UserModel(fe.sender).toEntity())
        .toList();
    return (
      beacon: beacon,
      offerHelpMessage: e.message,
      helpType: e.help_type,
      authorResponseType: CoordinationResponseType.tryFromInt(
        e.coordination?.response_type,
      ),
      forwarderSenders: forwarders,
      helpOfferRowUpdatedAt: e.updated_at,
      authorCoordinationUpdatedAt: e.coordination?.updated_at,
    );
  }

  static MyWorkHelpOfferedRow _mapClosedHelpOfferedRow(
    GMyWorkClosedData_helpOfferedClosed e,
  ) {
    final b = e.beacon;
    final beacon = BeaconModelWithHelpOfferUsers(b).toEntity();
    final forwarders = b.forward_edges
        .map((fe) => UserModel(fe.sender).toEntity())
        .toList();
    return (
      beacon: beacon,
      offerHelpMessage: e.message,
      helpType: e.help_type,
      authorResponseType: CoordinationResponseType.tryFromInt(
        e.coordination?.response_type,
      ),
      forwarderSenders: forwarders,
      helpOfferRowUpdatedAt: e.updated_at,
      authorCoordinationUpdatedAt: e.coordination?.updated_at,
    );
  }

  static const _label = 'MyWork';
}
