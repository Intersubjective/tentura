import 'dart:async';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/tasks_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';

import '../entity/task_entity.dart';

@Singleton(order: 2)
class UserCase {
  @FactoryMethod(preResolve: true)
  static Future<UserCase> createInstance(
    ImageRepository imageRepository,
    UserRepository userRepository,
    TaskRepository tasksRepository,
  ) async => UserCase(imageRepository, userRepository, tasksRepository);

  const UserCase(
    this._imageRepository,
    this._userRepository,
    this._tasksRepository,
  );

  final ImageRepository _imageRepository;

  final UserRepository _userRepository;

  final TaskRepository _tasksRepository;

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

    return UserEntity(id: id);
  }

  //
  Future<bool> deleteById({required String id}) async {
    await _userRepository.deleteById(id: id);
    await _imageRepository.deleteAllOf(userId: id);
    return true;
  }
}
