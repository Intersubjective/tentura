import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ForwardCase extends UseCaseBase {
  ForwardCase(
    this._forwardEdgeRepository,
    this._commitmentRepository,
    this._inboxRepository, {
    required super.env,
    required super.logger,
  });

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final InboxRepositoryPort _inboxRepository;

  /// Forward a beacon to one or more recipients atomically.
  /// Returns the batch_id used for this forward action.
  Future<String> forward({
    required String senderId,
    required String beaconId,
    required List<String> recipientIds,
    String? context,
    String? parentEdgeId,
    String sharedNote = '',
    Map<String, String>? perRecipientNotes,
  }) async {
    if (recipientIds.isEmpty) {
      throw ArgumentError('recipientIds must not be empty');
    }

    final batchId = generateId('X');

    await _forwardEdgeRepository.createBatch(
      beaconId: beaconId,
      senderId: senderId,
      recipientIds: recipientIds,
      batchId: batchId,
      noteForRecipient: (id) => perRecipientNotes?[id] ?? sharedNote,
      context: context,
      parentEdgeId: parentEdgeId,
      onAfterEdgesInserted: () async {
        final hasCommit = await _commitmentRepository.hasActiveCommitment(
          beaconId: beaconId,
          userId: senderId,
        );
        if (hasCommit) return;
        await _inboxRepository.upsertWatchingForSender(
          senderId: senderId,
          beaconId: beaconId,
          context: context,
        );
      },
    );

    return batchId;
  }
}
