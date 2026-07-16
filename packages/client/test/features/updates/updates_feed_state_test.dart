import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';

void main() {
  test(
    'updates state preserves active view, page items, and pagination hint',
    () {
      final receipt = AttentionReceipt(
        id: 'r1',
        category: 'asksOfMe',
        kind: 'needsMe',
        priority: 'normal',
        title: 'Need help',
        body: 'A request needs you.',
        actionUrl: '/#/',
        createdAt: DateTime.utc(2026),
        collapsedCount: 1,
        presentationPayloadJson: '{}',
      );
      final state = UpdatesFeedState(
        view: AttentionView.unread,
        items: [receipt],
        hasNextPage: true,
        status: const StateIsSuccess(),
      );

      expect(state.view, AttentionView.unread);
      expect(state.items, [receipt]);
      expect(state.hasNextPage, isTrue);
      expect(state.isEmpty, isFalse);
    },
  );
}
