import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:http/http.dart' show MultipartFile;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:built_collection/built_collection.dart' show ListBuilder;

import 'package:tentura/consts.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import '../../domain/exception.dart';
import '../gql/_g/beacon_create.req.gql.dart';
import '../gql/_g/beacon_fetch_by_id.req.gql.dart';
import '../gql/_g/beacon_delete_by_id.req.gql.dart';
import '../gql/_g/beacon_update_by_id.req.gql.dart';
import '../gql/_g/beacons_fetch_by_user_id.req.gql.dart';

@lazySingleton
class BeaconRepository {
  BeaconRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _controller = StreamController<RepositoryEvent<Beacon>>.broadcast();

  Stream<RepositoryEvent<Beacon>> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  //
  //
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    bool isEnabled = true,
    int limit = kFetchWindowSize,
  }) async {
    final request = GBeaconsFetchByUserIdReq(
      (b) => b.vars
        ..user_id = profileId
        ..enabled = isEnabled
        ..offset = offset
        ..limit = limit,
    );
    return _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beacon)
        .then((v) => v.map((e) => (e as BeaconModel).toEntity()));
  }

  //
  //
  Future<Beacon> fetchBeaconById(String id) => _remoteApiService
      .request(GBeaconFetchByIdReq((b) => b.vars.id = id))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beacon_by_pk as BeaconModel?)
      .then((v) => v == null ? throw BeaconFetchException(id) : v.toEntity());

  //
  //
  Future<Beacon> create(Beacon beacon) async {
    final request = GBeaconCreateReq((b) {
      b.vars
        ..title = beacon.title
        ..description = beacon.description
        ..context = beacon.context.isEmpty ? null : beacon.context
        ..tags = beacon.tags.isEmpty ? null : beacon.tags.join(',')
        ..startAt = beacon.startAt?.toIso8601String()
        ..endAt = beacon.endAt?.toIso8601String()
        ..coordinates = beacon.coordinates == null
            ? null
            : (GCoordinatesBuilder()
                ..lat = beacon.coordinates!.lat
                ..long = beacon.coordinates!.long)
        ..polling = beacon.polling == null
            ? null
            : (GPollingInputBuilder()
                ..question = beacon.polling!.question
                ..variants = ListBuilder(beacon.polling!.variants.values))
        ..image = beacon.image?.imageBytes == null
            ? null
            : MultipartFile.fromBytes(
                'image',
                beacon.image!.imageBytes!,
                contentType: MediaType.parse(beacon.image!.mimeType),
                filename: beacon.image!.fileName,
              );
    });
    final beaconId = await _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconCreate.id);
    final beaconNew = await fetchBeaconById(beaconId);
    _controller.add(RepositoryEventCreate(beaconNew));
    return beaconNew;
  }

  //
  //
  Future<void> delete(String id) async {
    final isOk = await _remoteApiService
        .request(GBeaconDeleteByIdReq((b) => b.vars.id = id))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconDeleteById);
    if (isOk) {
      _controller.add(
        RepositoryEventDelete(Beacon.empty.copyWith(id: id)),
      );
    } else {
      throw BeaconDeleteException(id);
    }
  }

  //
  //
  Future<void> setEnabled(
    bool isEnabled, {
    required String id,
  }) async {
    final request = GBeaconUpdateByIdReq((b) {
      b
        ..vars.id = id
        ..vars.enabled = isEnabled;
    });
    final beacon = await _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow().update_beacon_by_pk as BeaconModel?);
    if (beacon == null) {
      throw BeaconUpdateException(id);
    } else {
      _controller.add(RepositoryEventUpdate(beacon.toEntity()));
    }
  }

  static const _label = 'Beacon';
}
