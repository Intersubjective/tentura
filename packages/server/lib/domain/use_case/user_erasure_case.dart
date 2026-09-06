import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
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
import 'package:tentura_server/env.dart';

import '_use_case_base.dart';

/// Account-erasure entry point consumed by [UserCase].
abstract interface class AccountErasureCase {
  Future<bool> deleteById({required String id});
}

/// Domain-owned account erasure transaction (§4.5 point 2).
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

    await _attention.runAction(
      actorUserId: id,
      action: (_) async {
        await _hierarchy.lockMutationScope();

        final ownedPublished = await _erasure.listOwnedPublishedBeacons(
          userId: id,
        );
        for (final owned in ownedPublished) {
          if (owned.status == BeaconStatus.deleted) {
            final scrubbed = await _erasure.scrubDeletedOwnedBeaconContent(
              beaconId: owned.beaconId,
              ownerId: id,
            );
            for (final imageId in scrubbed) {
              imageIdsForGc.add((imageId: imageId, authorId: id));
            }
            continue;
          }

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
              final scrubbed = await _erasure.scrubDeletedOwnedBeaconContent(
                beaconId: locked.id,
                ownerId: id,
              );
              for (final imageId in scrubbed) {
                imageIdsForGc.add((imageId: imageId, authorId: id));
              }
              return true;
            },
          );
        }

        final draftIds = await _erasure.listOwnedDraftBeaconIds(userId: id);
        for (final draftId in draftIds) {
          final scrubbed = await _erasure.hardDeleteOwnedDraftBeacon(
            beaconId: draftId,
            ownerId: id,
          );
          for (final imageId in scrubbed) {
            imageIdsForGc.add((imageId: imageId, authorId: id));
          }
        }

        await _erasure.deleteUserScopedEvaluationAndCapabilityRows(userId: id);
        final profileImages = await _erasure.deleteOwnedImageRows(userId: id);
        for (final imageId in profileImages) {
          imageIdsForGc.add((imageId: imageId, authorId: id));
        }

        await _erasure.deleteOrdinaryRoomMessagesAuthoredByUser(userId: id);

        await _users.deleteById(id: id);
      },
    );

    for (final pending in imageIdsForGc) {
      await _imageObjectGc.enqueue(
        imageId: pending.imageId,
        authorId: pending.authorId,
      );
    }

    return true;
  }
}
