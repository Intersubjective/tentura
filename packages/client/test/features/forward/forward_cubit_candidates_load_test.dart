import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

class _ControllableForwardRepository implements ForwardRepository {
  _ControllableForwardRepository({
    this.candidates = const [],
    this.failWith,
  });

  List<Profile> candidates;
  Object? failWith;
  int fetchForwardCandidatesCalls = 0;

  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  void emitForwardCompleted(String beaconId) => _forwardChanges.add(beaconId);

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async {
    fetchForwardCandidatesCalls++;
    if (failWith != null) {
      throw failWith!;
    }
    return candidates;
  }

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
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

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<
  ({
    ForwardCase forwardCase,
    _ControllableForwardRepository forwardRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({
  List<Profile> candidates = const [],
  Object? failWith,
}) async {
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final forwardRepo = _ControllableForwardRepository(
    candidates: candidates,
    failWith: failWith,
  );
  final forwardCase = ForwardCase(
    forwardRepo,
    authLocal,
    _FakeBeaconFactCardRepository(),
    _FakeProfileRepository(),
    contactsCase,
    ControllableBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
  contactsRepo.fetchMineHandler = () async => {};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('viewer');
  await syncReady;
  await Future<void>.delayed(Duration.zero);
  return (
    forwardCase: forwardCase,
    forwardRepo: forwardRepo,
    contactsCase: contactsCase,
    store: store,
  );
}

void main() {
  group('ForwardCubit candidatesLoad', () {
    test('first load transitions loading to ready', () async {
      final harness = await _buildHarness(
        candidates: const [
          Profile(id: 'u1', displayName: 'Alex', rScore: 1, score: 1),
        ],
      );
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        if (GetIt.I.isRegistered<ContactNameStore>()) {
          await GetIt.I.unregister<ContactNameStore>();
        }
        await harness.store.dispose();
      });

      final cubit = ForwardCubit(
        beaconId: 'b1',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      expect(cubit.state.candidatesLoad, isA<ForwardCandidatesLoading>());

      await cubit.stream.firstWhere(
        (s) => s.candidatesLoad is ForwardCandidatesReady,
      );
      expect(cubit.state.candidates.single.profile.displayName, 'Alex');
    });

    test('first load transitions loading to empty on genuine empty result',
        () async {
      final harness = await _buildHarness();
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        if (GetIt.I.isRegistered<ContactNameStore>()) {
          await GetIt.I.unregister<ContactNameStore>();
        }
        await harness.store.dispose();
      });

      final cubit = ForwardCubit(
        beaconId: 'b1',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere(
        (s) => s.candidatesLoad is ForwardCandidatesEmpty,
      );
      expect(cubit.state.candidates, isEmpty);
      expect(cubit.state.lineageSuggestions, isEmpty);
    });

    test('first load failure surfaces error and retry succeeds', () async {
      final harness = await _buildHarness(
        failWith: Exception('network down'),
      );
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        if (GetIt.I.isRegistered<ContactNameStore>()) {
          await GetIt.I.unregister<ContactNameStore>();
        }
        await harness.store.dispose();
      });

      final cubit = ForwardCubit(
        beaconId: 'b1',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere(
        (s) => s.candidatesLoad is ForwardCandidatesError,
      );
      expect(cubit.state.candidates, isEmpty);

      harness.forwardRepo.failWith = null;
      harness.forwardRepo.candidates = const [
        Profile(id: 'u1', displayName: 'Retry Alex', rScore: 1, score: 1),
      ];
      await cubit.retryLoadCandidates();

      expect(cubit.state.candidatesLoad, isA<ForwardCandidatesReady>());
      expect(cubit.state.candidates.single.profile.displayName, 'Retry Alex');
    });

    test(
      'background refresh failure keeps ready list and emits snackbar only',
      () async {
        final effects = FakeUiEffectPort();
        final harness = await _buildHarness(
          candidates: const [
            Profile(id: 'u1', displayName: 'Alex', rScore: 1, score: 1),
          ],
        );
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: effects,
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere(
          (s) => s.candidatesLoad is ForwardCandidatesReady,
        );
        final candidatesBefore = cubit.state.candidates;

        harness.forwardRepo.failWith = Exception('stale refresh failed');
        harness.forwardRepo.emitForwardCompleted('b1');
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.candidatesLoad, isA<ForwardCandidatesReady>());
        expect(cubit.state.candidates, candidatesBefore);
        expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      },
    );
  });
}
