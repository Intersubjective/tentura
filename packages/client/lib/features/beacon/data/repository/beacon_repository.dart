import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:http/http.dart' show MultipartFile;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:built_collection/built_collection.dart' show ListBuilder;

import 'package:tentura/consts.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/domain/entity/image_entity.dart';

import '../../domain/exception.dart';
import '../gql/_g/beacon_add_image.req.gql.dart';
import '../gql/_g/beacon_create.req.gql.dart';
import '../gql/_g/beacon_fetch_by_id.req.gql.dart';
import '../gql/_g/beacon_delete_by_id.req.gql.dart';
import '../gql/_g/beacon_remove_image.req.gql.dart';
import '../gql/_g/beacon_update_by_id.req.gql.dart';
import '../gql/_g/beacons_fetch_by_user_id.req.gql.dart';

@lazySingleton
class BeaconRepository {
  BeaconRepository(
    this._remoteApiService,
    InvalidationService invalidationService,
  ) {
    _invalidationSub = invalidationService.beaconInvalidations.listen(
      (id) => _controller.add(
        RepositoryEventInvalidate(Beacon.empty.copyWith(id: id)),
      ),
    );
  }

  final RemoteApiService _remoteApiService;

  late final StreamSubscription<String> _invalidationSub;

  final _controller = StreamController<RepositoryEvent<Beacon>>.broadcast();

  Stream<RepositoryEvent<Beacon>> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() async {
    await _invalidationSub.cancel();
    await _controller.close();
  }

  //
  //
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    required List<int> lifecycleStates,
    int limit = kFetchWindowSize,
  }) async {
    final request = GBeaconsFetchByUserIdReq(
      (b) => b.vars
        ..user_id = profileId
        ..active_states.replace(lifecycleStates)
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
    final firstImage = beacon.images.isEmpty ? null : beacon.images.first;
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
            : (Gv2_CoordinatesBuilder()
                  ..lat = beacon.coordinates!.lat
                  ..long = beacon.coordinates!.long)
        ..polling = beacon.polling == null
            ? null
            : (Gv2_PollingInputBuilder()
                  ..question = beacon.polling!.question
                  ..variants = ListBuilder(beacon.polling!.variants.values))
        ..image = firstImage?.imageBytes == null
            ? null
            : MultipartFile.fromBytes(
                'image',
                firstImage!.imageBytes!,
                contentType: MediaType.parse(firstImage.mimeType),
                filename: firstImage.fileName,
              );
    });
    final beaconId = await _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconCreate.id);

    // Upload additional images (index 1+) via beaconAddImage
    for (var i = 1; i < beacon.images.length; i++) {
      final img = beacon.images[i];
      if (img.imageBytes != null) {
        await addImage(beaconId: beaconId, image: img);
      }
    }

    final beaconNew = await fetchBeaconById(beaconId);
    _controller.add(RepositoryEventCreate(beaconNew));
    return beaconNew;
  }

  //
  //
  Future<void> addImage({
    required String beaconId,
    required ImageEntity image,
  }) async {
    if (image.imageBytes == null) return;
    final request = GBeaconAddImageReq((b) {
      b.vars
        ..id = beaconId
        ..image = MultipartFile.fromBytes(
          'image',
          image.imageBytes!,
          contentType: MediaType.parse(image.mimeType),
          filename: image.fileName,
        );
    });
    await _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconAddImage.id);
  }

  //
  //
  Future<void> removeImage({
    required String beaconId,
    required String imageId,
  }) async {
    final isOk = await _remoteApiService
        .request(GBeaconRemoveImageReq((b) {
          b.vars
            ..beaconId = beaconId
            ..imageId = imageId;
        }))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconRemoveImage);
    if (!isOk) {
      throw BeaconUpdateException(beaconId);
    }
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
  Future<void> setBeaconLifecycle(
    BeaconLifecycle lifecycle, {
    required String id,
  }) async {
    final request = GBeaconUpdateByIdReq((b) {
      b
        ..vars.id = id
        ..vars.state = lifecycle.smallintValue;
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
