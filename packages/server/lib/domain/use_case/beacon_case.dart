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

@Singleton(order: 2)
class BeaconCase {
  @FactoryMethod(preResolve: true)
  static Future<BeaconCase> createInstance(
    BeaconRepository beaconRepository,
    ImageRepository imageRepository,
    TasksRepository tasksRepository,
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

  final TasksRepository _tasksRepository;

  Future<BeaconEntity> create({
    required String userId,
    required String title,
    String? description,
    String? context,
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

    final beacon = await _beaconRepository.createBeacon(
      authorId: userId,
      title: title,
      context: (context?.isEmpty ?? true) ? null : context,
      description: description ?? '',
      hasPicture: imageBytes != null,
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      polling: polling == null
          ? null
          : (question: polling.question!, variants: polling.variants!),
      startAt: startAt,
      endAt: endAt,
    );

    if (beacon.polling?.variants != null) {
      for (final variant in beacon.polling!.variants) {
        await _meritrankRepository.putEdge(
          nodeA: variant.id,
          nodeB: beacon.id,
        );
      }
    }

    if (imageBytes != null) {
      await _imageRepository.putBeaconImage(
        authorId: userId,
        beaconId: beacon.id,
        bytes: imageBytes,
      );
      await _tasksRepository.schedule(
        TaskBeaconImageHash(
          details: TaskBeaconImageHashDetails(
            userId: userId,
            beaconId: beacon.id,
          ),
        ),
      );
    }

    return beacon;
  }

  Future<bool> deleteById({
    required String beaconId,
    required String userId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );

    await _imageRepository.deleteBeaconImage(
      authorId: beacon.author.id,
      beaconId: beacon.id,
    );
    await _beaconRepository.deleteBeaconById(beacon.id);

    return true;
  }
}
