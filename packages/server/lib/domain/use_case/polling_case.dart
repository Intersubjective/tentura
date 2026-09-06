import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/discussion_product_policy_port.dart';
import 'package:tentura_server/domain/port/polling_act_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/policy/beacon_room_lifecycle_write_policy.dart';
import 'package:tentura_server/domain/exception.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class PollingCase extends UseCaseBase {
  PollingCase(
    this._pollingActRepository,
    this._pollingRepository,
    this._roomRepository,
    this._hierarchyRepository,
    this._discussionPolicy, {
    required super.env,
    required super.logger,
  });

  final PollingActRepositoryPort _pollingActRepository;
  final PollingRepositoryPort _pollingRepository;
  final BeaconRoomRepositoryPort _roomRepository;
  final BeaconHierarchyRepositoryPort _hierarchyRepository;
  final DiscussionProductPolicyPort _discussionPolicy;

  Future<bool> create({
    required String authorId,
    required String pollingId,
    required List<String> variantIds,
    int? score,
  }) async {
    final polling = await _pollingRepository.findById(pollingId);
    if (polling == null) throw ArgumentError('Poll not found: $pollingId');

    await _guardRoomBackedPollMutation(pollingId);

    final pollType = polling.pollType;

    if (score != null) {
      if (pollType != 'range') throw ArgumentError('score only valid for range polls');
      if (score < 0 || score > 5) throw ArgumentError('score must be 0–5');
    }
    if (pollType == 'single' && variantIds.length > 1) {
      throw ArgumentError('single polls accept exactly one variantId');
    }

    await _pollingActRepository.upsert(
      authorId: authorId,
      pollingId: pollingId,
      variantIds: variantIds,
      pollType: pollType,
      allowRevote: polling.allowRevote,
      score: score,
    );
    return true;
  }

  Future<void> _guardRoomBackedPollMutation(String pollingId) async {
    final message = await _roomRepository.getRoomMessageByLinkedPollingId(
      pollingId,
    );
    if (message == null) {
      return;
    }
    if (!_discussionPolicy.isDiscussionScopeEnabled(
      threadScopeId: message.threadItemId,
    )) {
      throw const DiscussionScopeDisabledException();
    }
    final status = await _hierarchyRepository.loadBeaconStatus(message.beaconId);
    if (status != null &&
        BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(status)) {
      throw const BeaconCreateException(
        description: 'Discussion is read-only for this request',
      );
    }
  }
}
