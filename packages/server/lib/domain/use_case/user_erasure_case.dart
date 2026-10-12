import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/user_erasure_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

/// Account-erasure entry point consumed by `UserCase`.
abstract interface class AccountErasureCase {
  Future<bool> deleteById({required String id});
}

/// Domain-owned account erasure in bounded transactions (§4.5 point 2).
@Singleton(as: AccountErasureCase, order: 2)
final class UserErasureCase extends UseCaseBase implements AccountErasureCase {
  UserErasureCase(
    this._erasure,
    this._beacons,
    this._users,
    this._hierarchy,
    this._lifecycleEffects,
    this._attention,
    this._imageObjectGc, {
    required super.env,
    required super.logger,
  });

  final UserErasurePort _erasure;
  final BeaconRepositoryPort _beacons;
  final UserRepositoryPort _users;
  final BeaconHierarchyRepositoryPort _hierarchy;
  final BeaconLifecycleEffectsCase _lifecycleEffects;
  final TransactionalAttentionCase _attention;
  final ImageObjectGcPort _imageObjectGc;

  @override
  Future<bool> deleteById({required String id}) async {
    final imageIdsForGc = <({String imageId, String authorId})>[];

    const batchSize = 200;
    final ownedPublished = await _erasure.listOwnedPublishedBeacons(userId: id);
    final draftIds = await _erasure.listOwnedDraftBeaconIds(userId: id);
    // Small accounts erase atomically; large ones commit in bounded chunks so
    // the DB lane is released between them.
    final atomic = ownedPublished.length + draftIds.length <= batchSize;
    Future<void> step(Future<void> Function() fn) => atomic
        ? fn()
        : _attention.runAction(actorUserId: id, action: (_) => fn());
    Future<void> erase() async {
      final deletedIds = <String>[];
      // Active rows still require their individual locked lifecycle transition.
      // Each transition commits independently; already-deleted rows use bulk SQL.
      for (final owned in ownedPublished) {
        if (owned.status == BeaconStatus.deleted) {
          deletedIds.add(owned.beaconId);
          continue;
        }
        await step(
          () async {
            await _hierarchy.lockMutationScope();
            await _beacons.runInBeaconStateTransaction(
              beaconId: owned.beaconId,
              userId: id,
              fn: (locked) async {
                await _lifecycleEffects.recordEligibleSourceTransition(
                  sourceBeaconId: locked.id,
                  fromStatus: locked.status,
                  toStatus: BeaconStatus.deleted,
                  occurredAt: DateTime.timestamp(),
                  actorUserId: id,
                  reason: BeaconStatusTransitionReason.deleted,
                );
                await _beacons.recordBeaconStatusTransition(
                  beaconId: locked.id,
                  fromStatus: locked.status,
                  toStatus: BeaconStatus.deleted,
                  reason: BeaconLifecycleChangeReason.deleted,
                  actorId: id,
                );
                final images = await _erasure.scrubDeletedOwnedBeaconContent(
                  beaconId: locked.id,
                  ownerId: id,
                );
                imageIdsForGc.addAll([
                  for (final imageId in images)
                    (imageId: imageId, authorId: id),
                ]);
                return true;
              },
            );
          },
        );
      }
      for (var start = 0; start < deletedIds.length; start += batchSize) {
        await step(
          () async {
            await _hierarchy.lockMutationScope();
            final images = await _erasure.scrubDeletedOwnedBeaconContents(
              beaconIds: deletedIds.skip(start).take(batchSize).toList(),
              ownerId: id,
            );
            imageIdsForGc.addAll([
              for (final imageId in images) (imageId: imageId, authorId: id),
            ]);
          },
        );
      }
      for (var start = 0; start < draftIds.length; start += batchSize) {
        await step(
          () async {
            await _hierarchy.lockMutationScope();
            final images = await _erasure.hardDeleteOwnedDraftBeacons(
              beaconIds: draftIds.skip(start).take(batchSize).toList(),
              ownerId: id,
            );
            imageIdsForGc.addAll([
              for (final imageId in images) (imageId: imageId, authorId: id),
            ]);
          },
        );
      }
      await step(
        () async {
          await _hierarchy.lockMutationScope();
          await _erasure.deleteUserScopedEvaluationAndCapabilityRows(
            userId: id,
          );
          final profileImages = await _erasure.deleteOwnedImageRows(userId: id);
          imageIdsForGc.addAll([
            for (final imageId in profileImages)
              (imageId: imageId, authorId: id),
          ]);
          await _erasure.deleteOrdinaryRoomMessagesAuthoredByUser(userId: id);
          await _users.deleteById(id: id);
        },
      );
    }

    if (atomic) {
      await _attention.runAction(actorUserId: id, action: (_) => erase());
    } else {
      await erase();
    }
    for (final pending in imageIdsForGc) {
      await _imageObjectGc.enqueue(
        imageId: pending.imageId,
        authorId: pending.authorId,
      );
    }

    return true;
  }
}
