import 'dart:async';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';

import '../entity/beacon_entity.dart';
import '../entity/task_entity.dart';
import '../exception.dart';
import '_use_case_base.dart';

const kMaxImagesPerBeacon = 10;

const _kMaxIconCodeLength = 64;

const _kNeedSummaryHardMax = 280;

const _kNeedSummaryPublishMin = 16;

const _kSuccessCriteriaHardMax = 240;

String? _trimOrNull(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  return t.isEmpty ? null : t;
}

String _normalizeBeaconDescription(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) {
    throw const BeaconCreateException(description: 'Description is required');
  }
  if (t.length > kBeaconDescriptionMaxLength) {
    throw const BeaconCreateException(description: 'Description is too long');
  }
  return t;
}

void _validateNeedSummaryLength(String? ns) {
  if (ns != null && ns.length > _kNeedSummaryHardMax) {
    throw const BeaconCreateException(
      description: 'Need summary must be 280 characters or fewer',
    );
  }
}

void _validateSuccessCriteriaLength(String? sc) {
  if (sc != null && sc.length > _kSuccessCriteriaHardMax) {
    throw const BeaconCreateException(
      description: 'Success criteria must be 240 characters or fewer',
    );
  }
}

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
  ) async => BeaconCase(
    beaconRepository,
    imageRepository,
    tasksRepository,
    env: env,
    logger: logger,
  );

  BeaconCase(
    this._beaconRepository,
    this._imageRepository,
    this._tasksRepository, {
    required super.env,
    required super.logger,
  });

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
    String? iconCode,
    int? iconBackground,
    bool draft = false,
    String? needSummary,
    String? successCriteria,
  }) async {
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
    final ns = _trimOrNull(needSummary);
    final sc = _trimOrNull(successCriteria);
    final desc = _normalizeBeaconDescription(description);
    _validateNeedSummaryLength(ns);
    _validateSuccessCriteriaLength(sc);
    if (!draft && (ns == null || ns.length < _kNeedSummaryPublishMin)) {
      throw const BeaconNeedSummaryTooShortException();
    }
    final beacon = await _beaconRepository.createBeacon(
      authorId: userId,
      title: title,
      imageIds: imageIds.isEmpty ? null : imageIds,
      context: (context?.isEmpty ?? true) ? null : context,
      description: desc,
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      state: draft ? 3 : null,
      needSummary: ns,
      successCriteria: sc,
    );

    return beacon;
  }

  /// Persists edits to a draft beacon (state 3).
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
    String? iconCode,
    int? iconBackground,
    String? needSummary,
    String? successCriteria,
  }) async {

    final normalizedIcon = _normalizeIconCode(iconCode);
    final ns = _trimOrNull(needSummary);
    final sc = _trimOrNull(successCriteria);
    final desc = _normalizeBeaconDescription(description);
    _validateNeedSummaryLength(ns);
    _validateSuccessCriteriaLength(sc);
    final beacon = await _beaconRepository.updateDraftBeacon(
      beaconId: beaconId,
      userId: userId,
      title: title,
      description: desc,
      context: context,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      needSummary: ns,
      successCriteria: sc,
    );
    return beacon;
  }

  /// Updates an open (published) beacon.
  Future<BeaconEntity> update({
    required String userId,
    required String beaconId,
    required String title,
    String? description,
    String? context,
    String? tags,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? iconCode,
    int? iconBackground,
    String? needSummary,
    String? successCriteria,
  }) async {
    final normalizedIcon = _normalizeIconCode(iconCode);
    final ns = _trimOrNull(needSummary);
    final sc = _trimOrNull(successCriteria);
    final desc = _normalizeBeaconDescription(description);
    _validateNeedSummaryLength(ns);
    _validateSuccessCriteriaLength(sc);
    if (ns != null &&
        ns.isNotEmpty &&
        ns.length < _kNeedSummaryPublishMin) {
      throw const BeaconNeedSummaryTooShortException();
    }
    return _beaconRepository.updateBeacon(
      beaconId: beaconId,
      userId: userId,
      title: title,
      description: desc,
      context: context,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      needSummary: ns,
      successCriteria: sc,
    );
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

  /// Author or steward sets outward [BeaconEntity.publicStatus].
  Future<BeaconEntity> updatePublicStatus({
    required String userId,
    required String beaconId,
    required int publicStatus,
    String? lastPublicMeaningfulChange,
  }) =>
      _beaconRepository.updatePublicStatus(
        beaconId: beaconId,
        userId: userId,
        publicStatus: publicStatus,
        lastPublicMeaningfulChange: lastPublicMeaningfulChange,
      );

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
