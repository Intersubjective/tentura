import 'dart:async';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';

import '../entity/beacon_entity.dart';
import '../entity/task_entity.dart';
import '../exception.dart';
import '_use_case_base.dart';

const kMaxImagesPerBeacon = 10;

const _kMaxIconCodeLength = 64;

bool _isValidIconCodeKey(String s) =>
    RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(s) && s.length <= _kMaxIconCodeLength;

/// Curated key from client catalog; rejects empty/oversized/non-[a-z0-9_] input.
String? _normalizeIconCode(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final truncated =
      t.length > _kMaxIconCodeLength ? t.substring(0, _kMaxIconCodeLength) : t;
  if (!_isValidIconCodeKey(truncated)) return null;
  return truncated;
}

@Singleton(order: 2)
final class BeaconCase extends UseCaseBase {
  @FactoryMethod(preResolve: true)
  static Future<BeaconCase> createInstance(
    Env env,
    Logger logger,
    BeaconRepositoryPort beaconRepository,
    ImageRepositoryPort imageRepository,
    TaskRepositoryPort tasksRepository,
    MeritrankRepositoryPort meritrankRepository,
  ) async => BeaconCase(
    beaconRepository,
    imageRepository,
    tasksRepository,
    meritrankRepository,
    env: env,
    logger: logger,
  );

  BeaconCase(
    this._beaconRepository,
    this._imageRepository,
    this._tasksRepository,
    this._meritrankRepository, {
    required super.env,
    required super.logger,
  });

  final MeritrankRepositoryPort _meritrankRepository;

  final BeaconRepositoryPort _beaconRepository;

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

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
    String? iconCode,
    int? iconBackground,
    bool draft = false,
  }) async {
    var effectivePolling = polling;
    if (draft) {
      if (effectivePolling != null) {
        final q = effectivePolling.question;
        final v = effectivePolling.variants;
        if (q == null ||
            q.trim().isEmpty ||
            v == null ||
            v.length < 2 ||
            v.where((e) => e.trim().isNotEmpty).length < 2) {
          effectivePolling = null;
        }
      }
    } else if (effectivePolling != null) {
      if (effectivePolling.question == null) {
        throw const BeaconCreateException(description: 'Question is required');
      }
      if (effectivePolling.variants == null) {
        throw const BeaconCreateException(description: 'Variants are required');
      }
      if (effectivePolling.variants!.length < 2) {
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

    final normalizedIcon = _normalizeIconCode(iconCode);
    final beacon = await _beaconRepository.createBeacon(
      authorId: userId,
      title: title,
      imageIds: imageIds.isEmpty ? null : imageIds,
      context: (context?.isEmpty ?? true) ? null : context,
      description: description ?? '',
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      polling: effectivePolling == null
          ? null
          : (question: effectivePolling.question!, variants: effectivePolling.variants!),
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      state: draft ? 3 : null,
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

  /// Persists edits to a draft beacon (state 3). Optional [polling] replaces poll when non-null.
  Future<BeaconEntity> updateDraft({
    required String userId,
    required String beaconId,
    required String title,
    String? description,
    String? context,
    String? tags,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    ({String? question, List<String>? variants})? polling,
    String? iconCode,
    int? iconBackground,
  }) async {
    var effectivePolling = polling;
    if (effectivePolling != null) {
      final q = effectivePolling.question;
      final v = effectivePolling.variants;
      if (q == null ||
          q.trim().isEmpty ||
          v == null ||
          v.length < 2 ||
          v.where((e) => e.trim().isNotEmpty).length < 2) {
        effectivePolling = null;
      }
    }

    final normalizedIcon = _normalizeIconCode(iconCode);
    final beacon = await _beaconRepository.updateDraftBeacon(
      beaconId: beaconId,
      userId: userId,
      title: title,
      description: description ?? '',
      context: context,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      polling: effectivePolling == null
          ? null
          : (
              question: effectivePolling.question!,
              variants: effectivePolling.variants!,
            ),
    );

    if (beacon.polling?.variants != null) {
      final pollingEntity = beacon.polling!;
      for (final variant in pollingEntity.variants) {
        await _meritrankRepository.putEdge(
          nodeA: variant.id,
          nodeB: pollingEntity.id,
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
