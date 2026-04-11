import 'dart:async';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/tasks_repository.dart';

import '../entity/task_entity.dart';
import '../exception.dart';

const kMaxImagesPerBeacon = 10;

@Singleton(order: 2)
class BeaconCase {
  @FactoryMethod(preResolve: true)
  static Future<BeaconCase> createInstance(
    BeaconRepository beaconRepository,
    ImageRepository imageRepository,
    TaskRepository tasksRepository,
    MeritrankRepository meritrankRepository,
  ) async => BeaconCase(
    beaconRepository,
    imageRepository,
    tasksRepository,
    meritrankRepository,
  );

  const BeaconCase(
    this._beaconRepository,
    this._imageRepository,
    this._tasksRepository,
    this._meritrankRepository,
  );

  final MeritrankRepository _meritrankRepository;

  final BeaconRepository _beaconRepository;

  final ImageRepository _imageRepository;

  final TaskRepository _tasksRepository;

  //
  Future<BeaconEntity> create({
    required String userId,
    required String title,
    String? description,
    String? context,
    String? tags,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    Stream<Uint8List>? imageBytes,
    ({String? question, List<String>? variants})? polling,
  }) async {
    if (polling != null) {
      if (polling.question == null) {
        throw const BeaconCreateException(description: 'Question is required');
      }
      if (polling.variants == null) {
        throw const BeaconCreateException(description: 'Variants are required');
      }
      if (polling.variants!.length < 2) {
        throw const BeaconCreateException(description: 'Too few variants');
      }
    }

    final imageIds = <String>[];

    if (imageBytes != null) {
      final imageId = await _imageRepository.put(
        authorId: userId,
        bytes: imageBytes,
      );
      imageIds.add(imageId);
      await _tasksRepository.schedule(
        TaskEntity(
          details: TaskCalculateImageHashDetails(imageId: imageId),
        ),
      );
    }

    final beacon = await _beaconRepository.createBeacon(
      authorId: userId,
      title: title,
      imageIds: imageIds.isEmpty ? null : imageIds,
      context: (context?.isEmpty ?? true) ? null : context,
      description: description ?? '',
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      polling: polling == null
          ? null
          : (question: polling.question!, variants: polling.variants!),
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      startAt: startAt,
      endAt: endAt,
    );

    if (beacon.polling?.variants != null) {
      final polling = beacon.polling!;
      for (final variant in polling.variants) {
        await _meritrankRepository.putEdge(
          nodeA: variant.id,
          nodeB: polling.id,
        );
      }
    }
    return beacon;
  }

  //
  Future<BeaconEntity> addImage({
    required String beaconId,
    required String userId,
    required Stream<Uint8List> imageBytes,
  }) async {
    final currentCount = await _beaconRepository.getImageCount(beaconId);
    if (currentCount >= kMaxImagesPerBeacon) {
      throw const BeaconCreateException(
        description: 'Maximum images per beacon reached',
      );
    }

    final imageId = await _imageRepository.put(
      authorId: userId,
      bytes: imageBytes,
    );
    await _tasksRepository.schedule(
      TaskEntity(
        details: TaskCalculateImageHashDetails(imageId: imageId),
      ),
    );

    await _beaconRepository.addImage(
      beaconId: beaconId,
      imageId: imageId,
      position: currentCount,
    );

    return _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );
  }

  //
  Future<bool> removeImage({
    required String beaconId,
    required String imageId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );

    // Deleting the image row cascades to beacon_image via FK ON DELETE CASCADE
    await _imageRepository.delete(
      authorId: beacon.author.id,
      imageId: imageId,
    );

    return true;
  }

  //
  Future<bool> reorderImages({
    required String beaconId,
    required String userId,
    required List<String> imageIds,
  }) async {
    // Verify ownership
    await _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );

    await _beaconRepository.reorderImages(
      beaconId: beaconId,
      imageIds: imageIds,
    );

    return true;
  }

  //
  Future<bool> deleteById({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );

    for (final image in beacon.images) {
      await _imageRepository.delete(
        authorId: beacon.author.id,
        imageId: image.id,
      );
    }

    await _beaconRepository.deleteBeaconById(beacon.id, userId: userId);

    return true;
  }
}
