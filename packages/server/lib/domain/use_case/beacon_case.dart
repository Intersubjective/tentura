import 'dart:async';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/evaluation/acknowledged_committer.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '../entity/beacon_entity.dart';
import '../entity/gql_public/beacon_close_review_result.dart';
import '../entity/task_entity.dart';
import '_use_case_base.dart';

const kMaxImagesPerBeacon = 10;

const _kMaxIconCodeLength = 64;

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

Set<String>? _normalizeNeeds(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final slugs = raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  for (final slug in slugs) {
    if (!kAllowedCapabilitySlugs.contains(slug)) {
      throw BeaconCreateException(
        description: 'Unknown capability slug: $slug',
      );
    }
  }
  return slugs.isEmpty ? null : slugs;
}

bool _isValidIconCodeKey(String s) =>
    RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(s) && s.length <= _kMaxIconCodeLength;

/// Curated key from client catalog; rejects empty/oversized/non-[a-z0-9_] input.
String? _normalizeIconCode(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final truncated = t.length > _kMaxIconCodeLength
      ? t.substring(0, _kMaxIconCodeLength)
      : t;
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
    CoordinationRepositoryPort coordinationRepository,
    HelpOfferRepositoryPort helpOfferRepository,
    BeaconAccessGuard guard,
  ) async => BeaconCase(
    beaconRepository,
    imageRepository,
    tasksRepository,
    coordinationRepository,
    helpOfferRepository,
    guard,
    env: env,
    logger: logger,
  );

  BeaconCase(
    this._beaconRepository,
    this._imageRepository,
    this._tasksRepository,
    this._coordinationRepository,
    this._helpOfferRepository,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

  final CoordinationRepositoryPort _coordinationRepository;

  final HelpOfferRepositoryPort _helpOfferRepository;

  final BeaconAccessGuard _guard;

  /// Spam control: reject when an author has created too many beacons within
  /// the configured trailing window.
  Future<void> _enforceCreateRateLimit(String userId) async {
    final recent = await _beaconRepository.countRecentByAuthor(
      userId: userId,
      window: env.beaconCreateRateWindow,
    );
    if (recent >= env.beaconCreateMaxPerUser) {
      logger.info('beacon create rate-limited for user $userId');
      throw const RateLimitedException(
        description: 'Too many requests created recently, please wait',
      );
    }
  }

  //
  Future<BeaconEntity> create({
    required String userId,
    required String title,
    String? description,
    String? context,
    String? tags,
    String? needs,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    Stream<Uint8List>? imageBytes,
    String? iconCode,
    int? iconBackground,
    bool draft = false,
    String? addressLabel,
  }) async {
    await _enforceCreateRateLimit(userId);
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
    final desc = _normalizeBeaconDescription(description);
    final beacon = await _beaconRepository.createBeacon(
      authorId: userId,
      title: title,
      imageIds: imageIds.isEmpty ? null : imageIds,
      context: (context?.isEmpty ?? true) ? null : context,
      description: desc,
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      needs: _normalizeNeeds(needs),
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      status: draft ? BeaconStatus.draft : null,
      addressLabel: _trimOrNull(addressLabel),
    );

    return beacon;
  }

  /// Publishes a draft beacon (state 3 → 0) and emits a `beaconPublished` event.
  Future<BeaconEntity> publishDraft({
    required String userId,
    required String beaconId,
  }) async {
    await _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );
    return _beaconRepository.publishDraft(id: beaconId, actorId: userId);
  }

  /// Persists edits to a draft beacon (state 3).
  Future<BeaconEntity> updateDraft({
    required String userId,
    required String beaconId,
    required String title,
    String? description,
    String? context,
    String? tags,
    String? needs,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? iconCode,
    int? iconBackground,
    String? addressLabel,
  }) async {
    final normalizedIcon = _normalizeIconCode(iconCode);
    final desc = _normalizeBeaconDescription(description);
    final beacon = await _beaconRepository.updateDraftBeacon(
      beaconId: beaconId,
      userId: userId,
      title: title,
      description: desc,
      context: context,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      needs: _normalizeNeeds(needs),
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      addressLabel: _trimOrNull(addressLabel),
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
    String? needs,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? iconCode,
    int? iconBackground,
    String? addressLabel,
  }) async {
    final normalizedIcon = _normalizeIconCode(iconCode);
    final desc = _normalizeBeaconDescription(description);
    return _beaconRepository.updateBeacon(
      beaconId: beaconId,
      userId: userId,
      title: title,
      description: desc,
      context: context,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      needs: _normalizeNeeds(needs),
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      startAt: startAt,
      endAt: endAt,
      iconCode: normalizedIcon,
      iconBackground: normalizedIcon == null ? null : iconBackground,
      addressLabel: _trimOrNull(addressLabel),
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
        description: 'Maximum images per request reached',
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

  /// Creates a DRAFT beacon from a visible source, copying reusable content only.
  Future<BeaconEntity> fork({
    required String sourceId,
    required String userId,
  }) async {
    await _enforceCreateRateLimit(userId);
    final source = await _beaconRepository.getBeaconById(beaconId: sourceId);
    await assertBeaconLineageSourceVisible(
      guard: _guard,
      beaconId: sourceId,
      userId: userId,
    );

    final imageIds = <String>[];
    if (source.author.id == userId && source.images.isNotEmpty) {
      for (final image in source.images) {
        final bytes = await _imageRepository.get(id: image.id);
        final newId = await _imageRepository.put(
          authorId: userId,
          bytes: Stream.value(bytes),
        );
        imageIds.add(newId);
        await _tasksRepository.schedule(
          TaskEntity(
            details: TaskCalculateImageHashDetails(imageId: newId),
          ),
        );
      }
    }

    final draft = await _beaconRepository.createBeacon(
      authorId: userId,
      title: source.title,
      description: source.description,
      context: source.context,
      latitude: source.coordinates?.lat,
      longitude: source.coordinates?.long,
      tags: source.tags,
      needs: source.needs,
      iconCode: source.iconCode,
      iconBackground: source.iconBackground,
      status: BeaconStatus.draft,
      imageIds: imageIds.isEmpty ? null : imageIds,
      lineageParentBeaconId: source.id,
      lineageRootBeaconId: source.lineageRootBeaconId ?? source.id,
    );

    return draft;
  }

  /// Author cancels an open beacon with zero acknowledged committers (state 1).
  Future<BeaconCloseReviewResult> beaconCancel({
    required String beaconId,
    required String userId,
  }) => _beaconRepository.runInBeaconStateTransaction(
    beaconId: beaconId,
    userId: userId,
    fn: (beacon) async {
      if (!beacon.status.isOpenFamily) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.beaconNotClosable,
          description: 'Request must be open to cancel',
        );
      }
      if (beacon.author.id != userId) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.notEligible,
          description: 'Only the author can cancel',
        );
      }
      final coords = await _coordinationRepository
          .coordinationResponseTypeByOfferUserId(
            beaconId,
          );
      final activeOffers = await _helpOfferRepository.fetchByBeaconId(beaconId);
      final hasCommitters = activeOffers.any(
        (o) => isAcknowledgedCommitterResponse(coords[o.userId]),
      );
      if (hasCommitters) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.beaconNotClosable,
          description: 'Cannot cancel a request with committers',
        );
      }
      await _beaconRepository.recordBeaconStatusTransition(
        beaconId: beaconId,
        fromStatus: beacon.status,
        toStatus: BeaconStatus.cancelled,
        reason: BeaconLifecycleChangeReason.cancelled,
        actorId: userId,
      );
      return BeaconCloseReviewResult(
        id: beaconId,
        status: BeaconStatus.cancelled.smallintValue,
      );
    },
  );

  //
  Future<bool> deleteById({
    required String beaconId,
    required String userId,
  }) => _beaconRepository.runInBeaconStateTransaction(
    beaconId: beaconId,
    userId: userId,
    fn: (beacon) async {
      if (beacon.author.id != userId) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.notEligible,
        );
      }

      if (beacon.status == BeaconStatus.draft) {
        for (final image in beacon.images) {
          await _imageRepository.delete(
            authorId: beacon.author.id,
            imageId: image.id,
          );
        }
        await _beaconRepository.deleteBeaconById(beacon.id, userId: userId);
        return true;
      }

      final coords = await _coordinationRepository
          .coordinationResponseTypeByOfferUserId(beacon.id);
      final everHadAcknowledgedCommitter = coords.values.any(
        isAcknowledgedCommitterResponse,
      );
      if (everHadAcknowledgedCommitter) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.beaconNotClosable,
          description: 'Cannot delete a request that ever had a committer',
        );
      }

      final verdict = validateBeaconStatusTransition(
        from: beacon.status,
        to: BeaconStatus.deleted,
        reason: BeaconStatusTransitionReason.deleted,
      );
      if (verdict.verdict != BeaconStatusTransitionVerdict.allowed) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.beaconNotClosable,
        );
      }

      await _beaconRepository.recordBeaconStatusTransition(
        beaconId: beacon.id,
        fromStatus: beacon.status,
        toStatus: BeaconStatus.deleted,
        reason: BeaconLifecycleChangeReason.deleted,
        actorId: userId,
      );
      return true;
    },
  );
}
