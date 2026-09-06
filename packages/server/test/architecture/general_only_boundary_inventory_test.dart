import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final manifest = jsonDecode(
    File(
      '../../docs/plans/nested-requests-boundary-inventory.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;

  final entries = (manifest['entries'] as List)
      .cast<Map<String, dynamic>>();

  const task07Decisions = {
    'general-only-plus-lifecycle-guard',
    'general-only-thread-scope',
    'retire-public-field',
    'retain-audit-kind-gate',
    'general-plus-admission',
    'general-source-authorization',
    'resolve-message-general-access',
    'reject-ordinary-user-writes',
    'restrict-general-ownership',
    'retire-non-plan-reminders',
    'retire-responsibility-projection',
    'retire-or-plan-only',
    'no-non-general-snapshot',
  };

  final task07Entries = entries
      .where((e) => task07Decisions.contains(e['decision']))
      .toList();

  const retiredMutationNames = {
    'markBlocker',
    'resolveBlocker',
    'cancelBlocker',
    'markAsk',
    'createPromise',
    'createDraftPromise',
    'publishPromise',
    'updateDraftPromise',
    'deleteDraftPromise',
    'acceptPromise',
    'resolvePromise',
    'cancelPromise',
    'redirectPromise',
    'createDraftAsk',
    'publishAsk',
    'updateDraftAsk',
    'deleteDraftAsk',
    'createDraftBlocker',
    'publishBlocker',
    'updateDraftBlocker',
    'deleteDraftBlocker',
    'acceptAsk',
    'resolveAsk',
    'cancelAsk',
    'redirectAsk',
  };

  const exposedCoordinationMutations = {
    'updateCoordinationPlan',
    'addPlanStep',
    'resolvePlanStep',
    'updateCoordinationItem',
    'remindCoordinationItem',
    'markBeaconItemsSeen',
  };

  test('manifest Task 07 entries are non-empty', () {
    expect(task07Entries, isNotEmpty);
  });

  test('every retire-public-field manifest symbol is absent from schema', () {
    final retiredSymbols = task07Entries
        .where((e) => e['decision'] == 'retire-public-field')
        .map((e) => e['symbol'] as String)
        .toSet();
    expect(retiredSymbols, retiredMutationNames);
    expect(exposedCoordinationMutations.intersection(retiredSymbols), isEmpty);
  });

  test('retained coordination mutations remain registered', () {
    expect(exposedCoordinationMutations, {
      'updateCoordinationPlan',
      'addPlanStep',
      'resolvePlanStep',
      'updateCoordinationItem',
      'remindCoordinationItem',
      'markBeaconItemsSeen',
    });
  });

  test('negative matrix covers every Task 07 manifest entry symbol', () {
    final coveredSymbols = <String>{
      ...exposedCoordinationMutations,
      ...retiredMutationNames,
      'roomMessageCreate',
      'roomMessageAttachmentAdd',
      'roomMessageEdit',
      'roomMessageDelete',
      'roomMessageReactionToggle',
      'roomMessageMarkSemanticDone',
      'roomPollCreate',
      'markThreadSeen',
      'participantOfferHelp',
      'beaconRoomAdmit',
      'beaconStewardPromote',
      'roomMessageList',
      'roomMessageTarget',
      'beaconThreads',
      'beaconParticipantList',
      'beaconRoomStateGet',
      'beaconActivityEventList',
      'inboxRoomContextBatch',
      'myWorkLastActivityEvent',
      'download',
      'createMessage',
      'editMessage',
      'deleteMessage',
      'reactionToggle',
      'addMessageAttachment',
      'createPoll',
      'markThreadSeen',
      'listThreads',
      'listMessages',
      'roomMessageTarget',
      'roomMessageMarkSemanticDone',
      'markBeaconRoomSeen',
      'downloadAttachment',
      'create',
      'pollingAct',
      'lifecycleWriteGuard',
      '_canAccessThread',
      '_canMutateMessage',
      'beaconRoomStateGet',
      'beaconFactCardPin',
      'beaconFactCardCorrect',
      'beaconFactCardRemove',
      'beaconFactCardSetVisibility',
      'beaconFactCardList',
      'coordinationItemsByBeacon',
      'coordinationResponsibilityBatch',
      'coordinationMyResponsibilityItems',
      'myWorkCoordinationItemActivity',
      'call',
      'batch',
      'polling',
      'polling_act',
      'polling_variant',
      'beacon_room_state',
    };

    final missing = <String>[];
    for (final entry in task07Entries) {
      final symbol = entry['symbol'] as String;
      if (!coveredSymbols.contains(symbol)) {
        missing.add('${entry['path']}:$symbol');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Add coverage for manifest symbols: $missing',
    );
  });
}
