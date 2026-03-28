import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/utils/id.dart';

@Singleton(order: 2)
class ForwardCase {
  const ForwardCase(this._forwardEdgeRepository);

  final ForwardEdgeRepository _forwardEdgeRepository;

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
    );

    return batchId;
  }
}
