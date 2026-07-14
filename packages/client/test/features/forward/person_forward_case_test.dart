import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/person_forward_row.dart';
import 'package:tentura/features/forward/domain/use_case/person_forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/test_realtime_sync.dart';

class _FakeForwardRepository implements ForwardRepository {
  final _forwardChanges = StreamController<String>.broadcast();
  final involvementByBeaconId = <String, BeaconInvolvementData>{};
  final involvementFailures = <String>{};
  final sent = <({String beaconId, List<String> recipientIds, String? note})>[];

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(Beacon beacon) async {
    if (involvementFailures.contains(beacon.id)) {
      throw StateError('boom ${beacon.id}');
    }
    return involvementByBeaconId[beacon.id] ??
        (
          beacon: beacon,
          forwardedToIds: <String>{},
          helpOfferedIds: <String>{},
          withdrawnIds: <String>{},
          rejectedIds: <String>{},
          watchingIds: <String>{},
          onwardForwarderIds: <String>{},
          myForwardedRecipientNotes: <String, String>{},
          myForwardedRecipientEdgeIds: <String, String>{},
          myForwardedRecipientReadAts: <String, DateTime?>{},
        );
  }

  @override
  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
  }) async {
    sent.add((beaconId: beaconId, recipientIds: recipientIds, note: note));
    _forwardChanges.add(beaconId);
    return 'edge-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _FakeBeaconRepository implements BeaconRepository {
  _FakeBeaconRepository(this.beacons);

  final List<Beacon> beacons;
  ({String profileId, int offset, List<int> lifecycleStates, int limit})?
  lastFetch;

  @override
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    required List<int> lifecycleStates,
    int limit = 5,
  }) async {
    lastFetch = (
      profileId: profileId,
      offset: offset,
      lifecycleStates: lifecycleStates,
      limit: limit,
    );
    return beacons;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  _FakeProfileRepository(this.profiles);

  final Map<String, Profile> profiles;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (profiles[id] != null) profiles[id]!,
  ];

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<
  ({
    PersonForwardCase personForwardCase,
    _FakeForwardRepository forwardRepo,
    _FakeBeaconRepository beaconRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({
  Profile person = const Profile(
    id: 'U-target',
    displayName: 'Raw Target',
    rScore: 1,
  ),
  List<Beacon> beacons = const [],
  String myId = 'U-me',
}) async {
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final authLocal = StreamingAuthLocal(myId);
  final contactsRepo = FakeContactsRepository();
  contactsRepo.fetchMineHandler = () async => {'U-target': 'Contact Target'};
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final syncReady = contactsRepo.nextSync();
  authLocal.emit(myId);
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  final forwardRepo = _FakeForwardRepository();
  final beaconRepo = _FakeBeaconRepository(beacons);
  final personForwardCase = PersonForwardCase(
    forwardRepo,
    beaconRepo,
    _FakeProfileRepository({person.id: person}),
    authLocal,
    contactsCase,
    env: const Env(),
    logger: Logger('test'),
  );
  return (
    personForwardCase: personForwardCase,
    forwardRepo: forwardRepo,
    beaconRepo: beaconRepo,
    contactsCase: contactsCase,
    store: store,
  );
}

Beacon _beacon(
  String id, {
  BeaconStatus status = BeaconStatus.open,
  String authorId = 'U-me',
}) => Beacon.empty.copyWith(
  id: id,
  title: id,
  status: status,
  author: Profile(id: authorId),
);

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<ContactNameStore>()) {
      await GetIt.I.unregister<ContactNameStore>();
    }
  });

  group('PersonForwardCase.load', () {
    test(
      'loads overlayed person and authored open-family request rows',
      () async {
        final harness = await _buildHarness(
          beacons: [
            _beacon('B-sent'),
            _beacon('B-open'),
            _beacon('B-review', status: BeaconStatus.reviewOpen),
          ],
        );
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          await harness.store.dispose();
        });
        harness.forwardRepo.involvementByBeaconId['B-sent'] = (
          beacon: _beacon('B-sent'),
          forwardedToIds: <String>{},
          helpOfferedIds: <String>{},
          withdrawnIds: <String>{},
          rejectedIds: <String>{},
          watchingIds: <String>{},
          onwardForwarderIds: <String>{},
          myForwardedRecipientNotes: <String, String>{'U-target': 'sent'},
          myForwardedRecipientEdgeIds: <String, String>{'U-target': 'edge-1'},
          myForwardedRecipientReadAts: <String, DateTime?>{},
        );

        final load = await harness.personForwardCase.load('U-target');

        expect(load.person.shownName, 'Contact Target');
        expect(harness.beaconRepo.lastFetch?.profileId, 'U-me');
        expect(harness.beaconRepo.lastFetch?.offset, 0);
        expect(harness.beaconRepo.lastFetch?.limit, 50);
        expect(
          harness.beaconRepo.lastFetch?.lifecycleStates.toSet(),
          BeaconStatus.openFamilyValues,
        );
        expect(load.rows.map((r) => r.beacon.id), [
          'B-open',
          'B-sent',
          'B-review',
        ]);
        expect(load.rows[0].block, PersonForwardBlock.none);
        expect(load.rows[1].block, PersonForwardBlock.alreadySent);
        expect(load.rows[2].block, PersonForwardBlock.notOpen);
      },
    );

    test('degrades failed involvement fetch to eligible unseen row', () async {
      final harness = await _buildHarness(beacons: [_beacon('B-flaky')]);
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        await harness.store.dispose();
      });
      harness.forwardRepo.involvementFailures.add('B-flaky');

      final load = await harness.personForwardCase.load('U-target');

      expect(load.rows.single.involvement, CandidateInvolvement.unseen);
      expect(load.rows.single.block, PersonForwardBlock.none);
      expect(load.rows.single.isEligible, isTrue);
    });

    test('send forwards one selected request with trimmed note', () async {
      final harness = await _buildHarness();
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        await harness.store.dispose();
      });

      await harness.personForwardCase.send(
        beaconId: 'B-open',
        personId: 'U-target',
        note: '  please help  ',
      );

      expect(harness.forwardRepo.sent.single.beaconId, 'B-open');
      expect(harness.forwardRepo.sent.single.recipientIds, ['U-target']);
      expect(harness.forwardRepo.sent.single.note, 'please help');
    });
  });
}
