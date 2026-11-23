import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/user_erasure_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

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
    this._closureRepository,
  });

  // The injected case always has the lock. Direct test fixtures may omit it.
  @FactoryMethod()
  factory UserErasureCase.create(
    UserErasurePort erasure,
    BeaconRepositoryPort beacons,
    UserRepositoryPort users,
    BeaconHierarchyRepositoryPort hierarchy,
    BeaconLifecycleEffectsCase lifecycleEffects,
    TransactionalAttentionCase attention,
    ImageObjectGcPort imageObjectGc, {
    required ClosureRepositoryPort closureRepository,
    required Env env,
    required Logger logger,
  }) = UserErasureCase;

  final UserErasurePort _erasure;
  final BeaconRepositoryPort _beacons;
  final UserRepositoryPort _users;
  final BeaconHierarchyRepositoryPort _hierarchy;
  final BeaconLifecycleEffectsCase _lifecycleEffects;
  final TransactionalAttentionCase _attention;
  final ImageObjectGcPort _imageObjectGc;
  final ClosureRepositoryPort? _closureRepository;

  @override
  Future<bool> deleteById({required String id}) async {
    const batchSize = 200;
    final ownedPublished = await _erasure.listOwnedPublishedBeacons(userId: id);
    final draftIds = await _erasure.listOwnedDraftBeaconIds(userId: id);
    // Small accounts erase atomically; large ones commit in bounded chunks so
    // the DB lane is released between them.
    final atomic = ownedPublished.length + draftIds.length <= batchSize;
    Future<void> runStep(
      Future<void> Function() fn, {
      required bool retryOnConflict,
    }) {
      Future<void> run() =>
          _attention.runAction(actorUserId: id, action: (_) => fn());
      return retryOnConflict ? _attention.retryOnConflict(run) : run();
    }

    Future<void> step(
      Future<void> Function() fn, {
      bool retryOnConflict = false,
    }) => atomic ? fn() : runStep(fn, retryOnConflict: retryOnConflict);

    // Cleanup jobs are enqueued in the transaction that deleted the image rows.
    Future<void> enqueueGc(List<String> imageIds) async {
      for (final imageId in imageIds) {
        await _imageObjectGc.enqueue(imageId: imageId, authorId: id);
      }
    }

    Future<void> eraseActive(OwnedPublishedBeaconRow owned) async {
      await _hierarchy.lockMutationScope();
      // Match Cancel/Delete: serialize with invite acceptance before locking the row.
      await _closureRepository?.lockRequest(owned.beaconId);
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
          await enqueueGc(
            await _erasure.scrubDeletedOwnedBeaconContent(
              beaconId: locked.id,
              ownerId: id,
            ),
          );
          return true;
        },
      );
    }

    Future<void> scrubDeleted(List<String> beaconIds) async {
      for (var start = 0; start < beaconIds.length; start += batchSize) {
        await step(
          () async {
            await _hierarchy.lockMutationScope();
            await enqueueGc(
              await _erasure.scrubDeletedOwnedBeaconContents(
                beaconIds: beaconIds.skip(start).take(batchSize).toList(),
                ownerId: id,
              ),
            );
          },
        );
      }
    }

    Future<void> erase() async {
      // Active rows still require their individual locked lifecycle transition.
      // Each transition commits independently; already-deleted rows use bulk SQL.
      for (final owned in ownedPublished) {
        if (owned.status != BeaconStatus.deleted) {
          await step(() => eraseActive(owned));
        }
      }
      await scrubDeleted([
        for (final owned in ownedPublished)
          if (owned.status == BeaconStatus.deleted) owned.beaconId,
      ]);
      for (var start = 0; start < draftIds.length; start += batchSize) {
        await step(
          () async {
            await _hierarchy.lockMutationScope();
            await enqueueGc(
              await _erasure.hardDeleteOwnedDraftBeacons(
                beaconIds: draftIds.skip(start).take(batchSize).toList(),
                ownerId: id,
              ),
            );
          },
        );
      }
      // The final step re-lists under the lock so rows created after the
      // first listing are erased too.
      await step(
        () async {
          await _hierarchy.lockMutationScope();
          final handledDrafts = draftIds.toSet();
          await enqueueGc(
            await _erasure.hardDeleteOwnedDraftBeacons(
              beaconIds: [
                for (final draftId in await _erasure.listOwnedDraftBeaconIds(
                  userId: id,
                ))
                  if (!handledDrafts.contains(draftId)) draftId,
              ],
              ownerId: id,
            ),
          );
          // Rows already handled by this run's chunks are not re-scrubbed.
          final handled = {for (final owned in ownedPublished) owned.beaconId};
          final remaining = [
            for (final owned in await _erasure.listOwnedPublishedBeacons(
              userId: id,
            ))
              if (!handled.contains(owned.beaconId)) owned,
          ];
          for (final owned in remaining) {
            if (owned.status != BeaconStatus.deleted) await eraseActive(owned);
          }
          await enqueueGc(
            await _erasure.scrubDeletedOwnedBeaconContents(
              beaconIds: [for (final owned in remaining) owned.beaconId],
              ownerId: id,
            ),
          );
          await _erasure.deleteUserScopedEvaluationAndCapabilityRows(
            userId: id,
          );
          await enqueueGc(await _erasure.deleteOwnedImageRows(userId: id));
          await _erasure.deleteOrdinaryRoomMessagesAuthoredByUser(userId: id);
          await _users.deleteById(id: id);
        },
        retryOnConflict: true,
      );
    }

    if (atomic) {
      await runStep(erase, retryOnConflict: true);
    } else {
      await erase();
    }

    return true;
  }
}
