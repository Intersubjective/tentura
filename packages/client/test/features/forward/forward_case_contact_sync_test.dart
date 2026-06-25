import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/data/repository/contacts_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

class _FakeForwardRepository implements ForwardRepository {
  _FakeForwardRepository({
    this.candidates = const [],
  });

  final List<Profile> candidates;
  int fetchForwardCandidatesCalls = 0;

  final _forwardCompleted = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardCompleted => _forwardCompleted.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) async {
    fetchForwardCandidatesCalls++;
    return candidates;
  }

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async =>
      (
        beacon: Beacon.empty.copyWith(id: beaconId),
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ForwardCase contact sync', () {
    late ContactNameStore store;

    setUp(() {
      store = ContactNameStore();
      GetIt.I.registerSingleton<ContactNameStore>(store);
    });

    tearDown(() async {
      if (GetIt.I.isRegistered<ContactNameStore>()) {
        await GetIt.I.unregister<ContactNameStore>();
      }
      await store.dispose();
    });

    test('applyContactOverlay uses ContactNameStore overlay', () {
      store.set('u-bob', 'Gym Bob');
      const candidate = ForwardCandidate(
        profile: Profile(id: 'u-bob', displayName: 'Robert'),
      );

      final patched = ForwardCase.applyContactOverlay(candidate);

      expect(patched.profile.shownName, 'Gym Bob');
    });

    test('profileWithContactOverlay matches applyContactOverlay', () {
      store.set('u-bob', 'Gym Bob');
      const profile = Profile(id: 'u-bob', displayName: 'Robert');

      expect(
        profileWithContactOverlay(profile).shownName,
        ForwardCase.applyContactOverlay(
          ForwardCandidate(profile: profile),
        ).profile.shownName,
      );
    });

    test('loadForwardCandidates refreshes contacts before fetch', () async {
      final authLocal = StreamingAuthLocal();
      final contactsRepo = FakeContactsRepository();
      final contactsCase = ContactsCase(
        contactsRepo,
        buildTestAuthCase(authLocal, EmptyAuthRemote()),
        store,
        env: const Env(),
        logger: Logger('test'),
      );
      final forwardRepo = _FakeForwardRepository(
        candidates: const [
          Profile(id: 'u-bob', displayName: 'Robert', rScore: 1, score: 1),
        ],
      );
      final forwardCase = ForwardCase(
        forwardRepo,
        authLocal,
        _FakeBeaconFactCardRepository(),
        _FakeProfileRepository(),
        contactsCase,
        env: const Env(),
        logger: Logger('test'),
      );

      var fetchMineCalls = 0;
      contactsRepo.fetchMineHandler = () async {
        fetchMineCalls++;
        return {'u-bob': 'Gym Bob'};
      };

      final syncReady = contactsRepo.nextSync();
      authLocal.emit('viewer');
      await syncReady;
      await Future<void>.delayed(Duration.zero);
      fetchMineCalls = 0;

      final load = await forwardCase.loadForwardCandidates(beaconId: 'b1');

      expect(fetchMineCalls, 1);
      expect(forwardRepo.fetchForwardCandidatesCalls, 1);
      expect(load.candidates.single.profile.shownName, 'Gym Bob');
      await contactsCase.dispose();
    });
  });
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
