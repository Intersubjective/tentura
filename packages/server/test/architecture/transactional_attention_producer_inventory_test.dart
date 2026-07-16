import 'dart:io';

import 'package:test/test.dart';

void main() {
  const migratedProducers = <String, List<String>>{
    'auth_case.dart': ['runAction(', '.inviteAccepted('],
    'credential_auth_case.dart': ['runAction(', '.inviteAccepted('],
    'invitation_case.dart': ['runAction(', '.inviteAccepted('],
    'help_offer_case.dart': [
      'runAction<',
      '.helpOfferSubmitted(',
      '.offerAccepted(',
      '.helpWithdrawn(',
    ],
    'forward_case.dart': ['runAction(', '.relayReceived('],
    'coordination_case.dart': [
      'runAction(',
      '.offerAccepted(',
      '.offerDeclined(',
      '.offerRemoved(',
    ],
    'evaluation_case.dart': ['runAction(', '.reviewOpened('],
    'beacon_room_case.dart': [
      'runAction<',
      '.helpOfferSubmitted(',
      '.offerAccepted(',
    ],
    'coordination_item/create_promise_case.dart': [
      'runAction(',
      '.promiseChanged(',
    ],
    'coordination_item/publish_draft_promise_case.dart': [
      'runAction(',
      '.promiseChanged(',
    ],
    'coordination_item/cancel_promise_case.dart': [
      'runAction(',
      '.promiseChanged(',
    ],
    'coordination_item/mark_ask_case.dart': ['runAction(', '.needsMe('],
    'coordination_item/publish_draft_ask_case.dart': [
      'runAction(',
      '.needsMe(',
    ],
    'coordination_item/mark_blocker_case.dart': [
      'runAction(',
      '.blockerChanged(',
    ],
    'coordination_item/publish_draft_blocker_case.dart': [
      'runAction(',
      '.blockerChanged(',
    ],
    'coordination_item/resolve_blocker_case.dart': [
      'runAction(',
      '.blockerChanged(',
    ],
    'coordination_item/update_plan_case.dart': [
      'runAction(',
      '.coordinationChanged(',
    ],
    'coordination_item/remind_coordination_item_case.dart': [
      'runAction(',
      '.staleReminder(',
    ],
  };

  const legacyMethods = <String>[
    '.notifyBlockerOpened(',
    '.notifyBlockerResolved(',
    '.notifyForwardReceived(',
    '.notifyHelpOfferToAuthor(',
    '.notifyHelpOfferedToModerators(',
    '.notifyCommitmentDeclined(',
    '.notifyCommitmentRemoved(',
    '.notifyHelpWithdrawn(',
    '.notifyNeedsMe(',
    '.notifyPlanUpdatedToRoom(',
    '.notifyPromiseMade(',
    '.notifyReviewOpened(',
    '.notifyRoomAdmitted(',
    '.notifyStaleRemind(',
    '.notifyInviteAccepted(',
  ];

  const newProducerTokens = <String, List<String>>{
    'beacon_room_case.dart': [
      'attentionV1NewProducersEnabled',
      '.roomMessagePosted(',
    ],
    'beacon_case.dart': [
      'attentionV1NewProducersEnabled',
      '.requestStatusChanged(',
    ],
    'coordination_case.dart': [
      'attentionV1NewProducersEnabled',
      '.requestStatusChanged(',
    ],
    'evaluation_case.dart': [
      'attentionV1NewProducersEnabled',
      '.requestStatusChanged(',
    ],
    'attention_expiry_sweep_case.dart': [
      'actorUserId: null',
      '.requestStatusChanged(',
    ],
    'user_trust_edge_case.dart': [
      'attentionV1NewProducersEnabled',
      '.mutualConnectionFormed(',
    ],
  };

  test('every existing producer records through transactional attention', () {
    for (final entry in migratedProducers.entries) {
      final source = File(
        'lib/domain/use_case/${entry.key}',
      ).readAsStringSync();
      for (final requiredToken in entry.value) {
        expect(
          source,
          contains(requiredToken),
          reason: '${entry.key} must contain $requiredToken',
        );
      }
      expect(
        source,
        isNot(contains('unawaited(')),
        reason: '${entry.key} must not detach receipt creation',
      );
    }
  });

  test('legacy notification calls cannot re-enter domain use cases', () {
    final sources = Directory('lib/domain/use_case')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final source in sources) {
      final contents = source.readAsStringSync();
      for (final method in legacyMethods) {
        expect(
          contents,
          isNot(contains(method)),
          reason: '${source.path} still calls legacy $method',
        );
      }
    }
  });

  test('every T-05 producer is gated and records a typed intent', () {
    for (final entry in newProducerTokens.entries) {
      final source = File(
        'lib/domain/use_case/${entry.key}',
      ).readAsStringSync();
      for (final token in entry.value) {
        expect(source, contains(token), reason: '${entry.key} missing $token');
      }
      expect(source, isNot(contains('unawaited(')));
    }
  });

  test(
    'all interactive and time-driven status transition sites are covered',
    () {
      const expectedIntentSites = <String, int>{
        'beacon_case.dart': 2,
        'coordination_case.dart': 1,
        'evaluation_case.dart': 3,
        'attention_expiry_sweep_case.dart': 1,
      };

      for (final entry in expectedIntentSites.entries) {
        final source = File(
          'lib/domain/use_case/${entry.key}',
        ).readAsStringSync();
        expect(
          RegExp(r'\.requestStatusChanged\(').allMatches(source),
          hasLength(entry.value),
          reason: '${entry.key} status producer inventory drifted',
        );
      }

      final worker = File(
        'lib/domain/use_case/task_worker_case.dart',
      ).readAsStringSync();
      expect(worker, contains('_attentionExpirySweep!.runDue'));
    },
  );

  test('ContactCase remains deliberately non-producing', () {
    final source = File(
      'lib/domain/use_case/contact_case.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('AttentionIntentCase')));
    expect(source, isNot(contains('TransactionalAttentionCase')));
    expect(source, isNot(contains('NotificationPort')));
  });
}
