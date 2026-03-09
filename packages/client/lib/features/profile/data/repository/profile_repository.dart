import 'dart:async';
import 'package:http/http.dart' show MultipartFile;
import 'package:http_parser/http_parser.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import '../../domain/exception.dart';
import '../gql/_g/profile_delete.req.gql.dart';
import '../gql/_g/profile_update.req.gql.dart';
import '../gql/_g/user_fetch_by_id.req.gql.dart';

@singleton
class ProfileRepository {
  ProfileRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _controller = StreamController<RepositoryEvent<Profile>>.broadcast();

  Stream<RepositoryEvent<Profile>> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  //
  Future<Profile> fetchById(String id) async {
    final request = GUserFetchByIdReq((b) => b.vars.id = id);
    final response = await _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).user_by_pk)
        .then((r) => (r as UserModel?)?.toEntity());
    if (response == null) throw ProfileFetchException(id);
    _controller.add(RepositoryEventFetch(response));
    return response;
  }

  //
  Future<void> update(
    Profile profile, {
    String? title,
    String? description,
    bool dropImage = false,
    ImageEntity? image,
  }) async {
    final request = GProfileUpdateReq((b) {
      b.fetchPolicy = FetchPolicy.NoCache;
      b.vars
        ..title = title
        ..description = description
        ..dropImage = dropImage
        ..image = image?.imageBytes == null
            ? null
            : MultipartFile.fromBytes(
                'image',
                image!.imageBytes!,
                contentType: MediaType.parse(image.mimeType),
                filename: image.fileName,
              );
    });

    await _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));

    _controller.add(RepositoryEventUpdate(await fetchById(profile.id)));
  }

  //
  Future<void> delete(String id) async {
    final isOk = await _remoteApiService
        .request(GProfileDeleteReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).userDelete);
    if (isOk) {
      _controller.add(RepositoryEventDelete(Profile(id: id)));
    } else {
      throw ProfileDeleteException(id);
    }
  }

  static const _label = 'Profile';
}
