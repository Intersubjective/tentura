import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';

void main() {
  AttentionReceipt receipt({
    required String destinationKind,
    required String targetEntityId,
    String? beaconId,
    String actionUrl = '/beacon/view/Bfallback',
  }) => AttentionReceipt(
    id: 'N1',
    category: 'coordination',
    kind: 'roomMessagePosted',
    priority: 'standard',
    title: 'Title',
    body: 'Body',
    actionUrl: actionUrl,
    createdAt: DateTime.utc(2026),
    collapsedCount: 1,
    presentationPayloadJson: '{}',
    beaconId: beaconId,
    destinationKind: destinationKind,
    targetEntityId: targetEntityId,
  );

  test('directed room target keeps message separate from item', () {
    final uri = attentionDestination(
      receipt(
        destinationKind: 'beacon_room_message',
        targetEntityId: 'M1',
        beaconId: 'B1',
      ),
    );

    expect(uri.path, '$kPathBeaconView/B1');
    expect(uri.queryParameters[kQueryBeaconViewTab], 'room');
    expect(uri.queryParameters[kQueryMessageId], 'M1');
    expect(uri.queryParameters.containsKey(kQueryCoordinationItemId), isFalse);
  });

  test('unknown destination retains the server action url', () {
    expect(
      attentionDestination(
        receipt(
          destinationKind: 'future_kind',
          targetEntityId: 'T1',
          actionUrl: '/profile/view/U1',
        ),
      ).toString(),
      '/profile/view/U1',
    );
  });
}
