import 'dart:async';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

import '../entity/task_entity.dart';
import '../entity/user_entity.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class UserCase extends UseCaseBase {
  @FactoryMethod(preResolve: true)
  static Future<UserCase> createInstance(
    Env env,
    Logger logger,
    ImageRepositoryPort imageRepository,
    UserRepositoryPort userRepository,
    TaskRepositoryPort tasksRepository,
  ) async => UserCase(
    imageRepository,
    userRepository,
    tasksRepository,
    env: env,
    logger: logger,
  );

  UserCase(
    this._imageRepository,
    this._userRepository,
    this._tasksRepository, {
    required super.env,
    required super.logger,
  });

  final ImageRepositoryPort _imageRepository;

  final UserRepositoryPort _userRepository;

  final TaskRepositoryPort _tasksRepository;

  //
  Future<UserEntity> updateProfile({
    required String id,
    String? title,
    String? description,
    Stream<Uint8List>? imageBytes,
    bool? dropImage,
  }) async {
    String? imageId;
    final needDropImage = dropImage ?? false;

    if (needDropImage || imageBytes != null) {
      final user = await _userRepository.getById(id);
      if (user.image != null) {
        await _imageRepository.delete(authorId: id, imageId: user.image!.id);
      }
    }

    if (imageBytes != null) {
      imageId = await _imageRepository.put(authorId: id, bytes: imageBytes);
      await _tasksRepository.schedule(
        TaskEntity(
          details: TaskCalculateImageHashDetails(imageId: imageId),
        ),
      );
    }

    await _userRepository.update(
      id: id,
      title: title,
      description: description,
      dropImage: needDropImage,
      imageId: imageId,
    );

    return _userRepository.getById(id);
  }

  //
  Future<bool> deleteById({required String id}) async {
    await _userRepository.deleteById(id: id);
    await _imageRepository.deleteAllOf(userId: id);
    return true;
  }
}
