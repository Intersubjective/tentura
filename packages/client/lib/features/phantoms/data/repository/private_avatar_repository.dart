import 'dart:typed_data';

import 'package:get_it/get_it.dart';
import 'package:tentura/data/gql/tentura_v2_upload.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/env.dart';

import '../../domain/entity/person_note.dart';
import '../gql/_g/person_private_avatar.req.gql.dart';

final class PrivateAvatarRepository {
  const PrivateAvatarRepository();

  RemoteApiService get _remote => GetIt.I<RemoteApiService>();

  Future<void> upload(PersonNoteSubject subject, ImagePicked photo) async {
    const label = 'PersonPrivateAvatarUpload';
    final response = await _remote
        .request(
          GPersonPrivateAvatarUploadReq(
            (b) => b.vars
              ..subjectUserId = subject is UserNoteSubject ? subject.id : null
              ..subjectPhantomId = subject is PhantomNoteSubject
                  ? subject.id
                  : null
              ..file = TenturaV2Upload(
                filename: photo.fileName,
                mimeType: 'image/jpeg',
                bytes: photo.bytes,
              ),
          ),
        )
        .firstLinkResponse(label: label);
    if (!response.dataOrThrow(label: label).personPrivateAvatarUpload) {
      throw const UnknownException();
    }
  }

  Future<void> remove(PersonNoteSubject subject) async {
    const label = 'PersonPrivateAvatarDelete';
    final response = await _remote
        .request(
          GPersonPrivateAvatarDeleteReq(
            (b) => b.vars
              ..subjectUserId = subject is UserNoteSubject ? subject.id : null
              ..subjectPhantomId = subject is PhantomNoteSubject
                  ? subject.id
                  : null,
          ),
        )
        .firstLinkResponse(label: label);
    if (!response.dataOrThrow(label: label).personPrivateAvatarDelete) {
      throw const UnknownException();
    }
  }

  Future<Uint8List> read(String objectKey) => _remote.fetchAuthenticatedBytes(
    Uri.parse(kServerName).replace(
      path: '/api/v2/private-avatars',
      queryParameters: {'objectKey': objectKey},
    ),
  );
}
