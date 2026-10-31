// Opening the forward screen from a tag lens passes the tag ids along; once
// the candidates have loaded the cubit selects the tags' eligible people, as
// if the tag chip had been tapped — once, so a later deselect sticks.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';

const _candidates = [
  Profile(id: 'ann', displayName: 'Ann', score: 1, rScore: 1),
  Profile(id: 'bob', displayName: 'Bob', score: 1, rScore: 1),
  Profile(id: 'cid', displayName: 'Cid', score: 1, rScore: 1),
];

const _neighbour = PersonTag(
  id: 'T-neighbour',
  name: 'Neighbour',
  glyph: 'N',
  color: 0,
  ord: 0,
);

class _ForwardRepository implements ForwardRepository {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _changes.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => _candidates;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon.empty.copyWith(
      id: beaconId,
      title: beaconId,
      author: const Profile(id: 'U-me'),
    ),
    forwardedToIds: <String>{},
    helpOfferedIds: <String>{},
    withdrawnIds: <String>{},
    declinedOfferIds: <String>{},
    rejectedIds: <String>{},
    watchingIds: <String>{},
    onwardForwarderIds: <String>{},
    myForwardedRecipientNotes: <String, String>{},
    myForwardedRecipientEdgeIds: <String, String>{},
    myForwardedRecipientReadAts: <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: <String, bool>{},
    myForwardedRecipientRejected: <String, bool>{},
  );

  @override
  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) async => const LineageForwardSuggestions(
    sourceBeaconId: '',
    rootBeaconId: '',
    suggestedNote: '',
    suggestions: [],
  );

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final profile in _candidates)
      if (ids.contains(profile.id)) profile,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FactCards implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ForwardCase> _forwardCase() async {
  final authLocal = StreamingAuthLocal('U-me');
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final realtime = buildTestRealtimeSync();
  final contacts = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  contactsRepo.fetchMineHandler = () async => {};
  final synced = contactsRepo.nextSync();
  authLocal.emit('U-me');
  await synced;
  await Future<void>.delayed(Duration.zero);
  final repository = _ForwardRepository();
  addTearDown(() async {
    await repository.dispose();
    await contacts.dispose();
    await realtime.port.dispose();
    if (GetIt.I.isRegistered<ContactNameStore>()) {
      await GetIt.I.unregister<ContactNameStore>();
    }
    await store.dispose();
  });
  return ForwardCase(
    repository,
    authLocal,
    _FactCards(),
    _Profiles(),
    contacts,
    noopBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
}

Future<void> _registerTags() async {
  final realtime = buildTestRealtimeSync();
  final tags = PeopleTagsCase(
    FakePeopleTagsRepository(
      tagList: const [_neighbour],
      memberList: const [
        PersonTagMembers(tagId: 'T-neighbour', personIds: ['ann', 'bob']),
      ],
    ),
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  await tags.load();
  GetIt.I.registerSingleton<PeopleTagsCase>(tags);
  addTearDown(() async {
    await GetIt.I.unregister<PeopleTagsCase>();
    await tags.dispose();
    await realtime.port.dispose();
  });
}

void main() {
  group('forward screen opened with tags from the tag lens', () {
    test(
      "selects the tags' eligible people once the candidates loaded",
      () async {
        final forwardCase = await _forwardCase();
        await _registerTags();

        final cubit = ForwardCubit(
          beaconId: 'B1',
          forwardCase: forwardCase,
          effects: FakeUiEffectPort(),
          initialTagIds: const {'T-neighbour'},
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.selectedIds.isNotEmpty);

        expect(cubit.state.selectedIds, {'ann', 'bob'});
        expect(cubit.state.addedByTag, {
          'T-neighbour': {'ann', 'bob'},
        });
      },
    );

    test('a later deselect sticks (the tags are applied only once)', () async {
      final forwardCase = await _forwardCase();
      await _registerTags();
      final cubit = ForwardCubit(
        beaconId: 'B1',
        forwardCase: forwardCase,
        effects: FakeUiEffectPort(),
        initialTagIds: const {'T-neighbour'},
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.selectedIds.isNotEmpty);

      cubit.toggleSelection('ann');
      await cubit.reloadCandidates();

      expect(cubit.state.selectedIds, {'bob'});
    });

    test('without tags nothing is preselected', () async {
      final forwardCase = await _forwardCase();
      await _registerTags();
      final cubit = ForwardCubit(
        beaconId: 'B1',
        forwardCase: forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);

      expect(cubit.state.selectedIds, isEmpty);
    });
  });
}
