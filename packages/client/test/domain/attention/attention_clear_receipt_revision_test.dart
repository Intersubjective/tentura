import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/attention/attention_clear_store.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';

AttentionReceipt _receipt() => AttentionReceipt(
  id: 'receipt',
  category: 'coordination',
  kind: 'commitmentEvent',
  priority: 'normal',
  title: 'Your forward helped',
  body: '',
  actionUrl: '/#/view/request',
  createdAt: DateTime.utc(2026, 11, 11),
  collapsedCount: 1,
  presentationPayloadJson: '{"eventType":"forwardHelped"}',
  surface: AttentionSurface.activity,
);

void main() {
  test(
    'a committed dismiss hides its revision but permits the server Done upgrade',
    () {
      final accepted = _receipt();
      final store = AttentionClearStore()
        ..begin('dismiss', [accepted.id], receipts: [accepted])
        ..commit('dismiss', [accepted.id]);
      expect(store.apply(accepted).isCleared, isTrue);
      // Finalization changes the payload and un-clears the same row; it does
      // not replace the receipt id or its original createdAt/position.
      final done = accepted.copyWith(
        presentationPayloadJson: '{"eventType":"forwardHelped","done":true}',
      );
      expect(store.apply(done).isCleared, isFalse);
      expect(store.isOptimisticallyCleared(accepted.id), isFalse);
    },
  );

  test(
    'an event update cannot remove a dismiss still waiting for the server',
    () {
      final accepted = _receipt();
      final store = AttentionClearStore()
        ..begin('dismiss', [accepted.id], receipts: [accepted]);
      final done = accepted.copyWith(
        presentationPayloadJson: '{"eventType":"forwardHelped","done":true}',
      );
      expect(store.apply(done).isCleared, isTrue);
      store.discard('dismiss');
      expect(store.apply(done).isCleared, isFalse);
    },
  );

  test('an older read cannot undo a committed dismiss', () {
    final accepted = _receipt();
    final store = AttentionClearStore()
      ..begin('dismiss', [accepted.id], receipts: [accepted])
      ..commit('dismiss', [accepted.id]);
    final older = accepted.copyWith(
      createdAt: accepted.createdAt.subtract(const Duration(seconds: 1)),
      presentationPayloadJson: '{}',
    );
    expect(store.apply(older).isCleared, isTrue);
    expect(store.apply(accepted).isCleared, isTrue);
  });
}
