import 'dart:typed_data';

import '../entity/person_subject.dart';

abstract interface class PrivateAvatarRepositoryPort {
  Future<void> put({
    required String ownerId,
    required PersonSubject subject,
    required Stream<Uint8List> bytes,
  });

  Future<void> remove({
    required String ownerId,
    required PersonSubject subject,
  });

  Future<Uint8List> get({
    required String viewerId,
    required String objectKey,
  });
}
