import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Maps each contract `impacts` label to at least one client projection that
/// subscribes to invalidation for wire kinds declaring that impact.
///
/// Keep this table aligned with `docs/realtime-sync-operations.md` and the U7
/// journal surface traces. Adding an impact without a subscriber must fail here
/// or be recorded as an intentional contract-only label in the journal.
const impactSubscribers = <String, List<String>>{
  'avatars': [
    'packages/client/lib/features/profile/ui/bloc/profile_cubit.dart',
  ],
  'chat': [
    'packages/client/lib/features/beacon_room/ui/bloc/room_cubit.dart',
  ],
  'chat_access': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'chat_poll_results': [
    'packages/client/lib/features/beacon_room/ui/bloc/room_cubit.dart',
  ],
  'chat_reactions': [
    'packages/client/lib/features/beacon_room/ui/bloc/room_cubit.dart',
  ],
  'chat_thread': [
    'packages/client/lib/features/beacon_room/ui/bloc/room_cubit.dart',
  ],
  'chat_watermark': [
    'packages/client/lib/features/beacon_room/domain/use_case/beacon_room_case.dart',
  ],
  'contact_name_overlays': [
    'packages/client/lib/features/contacts/domain/use_case/contacts_case.dart',
  ],
  'forward_candidates': [
    'packages/client/lib/features/forward/ui/bloc/forward_cubit.dart',
  ],
  'forward_graph': [
    'packages/client/lib/features/forward/data/repository/forward_repository.dart',
    'packages/client/lib/features/graph/ui/bloc/graph_cubit.dart',
  ],
  'forward_picker': [
    'packages/client/lib/features/forward/ui/bloc/person_forward_cubit.dart',
  ],
  'friends': [
    'packages/client/lib/features/friends/domain/use_case/friends_case.dart',
  ],
  'inbox': [
    'packages/client/lib/features/inbox/ui/bloc/inbox_cubit.dart',
  ],
  'inbox_unread': [
    'packages/client/lib/features/inbox/domain/use_case/inbox_case.dart',
  ],
  'items': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'my_work': [
    'packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart',
  ],
  'my_work_last_activity': [
    'packages/client/lib/features/my_work/domain/use_case/my_work_case.dart',
  ],
  'my_work_unread': [
    'packages/client/lib/features/my_work/domain/use_case/my_work_case.dart',
  ],
  'people': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'people_capability_cues': [
    'packages/client/lib/features/friends/domain/use_case/friends_case.dart',
  ],
  'people_visibility': [
    'packages/client/lib/features/friends/domain/use_case/friends_case.dart',
  ],
  'presence': [
    'packages/client/lib/features/beacon_room/ui/bloc/room_cubit.dart',
    'packages/client/lib/features/friends/domain/use_case/friends_case.dart',
  ],
  'profile': [
    'packages/client/lib/features/profile/ui/bloc/profile_cubit.dart',
    'packages/client/lib/features/profile_view/domain/use_case/profile_view_case.dart',
  ],
  'profile_controls': [
    'packages/client/lib/features/profile_view/domain/use_case/profile_view_case.dart',
  ],
  'profile_requests': [
    'packages/client/lib/features/profile_view/domain/use_case/profile_shared_beacons_case.dart',
  ],
  'request_activity': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'request_detail': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'request_detail_context': [
    'packages/client/lib/features/inbox/domain/use_case/inbox_case.dart',
  ],
  'request_people': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'request_timeline': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'shell_counters': [
    'packages/client/lib/features/home/ui/bloc/home_attention_cubit.dart',
    'packages/client/lib/features/home/ui/widget/updates_navbar_item.dart',
    'packages/client/lib/features/home/ui/widget/inbox_navbar_item.dart',
  ],
  'unread': [
    'packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
  ],
  'updates_badge': [
    'packages/client/lib/domain/attention/attention_case.dart',
    'packages/client/lib/features/home/ui/widget/updates_navbar_item.dart',
  ],
  'updates_feed': [
    'packages/client/lib/domain/attention/attention_case.dart',
    'packages/client/lib/features/updates/ui/bloc/updates_feed_cubit.dart',
  ],
};

void main() {
  test('every declared contract impact maps to a client subscriber', () {
    final contractFile = _contractFile();
    final contract = jsonDecode(contractFile.readAsStringSync()) as Map;
    final entries = (contract['kinds']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    final repoRoot = contractFile.parent.parent.parent;

    final declaredImpacts = <String>{};
    for (final entry in entries) {
      declaredImpacts.addAll((entry['impacts']! as List).cast<String>());
    }

    expect(declaredImpacts, isNotEmpty);

    final unmapped = <String>[];
    for (final impact in declaredImpacts) {
      final subscribers = impactSubscribers[impact];
      if (subscribers == null || subscribers.isEmpty) {
        unmapped.add(impact);
        continue;
      }
      for (final path in subscribers) {
        expect(
          File.fromUri(repoRoot.uri.resolve(path)).existsSync(),
          isTrue,
          reason: 'impact $impact subscriber missing: $path',
        );
      }
    }

    expect(
      unmapped,
      isEmpty,
      reason: 'Add impactSubscribers entries for: $unmapped',
    );

    final orphanMappings = impactSubscribers.keys.toSet().difference(
      declaredImpacts,
    );
    expect(
      orphanMappings,
      isEmpty,
      reason: 'Remove stale impactSubscribers keys: $orphanMappings',
    );
  });

  test('coordination_item impacts cover the four #102 surfaces', () {
    final contract = jsonDecode(_contractFile().readAsStringSync()) as Map;
    final coordination = (contract['kinds']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .singleWhere((entry) => entry['wireKind'] == 'coordination_item');
    final impacts = (coordination['impacts']! as List).cast<String>();

    expect(
      impacts,
      containsAll(const [
        'request_detail',
        'my_work',
        'items',
      ]),
    );

    final notification = (contract['kinds']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .singleWhere((entry) => entry['wireKind'] == 'notification');
    expect(
      (notification['impacts']! as List).cast<String>(),
      containsAll(const ['updates_feed', 'updates_badge']),
    );
  });
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Realtime entity contract manifest not found');
}
