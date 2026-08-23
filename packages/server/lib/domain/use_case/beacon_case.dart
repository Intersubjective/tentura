import 'dart:async';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/utils/id.dart';

import '../entity/beacon_entity.dart';
import '../entity/gql_public/beacon_close_review_result.dart';
import '../entity/gql_public/beacon_image_added_result.dart';
import '../entity/gql_public/beacon_image_staged_result.dart';
import '../entity/task_entity.dart';
import '_use_case_base.dart';

const kMaxImagesPerBeacon = 10;

/// Stage rows older than this are eligible for the expiry sweep (§3.3).
const kBeaconStageExpiry = Duration(hours: 24);

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

/// Resolves the strict/compatibility `primaryNeedSlug` (N1-N3, §3.5).
///
/// When [primaryNeedSlugProvided] is false (legacy caller omitted the
/// argument), derives canonical-first from [needs]. Otherwise validates
/// strictly: an unknown slug throws [BeaconPrimaryNeedInvalidException]; a
/// non-null primary absent from [needs], or a null primary while [needs] is
/// non-empty, throws [BeaconPrimaryNeedNotInNeedsException].
String? _resolvePrimaryNeedSlug({
  required Set<String>? needs,
  required String? primaryNeedSlug,
  required bool primaryNeedSlugProvided,
}) {
  final needsSet = needs ?? const <String>{};
  if (!primaryNeedSlugProvided) {
    return canonicalFirstCapabilitySlug(needsSet);
  }
  if (primaryNeedSlug == null) {
    if (needsSet.isNotEmpty) {
      throw const BeaconPrimaryNeedNotInNeedsException();
    }
    return null;
  }
  if (!kAllowedCapabilitySlugs.contains(primaryNeedSlug)) {
    throw const BeaconPrimaryNeedInvalidException();
  }
  if (!needsSet.contains(primaryNeedSlug)) {
    throw const BeaconPrimaryNeedNotInNeedsException();
  }
  return primaryNeedSlug;
}

BeaconCoverSource _parseCoverSourceStrict(int wireValue) {
  for (final source in BeaconCoverSource.values) {
    if (source.wireValue == wireValue) return source;
  }
  throw const BeaconMediaInvalidException();
}

/// Resolves the thumb id to persist for [beaconSetMedia].
String? _resolveCoverThumbId({
  required BeaconEntity locked,
  required String? coverImageId,
  required bool thumbArgPresent,
  required String? thumbArgValue,
  required Set<String> stagedIds,
}) {
  final String? resolved;
  if (!thumbArgPresent) {
    if (coverImageId != locked.coverImageId) {
      resolved = null;
    } else {
      resolved = locked.coverThumbImageId;
    }
  } else {
    resolved = thumbArgValue;
  }

  if (resolved == null || resolved.isEmpty) {
    if (coverImageId == null && thumbArgPresent && thumbArgValue != null) {
      throw const BeaconMediaInvalidException();
    }
    return null;
  }

  if (coverImageId == null) {
    throw const BeaconMediaInvalidException();
  }

  for (final image in locked.images) {
    if (image.id == resolved) {
      throw const BeaconMediaInvalidException();
    }
  }

  final isCurrent = resolved == locked.coverThumbImageId;
  final isStaged = stagedIds.contains(resolved);
  if (!isCurrent && !isStaged) {
    throw const BeaconImageNotAttachedException();
  }

  if (coverImageId != locked.coverImageId &&
      resolved == locked.coverThumbImageId) {
    throw const BeaconMediaInvalidException();
  }

  return resolved;
}

