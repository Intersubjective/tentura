import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _topLevelKeys = {
  'schemaVersion',
  'pendingProducerEventTypes',
  'eventTypes',
};

const _entryKeys = {
  'eventType',
  'producer',
  'recipientCategory',
  'destinationFamily',
  'muteability',
  'coveringTest',
};

const _pendingProducerEventTypes = <String>[];

const _expectedEventTypes = <Map<String, String>>[
  {
    'eventType': 'relayReceived',
    'producer': 'ForwardCase.forward',
    'recipientCategory': 'forward_recipients',
    'destinationFamily': 'beacon',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/use_case/forward_case_test.dart',
  },
  {
    'eventType': 'helpOfferSubmitted',
    'producer': 'HelpOfferCase.offerHelp',
    'recipientCategory': 'author_and_stewards',
    'destinationFamily': 'beacon_people_offer',
    'muteability': 'mandatory_or_standard',
    'coveringTest':
        'packages/server/test/domain/use_case/help_offer_case_test.dart',
  },
  {
    'eventType': 'offerAccepted',
    'producer': 'CoordinationCase.acceptHelpOffer',
    'recipientCategory': 'affected_helper',
    'destinationFamily': 'beacon_room',
    'muteability': 'mandatory',
    'coveringTest':
        'packages/server/test/domain/use_case/beacon_room_admission_matrix_test.dart',
  },
  {
    'eventType': 'offerDeclined',
    'producer': 'CoordinationCase.declineHelpOffer',
    'recipientCategory': 'affected_helper',
    'destinationFamily': 'beacon_people_or_safe_terminal',
    'muteability': 'mandatory',
    'coveringTest':
        'packages/server/test/domain/use_case/beacon_room_admission_matrix_test.dart',
  },
  {
    'eventType': 'offerRemoved',
    'producer': 'CoordinationCase.removeFromRoom',
    'recipientCategory': 'affected_helper',
    'destinationFamily': 'beacon_people_or_safe_terminal',
    'muteability': 'mandatory',
    'coveringTest':
        'packages/server/test/domain/use_case/beacon_room_admission_matrix_test.dart',
  },
  {
    'eventType': 'roomMessagePosted',
    'producer': 'BeaconRoomCase.createMessage',
    'recipientCategory': 'directed_chat_target',
    'destinationFamily': 'beacon_room_message',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/use_case/beacon_room_case_message_mutations_test.dart',
  },
  {
    'eventType': 'requestStatusChanged',
    'producer':
        'BeaconCase|CoordinationCase|EvaluationCase|AttentionExpirySweepCase',
    'recipientCategory': 'active_participants_and_inbox_stance_holders',
    'destinationFamily': 'beacon',
    'muteability': 'standard_or_noisy',
    'coveringTest':
        'packages/server/test/domain/use_case/coordination_case_revert_test.dart',
  },
  {
    'eventType': 'reviewOpened',
    'producer': 'EvaluationCase.beaconClose',
    'recipientCategory': 'admitted_participants',
    'destinationFamily': 'review',
    'muteability': 'mandatory',
    'coveringTest':
        'packages/server/test/domain/evaluation/evaluation_case_test.dart',
  },
  {
    'eventType': 'mutualConnectionFormed',
    'producer': 'UserTrustEdgeCase.setUserVote',
    'recipientCategory': 'reciprocal_counterpart',
    'destinationFamily': 'profile',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/use_case/user_trust_edge_case_test.dart',
  },
  {
    'eventType': 'inviteAccepted',
    'producer':
        'AuthCase.signUp(invite)|AuthCase.signUpWithInvite|CredentialAuthCase.resolveOrCreate(invite)|InvitationCase.accept|InvitationCase.acceptAsExisting(non-Beacon relationship-forming path)',
    'recipientCategory': 'inviter',
    'destinationFamily': 'profile',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/use_case/invitation_case_test.dart',
  },
];

void main() {
  test('Updates contract has the exact revision 4 semantic coverage', () {
    final contractFile = _contractFile();
    final contract = Map<String, dynamic>.from(
      jsonDecode(contractFile.readAsStringSync()) as Map,
    );

    expect(contract.keys.toSet(), _topLevelKeys);
    expect(contract['schemaVersion'], 1);

    final pending = (contract['pendingProducerEventTypes'] as List)
        .cast<String>();
    expect(pending, _pendingProducerEventTypes);

    final entries = (contract['eventTypes'] as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    expect(
      entries,
      _expectedEventTypes,
      reason: 'exact canonical six-field rows',
    );

    final names = entries.map((entry) => entry['eventType'] as String).toList();
    expect(names, isNot(contains('roomAdmissionChanged')));
    expect(names, containsAll(_pendingProducerEventTypes));

    final repositoryRoot = contractFile.parent.parent.parent;
    final serverTestRoot = Directory.fromUri(
      repositoryRoot.uri.resolve('packages/server/test/'),
    ).resolveSymbolicLinksSync();
    for (final entry in entries) {
      final eventType = entry['eventType'];
      expect(entry.keys.toSet(), _entryKeys, reason: '$eventType field shape');
      for (final key in _entryKeys) {
        expect(entry[key], isA<String>(), reason: '$eventType missing $key');
        expect(
          (entry[key] as String).trim(),
          isNotEmpty,
          reason: '$eventType has empty $key',
        );
      }

      final coveringTestPath = entry['coveringTest'] as String;
      expect(
        coveringTestPath,
        startsWith('packages/server/test/'),
        reason: '$eventType covering test declaration',
      );
      final coveringTest = File.fromUri(
        repositoryRoot.uri.resolve(coveringTestPath),
      );
      expect(
        coveringTest.existsSync(),
        isTrue,
        reason: '$eventType covering test does not exist: ${coveringTest.path}',
      );
      expect(
        coveringTest.resolveSymbolicLinksSync(),
        startsWith('$serverTestRoot${Platform.pathSeparator}'),
        reason: '$eventType covering test must stay under packages/server/test',
      );
    }

    final safeTerminalEvents = entries
        .where(
          (entry) =>
              entry['destinationFamily'] == 'beacon_people_or_safe_terminal',
        )
        .map((entry) => entry['eventType'])
        .toSet();
    expect(safeTerminalEvents, {'offerDeclined', 'offerRemoved'});
    expect(
      _pendingProducerEventTypes,
      isNot(contains('inviteAccepted')),
      reason: 'inviteAccepted already has live producers',
    );
  });
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/updates-event-contract.json',
    'docs/contracts/updates-event-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Updates event contract not found');
}
