import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';

/// Which command was in flight when a save failed.
enum BeaconSavePhase { fields, stage, reconcile }

/// One request save: field values plus the complete desired media state.
class BeaconSaveCommand {
  const BeaconSaveCommand({
    required this.fields,
    required this.images,
    required this.coverKey,
    this.coverThumb,
    this.draft = false,
  });

  /// Field payload; carries `primaryNeedSlug` and `coverSource`.
  final Beacon fields;

  /// Desired attachments in display order; local entries carry `localKey`.
  final List<ImageEntity> images;

  /// [ImageEntity.key] of the selected cover, or null when there are none.
  final String? coverKey;

  /// Cropped card thumb; not part of [images].
  final ImageEntity? coverThumb;

  /// Create only: whether the new request starts as a server draft.
  final bool draft;

  BeaconCoverSource get coverSource => fields.coverSource;
}

class BeaconSaveResult {
  const BeaconSaveResult({
    required this.beacon,
    required this.images,
    this.coverThumb,
  });

  final Beacon beacon;

  /// Server-identified images in the order that was published.
  final List<ImageEntity> images;

  /// Published thumb after reconcile, when present.
  final ImageEntity? coverThumb;
}

/// Carries progressed state so a retry never re-creates or re-uploads work
/// that already succeeded.
class BeaconSaveFailure implements Exception {
  const BeaconSaveFailure({
    required this.cause,
    required this.phase,
    required this.beaconId,
    required this.images,
    required this.coverKey,
    this.coverThumb,
  });

  final Object cause;
  final BeaconSavePhase phase;

  /// Known server id once the field command succeeded.
  final String? beaconId;

  /// Image list with every already-staged entry carrying its server id.
  final List<ImageEntity> images;
  final String? coverKey;
  final ImageEntity? coverThumb;

  @override
  String toString() => 'BeaconSaveFailure(${phase.name}): $cause';
}

/// Owns every multi-repository step of creating or editing a request.
@singleton
class BeaconCreateCase {
  BeaconCreateCase(this._beacons, this._images);

  final BeaconWritePort _beacons;
  final BeaconImagePort _images;

  static const _uuid = Uuid();

  Future<Beacon> fetchById(String id) => _beacons.fetchBeaconById(id);

  Future<void> publishDraft(String id) => _beacons.publishDraft(id);

  Future<void> delete(String id) => _beacons.delete(id);

  /// Picks images and gives each one a stable client identity.
  Future<List<ImageEntity>> pickImages() async {
    final picked = await _images.pickMultipleImages();
    return [
      for (final image in picked)
        image.toImageEntity().copyWith(localKey: _uuid.v4()),
    ];
  }

  /// Re-crops [image] at 1:1. Returns null when the user cancels; throws when
  /// server bytes cannot be fetched.
  Future<ImageEntity?> adjustCoverCrop({
    required ImageEntity image,
    required String imageUrl,
    required ImageCropUiPort cropUi,
  }) async {
    final bytes = image.imageBytes ?? await _images.fetchImageBytes(imageUrl);
    final cropped = await cropUi.cropSquare(bytes);
    if (cropped == null) return null;
    return cropped.toImageEntity().copyWith(localKey: _uuid.v4());
  }

  Future<BeaconSaveResult> create(BeaconSaveCommand command) =>
      _save(command, _Save.create);

  Future<BeaconSaveResult> saveDraft(BeaconSaveCommand command) =>
      _save(command, _Save.draft);

  Future<BeaconSaveResult> saveEdit(BeaconSaveCommand command) =>
      _save(command, _Save.edit);

  Future<BeaconSaveResult> _save(BeaconSaveCommand command, _Save kind) async {
    final Beacon written;
    try {
      written = switch (kind) {
        _Save.create => await _beacons.create(
          command.fields,
          draft: command.draft,
        ),
        _Save.draft => await _beacons.updateDraft(command.fields),
        _Save.edit => await _beacons.update(command.fields),
      };
    } catch (e) {
      throw BeaconSaveFailure(
        cause: e,
        phase: BeaconSavePhase.fields,
        beaconId: kind == _Save.create ? null : command.fields.id,
        images: command.images,
        coverKey: command.coverKey,
        coverThumb: command.coverThumb,
      );
    }

    return _reconcile(
      beaconId: written.id,
      images: command.images,
      coverKey: command.coverKey,
      coverThumb: command.coverThumb,
      coverSource: command.coverSource,
    );
  }