@Singleton(order: 2)
final class BeaconCase extends UseCaseBase {
  @FactoryMethod(preResolve: true)
  static Future<BeaconCase> createInstance(
    Env env,
    Logger logger,
    BeaconRepositoryPort beaconRepository,
    ImageRepositoryPort imageRepository,
    ImageObjectGcPort imageObjectGc,
    TaskRepositoryPort tasksRepository,
    CommitmentQueryCase commitmentQueryCase,
    BeaconAccessGuard guard,
    AttentionIntentCase attentionIntents,
    TransactionalAttentionCase attention,
  ) async => BeaconCase(
    beaconRepository,
    imageRepository,
    imageObjectGc,
    tasksRepository,
    commitmentQueryCase,
    guard,
    attentionIntents: attentionIntents,
    attention: attention,
    env: env,
    logger: logger,
  );

  BeaconCase(
    this._beaconRepository,
    this._imageRepository,
    this._imageObjectGc,
    this._tasksRepository,
    this._commitmentQueryCase,
    this._guard, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final BeaconRepositoryPort _beaconRepository;

  final ImageRepositoryPort _imageRepository;

  final ImageObjectGcPort _imageObjectGc;

  final TaskRepositoryPort _tasksRepository;

  final CommitmentQueryCase _commitmentQueryCase;

  final BeaconAccessGuard _guard;

  final AttentionIntentCase? _attentionIntents;

  final TransactionalAttentionCase? _attention;

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

  Future<void> _scheduleHashTaskNonFatal(String imageId) async {
    try {
      await _tasksRepository.schedule(
        TaskEntity(details: TaskCalculateImageHashDetails(imageId: imageId)),
      );
    } catch (e, st) {
      logger.warning('failed to schedule hash task for image $imageId', e, st);
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
    String? primaryNeedSlug,
    bool primaryNeedSlugProvided = false,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    Stream<Uint8List>? imageBytes,
    bool draft = false,
    String? addressLabel,
  }) async {
    await _enforceCreateRateLimit(userId);
    final normalizedNeeds = _normalizeNeeds(needs);
    final resolvedPrimary = _resolvePrimaryNeedSlug(
      needs: normalizedNeeds,
      primaryNeedSlug: primaryNeedSlug,
      primaryNeedSlugProvided: primaryNeedSlugProvided,
    );
    final imageIds = <String>[];

    try {
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

      final desc = _normalizeBeaconDescription(description);
      return await _beaconRepository.createBeacon(
        authorId: userId,
        title: title,
        imageIds: imageIds.isEmpty ? null : imageIds,
        context: (context?.isEmpty ?? true) ? null : context,
        description: desc,
        latitude: coordinates?.lat,
        longitude: coordinates?.long,
        tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
        needs: normalizedNeeds,
        primaryNeedSlug: resolvedPrimary,
        startAt: startAt,
        endAt: endAt,
        status: draft ? BeaconStatus.draft : null,
        addressLabel: _trimOrNull(addressLabel),
      );
    } catch (_) {
      for (final imageId in imageIds) {
        await _imageRepository.compensateOrphanedUpload(
          imageId: imageId,
          authorId: userId,
        );
      }
      rethrow;
    }
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
    String? primaryNeedSlug,
    bool primaryNeedSlugProvided = false,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? addressLabel,
  }) async {
    final desc = _normalizeBeaconDescription(description);
    final normalizedNeeds = _normalizeNeeds(needs);
    final resolvedPrimary = _resolvePrimaryNeedSlug(
      needs: normalizedNeeds,
      primaryNeedSlug: primaryNeedSlug,
      primaryNeedSlugProvided: primaryNeedSlugProvided,
    );
    final beacon = await _beaconRepository.updateDraftBeacon(
      beaconId: beaconId,
      userId: userId,
      title: title,
      description: desc,
      context: context,
      tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
      needs: normalizedNeeds,
      primaryNeedSlug: resolvedPrimary,
      latitude: coordinates?.lat,
      longitude: coordinates?.long,
      startAt: startAt,
      endAt: endAt,
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
    String? primaryNeedSlug,
    bool primaryNeedSlugProvided = false,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? addressLabel,
  }) async {
    final desc = _normalizeBeaconDescription(description);
    final normalizedNeeds = _normalizeNeeds(needs);
    final resolvedPrimary = _resolvePrimaryNeedSlug(
      needs: normalizedNeeds,
      primaryNeedSlug: primaryNeedSlug,
      primaryNeedSlugProvided: primaryNeedSlugProvided,
    );
    // The repository locks before loading, and this enclosing transaction also
    // commits the occurrence/receipts/channel work.  Keeping comparison here
    // means the observed old value is the serialised value, not a stale read.
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final before = await _beaconRepository.getBeaconById(
          beaconId: beaconId,
          filterByUserId: userId,
        );
        final updated = await _beaconRepository.updateBeacon(
          beaconId: beaconId,
          userId: userId,
          title: title,
          description: desc,
          context: context,
          tags: (tags?.isEmpty ?? true) ? null : tags?.split(',').toSet(),
          needs: normalizedNeeds,
          primaryNeedSlug: resolvedPrimary,
          latitude: coordinates?.lat,
          longitude: coordinates?.long,
          startAt: startAt,
          endAt: endAt,
          addressLabel: _trimOrNull(addressLabel),
        );
        if (before.endAt != updated.endAt) {
          final recipients = await _commitmentQueryCase.currentCommitterUserIds(
            beaconId,
          );
          await transaction.record(
            await _attentionIntents!.deadlineChanged(
              beaconId: beaconId,
              actorUserId: userId,
              participantUserIds: recipients,
              oldEndAt: before.endAt,
              newEndAt: updated.endAt,
              sourceEventKey: 'deadline_changed:${generateId('A')}',
            ),
          );
        }
        return updated;
      },
    );
  }

  /// Legacy immediate-attach bridge (§3.3). Hardened: precheck owner before
  /// upload, re-authorize and cap-check under the beacon lock, and
  /// post-rollback compensation.
  Future<BeaconImageAddedResult> addImage({
    required String beaconId,
    required String userId,
    required Stream<Uint8List> imageBytes,
  }) async {
    await _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );

    final imageId = await _imageRepository.put(
      authorId: userId,
      bytes: imageBytes,
    );

    final BeaconEntity beacon;
    try {
      beacon = await _beaconRepository.runInBeaconStateTransaction(
        beaconId: beaconId,
        userId: userId,
        fn: (locked) async {
          if (locked.author.id != userId) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.notEligible,
            );
          }
          final snapshot = await _beaconRepository.getMediaSnapshot(beaconId);
          if (snapshot.combinedCount >= kMaxImagesPerBeacon) {
            throw const BeaconCreateException(
              description: 'Maximum images per request reached',
            );
          }
          await _beaconRepository.addImage(
            beaconId: beaconId,
            imageId: imageId,
            position: snapshot.attachedImageIds.length,
          );
          if (locked.coverImageId == null) {
            await _beaconRepository.setCover(
              beaconId: beaconId,
              coverImageId: imageId,
              coverSource: locked.coverSource,
            );
          }
          return _beaconRepository.getBeaconById(
            beaconId: beaconId,
            filterByUserId: userId,
          );
        },
      );
    } catch (_) {
      await _imageRepository.compensateOrphanedUpload(
        imageId: imageId,
        authorId: userId,
      );
      rethrow;
    }

    await _scheduleHashTaskNonFatal(imageId);

    return BeaconImageAddedResult(imageId: imageId, beacon: beacon);
  }

  /// Uploads an invisible stage image (§3.3). No reader of the beacon can see
  /// the stage until [beaconSetMedia] promotes it.
  Future<BeaconImageStagedResult> beaconStageImage({
    required String beaconId,
    required String userId,
    required Stream<Uint8List> imageBytes,
  }) async {
    await _beaconRepository.getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );

    final imageId = await _imageRepository.put(
      authorId: userId,
      bytes: imageBytes,
    );

    try {
      await _beaconRepository.runInBeaconStateTransaction(
        beaconId: beaconId,
        userId: userId,
        fn: (locked) async {
          if (locked.author.id != userId) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.notEligible,
            );
          }
          final snapshot = await _beaconRepository.getMediaSnapshot(beaconId);
          if (snapshot.combinedCount >= kMaxImagesPerBeacon) {
            throw const BeaconCreateException(
              description: 'Maximum images per request reached',
            );
          }
          final ownedIds = await _imageRepository.listOwnedIds(
            authorId: userId,
          );
          if (!ownedIds.contains(imageId)) {
            throw IdNotFoundException(id: imageId);
          }
          await _beaconRepository.insertStage(
            beaconId: beaconId,
            imageId: imageId,
          );
        },
      );
    } catch (_) {
      await _imageRepository.compensateOrphanedUpload(
        imageId: imageId,
        authorId: userId,
      );
      rethrow;
    }

    await _scheduleHashTaskNonFatal(imageId);

    return BeaconImageStagedResult(imageId: imageId, beaconId: beaconId);
  }

  /// Reconciles attached media to exactly [imageIds], promoting any staged
  /// ids, then sets the cover (§3.3). Strictly validated (§3.5).
  Future<BeaconEntity> beaconSetMedia({
    required String beaconId,
    required String userId,
    required List<String> imageIds,
    required int coverSource,
    String? coverImageId,
    String? coverThumbImageId,
    bool coverThumbImageIdPresent = false,
  }) => _beaconRepository.runInBeaconStateTransaction(
    beaconId: beaconId,
    userId: userId,
    fn: (locked) async {
      if (locked.author.id != userId) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.notEligible,
        );
      }

      final desired = imageIds.toSet();
      if (desired.length != imageIds.length ||
          imageIds.length > kMaxImagesPerBeacon) {
        throw const BeaconMediaInvalidException();
      }

      final resolvedCoverSource = _parseCoverSourceStrict(coverSource);

      final snapshot = await _beaconRepository.getMediaSnapshot(beaconId);
      final available = {
        ...snapshot.attachedImageIds,
        ...snapshot.stagedImageIds,
      };
      for (final id in desired) {
        if (!available.contains(id)) {
          throw const BeaconImageNotAttachedException();
        }
      }

      if (coverImageId == null) {
        if (imageIds.isNotEmpty) throw const BeaconMediaInvalidException();
      } else {
        if (imageIds.isEmpty) throw const BeaconMediaInvalidException();
        if (!desired.contains(coverImageId)) {
          throw const BeaconCoverNotAttachedException();
        }
      }

      final resolvedThumb = _resolveCoverThumbId(
        locked: locked,
        coverImageId: coverImageId,
        thumbArgPresent: coverThumbImageIdPresent,
        thumbArgValue: coverThumbImageId,
        stagedIds: snapshot.stagedImageIds,
      );

      final oldThumb = locked.coverThumbImageId;

      final removedIds = await _beaconRepository.replaceMedia(
        beaconId: beaconId,
        imageIds: imageIds,
        coverImageId: coverImageId,
        coverSource: resolvedCoverSource,
        coverThumbImageId: resolvedThumb,
      );
      for (final removedId in removedIds) {
        await _imageObjectGc.enqueue(imageId: removedId, authorId: userId);
        await _imageRepository.deleteOwnedRow(
          imageId: removedId,
          authorId: userId,
        );
      }
      if (oldThumb != null &&
          oldThumb.isNotEmpty &&
          oldThumb != resolvedThumb) {
        await _imageObjectGc.enqueue(imageId: oldThumb, authorId: userId);
        await _imageRepository.deleteOwnedRow(
          imageId: oldThumb,
          authorId: userId,
        );
      }

      return _beaconRepository.getBeaconById(
        beaconId: beaconId,
        filterByUserId: userId,
      );
    },
  );

  /// Retained and hardened for legacy clients; the new save path never calls
  /// this. Enqueues GC and deletes the actor-owned image row in the same
  /// transaction, and re-selects the lowest remaining cover when needed.
  Future<bool> removeImage({
    required String beaconId,
    required String imageId,
    required String userId,
  }) => _beaconRepository.runInBeaconStateTransaction(
    beaconId: beaconId,
    userId: userId,
    fn: (locked) async {
      if (locked.author.id != userId) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.notEligible,
        );
      }
      final attachedIds = [for (final image in locked.images) image.id];
      if (!attachedIds.contains(imageId)) {
        throw const BeaconImageNotAttachedException();
      }

      await _imageObjectGc.enqueue(imageId: imageId, authorId: userId);
      await _imageRepository.deleteOwnedRow(
        imageId: imageId,
        authorId: userId,
      );

      if (locked.coverImageId == imageId) {
        final remaining = attachedIds.where((id) => id != imageId);
        await _beaconRepository.setCover(
          beaconId: beaconId,
          coverImageId: remaining.isEmpty ? null : remaining.first,
          coverSource: locked.coverSource,
        );
      }

      return true;
    },
  );

  /// Retained and hardened for legacy clients; the new save path never calls
  /// this. Requires the supplied set to exactly equal the attached set.
  Future<bool> reorderImages({
    required String beaconId,
    required String userId,
    required List<String> imageIds,
  }) => _beaconRepository.runInBeaconStateTransaction(
    beaconId: beaconId,
    userId: userId,
    fn: (locked) async {
      if (locked.author.id != userId) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.notEligible,
        );
      }
      final attachedIds = {for (final image in locked.images) image.id};
      final desired = imageIds.toSet();
      if (desired.length != imageIds.length ||
          desired.length != attachedIds.length ||
          !attachedIds.containsAll(desired)) {
        throw const BeaconMediaInvalidException();
      }

      await _beaconRepository.reorderImages(
        beaconId: beaconId,
        imageIds: imageIds,
      );

      return true;
    },
  );

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
    String? mappedCoverImageId;
    try {
      if (source.author.id == userId && source.images.isNotEmpty) {
        for (final image in source.images) {
          final bytes = await _imageRepository.get(id: image.id);
          final newId = await _imageRepository.put(
            authorId: userId,
            bytes: Stream.value(bytes),
          );
          imageIds.add(newId);
          if (image.id == source.coverImageId) {
            mappedCoverImageId = newId;
          }
          await _tasksRepository.schedule(
            TaskEntity(
              details: TaskCalculateImageHashDetails(imageId: newId),
            ),
          );
        }
      }

      return await _beaconRepository.createBeacon(
        authorId: userId,
        title: source.title,
        description: source.description,
        context: source.context,
        latitude: source.coordinates?.lat,
        longitude: source.coordinates?.long,
        tags: source.tags,
        needs: source.needs,
        primaryNeedSlug: source.primaryNeedSlug,
        coverImageId: mappedCoverImageId,
        coverSource: source.coverSource,
        status: BeaconStatus.draft,
        imageIds: imageIds.isEmpty ? null : imageIds,
        lineageParentBeaconId: source.id,
        lineageRootBeaconId: source.lineageRootBeaconId ?? source.id,
      );
    } catch (_) {
      for (final imageId in imageIds) {
        await _imageRepository.compensateOrphanedUpload(
          imageId: imageId,
          authorId: userId,
        );
      }
      rethrow;
    }
  }

  /// Author cancels an open beacon with zero acknowledged committers (state 1).
  Future<BeaconCloseReviewResult> beaconCancel({
    required String beaconId,
    required String userId,
  }) {
    Future<BeaconCloseReviewResult> mutate(AttentionTransaction? transaction) =>
        _beaconRepository.runInBeaconStateTransaction(
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
            if (await _commitmentQueryCase.everHadCommitter(beaconId)) {
              throw EvaluationException(
                evaluationCode: EvaluationExceptionCode.beaconNotClosable,
                description:
                    'Cannot cancel a request that ever had a committer',
              );
            }
            final intent = transaction == null
                ? null
                : await _attentionIntents!.requestStatusChanged(
                    beaconId: beaconId,
                    fromStatus: beacon.status.name,
                    toStatus: BeaconStatus.cancelled.name,
                    actorUserId: userId,
                    sourceEventKey: 'request_status:${generateId('A')}',
                  );
            await _beaconRepository.recordBeaconStatusTransition(
              beaconId: beaconId,
              fromStatus: beacon.status,
              toStatus: BeaconStatus.cancelled,
              reason: BeaconLifecycleChangeReason.cancelled,
              actorId: userId,
            );
            if (intent != null) {
              await transaction!.record(intent);
            }
            return BeaconCloseReviewResult(
              id: beaconId,
              status: BeaconStatus.cancelled.smallintValue,
            );
          },
        );

    return _attention!.runAction(actorUserId: userId, action: mutate);
  }

  //
  Future<bool> deleteById({
    required String beaconId,
    required String userId,
  }) {
    Future<bool> mutate(
      AttentionTransaction? transaction,
    ) => _beaconRepository.runInBeaconStateTransaction(
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
            await _imageObjectGc.enqueue(
              imageId: image.id,
              authorId: beacon.author.id,
            );
            await _imageRepository.deleteOwnedRow(
              imageId: image.id,
              authorId: beacon.author.id,
            );
          }
          final thumbId = beacon.coverThumbImageId;
          if (thumbId != null && thumbId.isNotEmpty) {
            await _imageObjectGc.enqueue(
              imageId: thumbId,
              authorId: beacon.author.id,
            );
            await _imageRepository.deleteOwnedRow(
              imageId: thumbId,
              authorId: beacon.author.id,
            );
          }
          await _beaconRepository.deleteBeaconById(beacon.id, userId: userId);
          return true;
        }

        if (await _commitmentQueryCase.everHadCommitter(beacon.id)) {
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

        final intent = transaction == null
            ? null
            : await _attentionIntents!.requestStatusChanged(
                beaconId: beacon.id,
                fromStatus: beacon.status.name,
                toStatus: BeaconStatus.deleted.name,
                actorUserId: userId,
                sourceEventKey: 'request_status:${generateId('A')}',
              );
        await _beaconRepository.recordBeaconStatusTransition(
          beaconId: beacon.id,
          fromStatus: beacon.status,
          toStatus: BeaconStatus.deleted,
          reason: BeaconLifecycleChangeReason.deleted,
          actorId: userId,
        );
        if (intent != null) {
          await transaction!.record(intent);
        }
        return true;
      },
    );

    return _attention!.runAction(actorUserId: userId, action: mutate);
  }

  /// Stage-expiry sweep (§3.3): locks each candidate's beacon, rechecks age
  /// and presence, enqueues GC, and deletes the owned image row. Never
  /// expires an attachment.
  Future<int> expireStaleStages({
    required DateTime now,
    int limit = 100,
  }) async {
    final olderThan = now.subtract(kBeaconStageExpiry);
    final candidates = await _beaconRepository.staleStages(
      olderThan: olderThan,
      limit: limit,
    );
    var expired = 0;
    for (final stage in candidates) {
      final handled = await _beaconRepository.runInBeaconStateTransaction(
        beaconId: stage.beaconId,
        userId: stage.authorId,
        fn: (locked) async {
          final snapshot = await _beaconRepository.getMediaSnapshot(
            stage.beaconId,
          );
          if (!snapshot.stagedImageIds.contains(stage.imageId)) return false;
          await _beaconRepository.deleteStage(imageId: stage.imageId);
          await _imageObjectGc.enqueue(
            imageId: stage.imageId,
            authorId: stage.authorId,
          );
          await _imageRepository.deleteOwnedRow(
            imageId: stage.imageId,
            authorId: stage.authorId,
          );
          return true;
        },
      );
      if (handled) expired++;
    }
    return expired;
  }
}
