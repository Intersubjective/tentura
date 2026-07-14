import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
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

/// Simulates route pop disposing the cubit when [NavigateBack] fires.
class _NavigateBackClosesCubitPort extends FakeUiEffectPort {
  _NavigateBackClosesCubitPort(this._cubitProvider);

  final ForwardCubit Function() _cubitProvider;

  @override
  void emit(UiEffect effect) {
    super.emit(effect);
    if (effect is NavigateBack) {
      unawaited(_cubitProvider().close());
    }
  }
}

class _LiveSyncForwardRepository implements ForwardRepository {
  _LiveSyncForwardRepository({
    this.candidates = const [],
  });

  final List<Profile> candidates;
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
  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
  }) async {
    if (!_forwardChanges.isClosed) {
      emitForwardCompleted(beaconId);
    }
    return 'edge-1';
  }

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
    _LiveSyncForwardRepository forwardRepo,
    ContactsCase contactsCase,
    FakeContactsRepository contactsRepo,
    ContactNameStore store,
  })
>
_buildForwardCaseHarness() async {
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    env: const Env(),
    logger: Logger('test'),
  );
  final forwardRepo = _LiveSyncForwardRepository(
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
  contactsRepo.fetchMineHandler = () async => {'u-bob': 'Gym Bob'};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('viewer');
  await syncReady;
  await Future<void>.delayed(Duration.zero);
  return (
    forwardCase: forwardCase,
    forwardRepo: forwardRepo,
    contactsCase: contactsCase,
    contactsRepo: contactsRepo,
    store: store,
  );
}

void main() {
  group('ForwardCubit live contact sync', () {
    test(
      'forwardChanges reloads candidates even when memo key unchanged',
      () async {
        final harness = await _buildForwardCaseHarness();
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

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        expect(cubit.state.candidates.single.profile.shownName, 'Gym Bob');
        expect(harness.forwardRepo.fetchForwardCandidatesCalls, 1);

        harness.contactsRepo.fetchMineHandler = () async => {
          'u-bob': 'Alias Bob',
        };
        harness.forwardRepo.emitForwardCompleted('b1');

        await cubit.stream.firstWhere(
          (s) => s.candidates.single.profile.shownName == 'Alias Bob',
        );
        expect(harness.forwardRepo.fetchForwardCandidatesCalls, 2);
      },
    );

    test(
      'contactChanges patches candidate names without full reload',
      () async {
        final harness = await _buildForwardCaseHarness();
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

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        final fetchCallsBefore =
            harness.forwardRepo.fetchForwardCandidatesCalls;

        await harness.contactsCase.rename(
          subjectId: 'u-bob',
          contactName: 'Renamed Bob',
        );

        await cubit.stream.firstWhere(
          (s) => s.candidates.single.profile.shownName == 'Renamed Bob',
        );
        expect(
          harness.forwardRepo.fetchForwardCandidatesCalls,
          fetchCallsBefore,
        );
      },
    );

    test(
      'forward navigates back without surfacing cubit-close errors',
      () async {
        final harness = await _buildForwardCaseHarness();
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        late ForwardCubit cubit;
        final effects = _NavigateBackClosesCubitPort(() => cubit);
        cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: effects,
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        cubit.emit(
          cubit.state.copyWith(
            selectedIds: {'u-bob'},
            beacon:
                cubit.state.beacon ??
                Beacon.empty.copyWith(id: 'b1', status: BeaconStatus.open),
          ),
        );

        await cubit.forward();

        expect(effects.emitted.whereType<NavigateBack>(), hasLength(1));
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
      },
    );
  });
}