  /// Stages every local image, then publishes media exactly once.
  Future<BeaconSaveResult> _reconcile({
    required String beaconId,
    required List<ImageEntity> images,
    required String? coverKey,
    required ImageEntity? coverThumb,
    required BeaconCoverSource coverSource,
    bool allowStageRecovery = true,
  }) async {
    final progressed = [...images];
    var cover = coverKey;

    for (var i = 0; i < progressed.length; i++) {
      final image = progressed[i];
      if (image.id.isNotEmpty) continue;
      final localKey = image.key;
      try {
        final serverId = await _beacons.stageImage(
          beaconId: beaconId,
          image: image,
        );
        progressed[i] = image.copyWith(id: serverId);
        if (cover == localKey) cover = serverId;
      } catch (e) {
        throw BeaconSaveFailure(
          cause: e,
          phase: BeaconSavePhase.stage,
          beaconId: beaconId,
          images: progressed,
          coverKey: cover,
          coverThumb: coverThumb,
        );
      }
    }

    var progressedThumb = coverThumb;
    if (progressedThumb != null && progressedThumb.id.isEmpty) {
      try {
        final thumbId = await _beacons.stageImage(
          beaconId: beaconId,
          image: progressedThumb,
        );
        progressedThumb = progressedThumb.copyWith(id: thumbId);
      } catch (e) {
        throw BeaconSaveFailure(
          cause: e,
          phase: BeaconSavePhase.stage,
          beaconId: beaconId,
          images: progressed,
          coverKey: cover,
          coverThumb: progressedThumb,
        );
      }
    }

    final imageIds = [for (final image in progressed) image.id];
    final coverImageId = imageIds.contains(cover) ? cover : null;

    try {
      final beacon = await _beacons.setMedia(
        beaconId: beaconId,
        imageIds: imageIds,
        coverImageId: imageIds.isEmpty ? null : coverImageId ?? imageIds.first,
        coverThumbImageId: progressedThumb?.id,
        coverSource: coverSource,
      );
      return BeaconSaveResult(
        beacon: beacon,
        images: progressed,
        coverThumb: progressedThumb,
      );
    } catch (e) {
      if (allowStageRecovery) {
        final recovered = await _recoverExpiredStages(
          beaconId: beaconId,
          progressed: progressed,
          original: images,
        );
        if (recovered != null) {
          final coverIndex = progressed.indexWhere((e) => e.key == cover);
          return _reconcile(
            beaconId: beaconId,
            images: recovered,
            coverKey: coverIndex < 0 ? cover : recovered[coverIndex].key,
            coverThumb: progressedThumb,
            coverSource: coverSource,
            allowStageRecovery: false,
          );
        }
      }
      throw BeaconSaveFailure(
        cause: e,
        phase: BeaconSavePhase.reconcile,
        beaconId: beaconId,
        images: progressed,
        coverKey: cover,
        coverThumb: progressedThumb,
      );
    }
  }

  /// A stage older than the server's window is gone, so its id is rejected.
  /// Only entries whose local bytes are still held can be re-staged; the id is
  /// never inferred from a position.
  Future<List<ImageEntity>?> _recoverExpiredStages({
    required String beaconId,
    required List<ImageEntity> progressed,
    required List<ImageEntity> original,
  }) async {
    final Beacon server;
    try {
      server = await _beacons.fetchBeaconById(beaconId);
    } catch (_) {
      return null;
    }

    final attached = {for (final image in server.images) image.id};

    var changed = false;
    final next = <ImageEntity>[];
    for (var i = 0; i < progressed.length; i++) {
      final image = progressed[i];
      if (attached.contains(image.id)) {
        next.add(image);
        continue;
      }
      // Position is only used to find this entry's own local source, never to
      // guess which server id belongs to it.
      final source = original[i];
      if (source.imageBytes == null) return null;
      next.add(source.copyWith(id: ''));
      changed = true;
    }
    return changed ? next : null;
  }
}

enum _Save { create, draft, edit }
