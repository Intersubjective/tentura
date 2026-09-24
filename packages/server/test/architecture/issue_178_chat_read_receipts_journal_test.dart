import 'dart:io';

import 'package:test/test.dart';

void main() {
  final journal = File(
    '../../docs/plans/issue-178-chat-read-receipts-implementation-journal.md',
  );

  test(
    'issue-178 journal records P1.6 bridge_attention_room_seen index decision',
    () {
      expect(
        journal.existsSync(),
        isTrue,
        reason:
            'expected ${journal.path} documenting plan §P1.6 measure-then-decide',
      );

      final text = journal.readAsStringSync();
      expect(text, contains('P1.6'));
      expect(text, contains('bridge_attention_room_seen'));

      final documentsIndexDecision =
          text.contains('notification_outbox__room_message_unseen') ||
          RegExp(
            r'index (was )?not added',
            caseSensitive: false,
          ).hasMatch(text) ||
          RegExp(
            r'did not add (the |an )?index',
            caseSensitive: false,
          ).hasMatch(text) ||
          RegExp(
            r'existing index(es)? (suffice|sufficient)',
            caseSensitive: false,
          ).hasMatch(text);

      expect(
        documentsIndexDecision,
        isTrue,
        reason:
            'journal must state whether notification_outbox__room_message_unseen '
            'was added and why (plan §P1.6)',
      );
    },
  );
}
