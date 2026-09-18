import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

const _topLevelKeys = {
  'schemaVersion',
  'pendingProducerEventTypes',
  'eventTypes',
  'producers',
  'eventClassifications',
};

const _classificationVariantKeys = {
  'recipientPredicate',
  'scope',
  'attentionClass',
  'placement',
  'groupKey',
  'orderingEffect',
  'accessPolicy',
  'recoverableVia',
  'clearPolicy',
  'producerTests',
  'transitionTests',
};

const _bumpingOrderingEffects = {'promote_on_obligation', 'bump'};

const _hierarchyPropagatedEventTypes = {'beaconHierarchyStatusChanged'};

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
    'eventType': 'commitmentReleased',
    'producer': 'CoordinationCase.releaseCommitment',
    'recipientCategory': 'affected_helper',
    'destinationFamily': 'beacon_people_or_safe_terminal',
    'muteability': 'mandatory',
    'coveringTest':
        'packages/server/test/domain/use_case/coordination_case_release_test.dart',
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
    'eventType': 'reviewAllPackagesIn',
    'producer': 'EvaluationCase.evaluationFinalize',
    'recipientCategory': 'beacon_author',
    'destinationFamily': 'review',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/evaluation/evaluation_case_test.dart',
  },
  {
    'eventType': 'reviewWindowCancelled',
    'producer': 'EvaluationCase.reopenFromReview',
    'recipientCategory': 'review_participant',
    'destinationFamily': 'beacon',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/evaluation/evaluation_case_test.dart',
  },
  {
    'eventType': 'mutualConnectionFormed',
    'producer':
        'UserTrustEdgeCase.setUserVote|AuthCase.signUp(invite)|AuthCase.signUpWithInvite|CredentialAuthCase.resolveOrCreate(invite)|InvitationCase.accept|InvitationCase.acceptAsExisting(non-Beacon relationship-forming path)',
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
  {
    'eventType': 'trustGivenChanged',
    'producer': 'EvaluationCase.closeNow|AttentionExpirySweepCase.runDue',
    'recipientCategory': 'review_participant',
    'destinationFamily': 'profile',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/evaluation/evaluation_case_test.dart',
  },
  {
    'eventType': 'trustReceivedChanged',
    'producer': 'EvaluationCase.closeNow|AttentionExpirySweepCase.runDue',
    'recipientCategory': 'review_participant',
    'destinationFamily': 'received_reviews',
    'muteability': 'standard',
    'coveringTest':
        'packages/server/test/domain/evaluation/evaluation_case_test.dart',
  },
];

void main() {
  test('Updates contract has the exact revision 4 semantic coverage', () {
    final contractFile = _contractFile();
    final contract = Map<String, dynamic>.from(
      jsonDecode(contractFile.readAsStringSync()) as Map,
    );

    expect(contract.keys.toSet(), _topLevelKeys);
    expect(contract['schemaVersion'], AttentionEventTypeCatalog.contractSchemaVersion);

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
    expect(safeTerminalEvents, {'offerDeclined', 'offerRemoved', 'commitmentReleased'});
    expect(
      _pendingProducerEventTypes,
      isNot(contains('inviteAccepted')),
      reason: 'inviteAccepted already has live producers',
    );
  });

  test('event classifications cover every AttentionEventType', () {
    final contract = _loadContract();
    final classifications = (contract['eventClassifications']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);

    final byType = {
      for (final entry in classifications)
        entry['eventType']! as String: entry,
    };

    expect(
      byType.keys.toSet(),
      AttentionEventType.values.map((event) => event.name).toSet(),
      reason: 'each runtime enum value must have exactly one classification row',
    );

    final unverifiedGaps = <String>[];
    for (final entry in classifications) {
      final eventType = entry['eventType']! as String;
      final status = entry['status']! as String;
      expect(
        AttentionEventCatalogStatus.values.map((s) => s.name),
        contains(status),
        reason: '$eventType status',
      );
      expect(status, isNot('retired'), reason: '$eventType is still live');

      final variants = (entry['variants']! as List)
          .map((variant) => Map<String, dynamic>.from(variant as Map))
          .toList(growable: false);
      expect(variants, isNotEmpty, reason: '$eventType needs variants');

      for (final variant in variants) {
        final allowedKeys = {..._classificationVariantKeys};
        if (variant['attentionClass'] == 'obligation') {
          allowedKeys.addAll({
            'actionDescriptor',
            'logicalTaskKey',
            'resolutionTransitions',
          });
        }
        if (variant['recoverableVia'] == 'none') {
          allowedKeys.add('retentionExemption');
        }
        expect(
          variant.keys,
          everyElement(isIn(allowedKeys)),
          reason: '$eventType variant field shape',
        );

        _collectUnverified(variant, '$eventType', unverifiedGaps);
        _enforceClassificationRules(eventType, variant);
      }
    }

    // Soft gate until U19: report gaps without failing the build.
    expect(
      unverifiedGaps,
      unverifiedGaps,
      reason:
          'unverified classification gaps (must reach zero before U19):\n'
          '${unverifiedGaps.join('\n')}',
    );
  });
}

Map<String, dynamic> _loadContract() => Map<String, dynamic>.from(
  jsonDecode(_contractFile().readAsStringSync()) as Map,
);

void _collectUnverified(
  Map<String, dynamic> variant,
  String prefix,
  List<String> gaps,
) {
  for (final key in variant.keys) {
    final value = variant[key];
    if (value == 'unverified') {
      gaps.add('$prefix.$key');
    } else if (value is List && value.contains('unverified')) {
      gaps.add('$prefix.$key');
    }
  }
}

void _enforceClassificationRules(
  String eventType,
  Map<String, dynamic> variant,
) {
  final attentionClass = variant['attentionClass']! as String;
  final orderingEffect = variant['orderingEffect']! as String;
  final placement = variant['placement']! as String;
  final recoverableVia = variant['recoverableVia']! as String;

  if (attentionClass == 'obligation') {
    expect(variant['actionDescriptor'], isA<String>());
    expect((variant['actionDescriptor'] as String).trim(), isNotEmpty);
    expect(variant['logicalTaskKey'], isA<String>());
    expect((variant['logicalTaskKey'] as String).trim(), isNotEmpty);
    final transitions = variant['resolutionTransitions']! as List;
    expect(transitions, isNotEmpty);
    expect(variant['clearPolicy'], 'forbidden');
  }

  if (attentionClass == 'optional') {
    expect(
      _bumpingOrderingEffects,
      isNot(contains(orderingEffect)),
      reason: '$eventType optional variant must not declare bump ordering',
    );
  }

  if (_hierarchyPropagatedEventTypes.contains(eventType)) {
    expect(
      placement,
      'timeline_only',
      reason: '$eventType is hierarchy-propagated',
    );
  }

  if (recoverableVia == 'none') {
    expect(
      variant['retentionExemption'],
      isA<String>(),
      reason: '$eventType recoverableVia none requires retentionExemption',
    );
    expect((variant['retentionExemption'] as String).trim(), isNotEmpty);
  }
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
