import 'dart:async';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';

/// Remote profile + change stream (implemented by [ProfileRepository]).
abstract class ProfileRepositoryPort {
  Future<void> dispose();

  Stream<RepositoryEvent<Profile>> get changes;

  Future<Profile> fetchById(String id);

  Future<void> update(
    Profile profile, {
    String? title,
    String? description,
    bool dropImage = false,
    ImageEntity? image,
  });

  Future<void> delete(String id);
}
