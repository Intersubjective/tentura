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
import 'package:tentura/features/forward/domain/entity/person_forward_row.dart';
import 'package:tentura/features/forward/domain/use_case/person_forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeForwardRepository implements ForwardRepository {
  final _forwardChanges = StreamController<String>.broadcast();
  final involvementByBeaconId = <String, BeaconInvolvementData>{};
  final sent = <({String beaconId, List<String> recipientIds, String? note})>[];

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  void emitForwardCompleted(String beaconId) => _forwardChanges.add(beaconId);

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(
    Beacon beacon,
  ) async =>
      involvementByBeaconId[beacon.id] ??
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
    return 'edge-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _FakeBeaconRepository implements BeaconRepository {
  _FakeBeaconRepository(this.beacons);

  List<Beacon> beacons;
  int fetchCalls = 0;

  @override
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    required List<int> lifecycleStates,
    int limit = 5,
  }) async {
    fetchCalls++;
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
    PersonForwardCase case_,
    _FakeForwardRepository forwardRepo,
    _FakeBeaconRepository beaconRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({
  Profile person = const Profile(
    id: 'U-target',
    displayName: 'Target',
    rScore: 1,
  ),
  List<Beacon> beacons = const [],
  String myId = 'U-me',
}) async {
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final authLocal = StreamingAuthLocal(myId);
  final contactsRepo = FakeContactsRepository();
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    env: const Env(),
    logger: Logger('test'),
  );
  contactsRepo.fetchMineHandler = () async => {};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit(myId);
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  final forwardRepo = _FakeForwardRepository();
  final beaconRepo = _FakeBeaconRepository(beacons);
  final case_ = PersonForwardCase(
    forwardRepo,
    beaconRepo,
    _FakeProfileRepository({person.id: person}),
    authLocal,
    contactsCase,
    env: const Env(),
    logger: Logger('test'),
  );
  return (
    case_: case_,
    forwardRepo: forwardRepo,
    beaconRepo: beaconRepo,
    contactsCase: contactsCase,
    store: store,
  );
}

Beacon _beacon(String id, {BeaconStatus status = BeaconStatus.open}) =>
    Beacon.empty.copyWith(
      id: id,
      title: id,
      status: status,
      author: const Profile(id: 'U-me'),
    );

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<ContactNameStore>()) {
      await GetIt.I.unregister<ContactNameStore>();
    }
  });

  group('PersonForwardCubit', () {
    test('loads person-forward rows on initial load', () async {
      final harness = await _buildHarness(beacons: [_beacon('B-open')]);
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        await harness.store.dispose();
      });
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        personForwardCase: harness.case_,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.rows.isNotEmpty);

      expect(cubit.state.person?.id, 'U-target');
      expect(cubit.state.rows.single.beacon.id, 'B-open');
    });

    test(
      'send guards empty selection, ineligible row, and unreachable person',
      () async {
        final harness = await _buildHarness(
          person: const Profile(
            id: 'U-target',
            displayName: 'Target',
            rScore: 0,
          ),
          beacons: [_beacon('B-open')],
        );
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          await harness.store.dispose();
        });
        final cubit = PersonForwardCubit(
          personId: 'U-target',
          personForwardCase: harness.case_,
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        await cubit.stream.firstWhere((s) => s.rows.isNotEmpty);

        await cubit.send();
        cubit.selectBeacon('B-open');
        await cubit.send();
        cubit.emit(
          cubit.state.copyWith(
            person: const Profile(
              id: 'U-target',
              displayName: 'Target',
              rScore: 1,
            ),
            rows: [
              cubit.state.rows.single.copyWith(
                block: PersonForwardBlock.alreadySent,
              ),
            ],
          ),
        );
        await cubit.send();

        expect(harness.forwardRepo.sent, isEmpty);
      },
    );

    test('successful send shows confirmation and navigates back', () async {
      final harness = await _buildHarness(beacons: [_beacon('B-open')]);
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        await harness.store.dispose();
      });
      final effects = FakeUiEffectPort();
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        personForwardCase: harness.case_,
        effects: effects,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.rows.isNotEmpty);

      cubit.selectBeacon('B-open');
      cubit.setNote('please');
      await cubit.send();

      expect(harness.forwardRepo.sent.single.recipientIds, ['U-target']);
      expect(harness.forwardRepo.sent.single.note, 'please');
      expect(effects.emitted.whereType<ShowMessage>(), hasLength(1));
      expect(effects.emitted.whereType<NavigateBack>(), hasLength(1));
    });

    test('forwardChanges for a listed beacon reloads rows', () async {
      final harness = await _buildHarness(beacons: [_beacon('B-open')]);
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        await harness.store.dispose();
      });
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        personForwardCase: harness.case_,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.rows.isNotEmpty);
      expect(harness.beaconRepo.fetchCalls, 1);

      harness.forwardRepo.emitForwardCompleted('B-open');

      await cubit.stream.firstWhere(
        (s) => s.rows.isNotEmpty && harness.beaconRepo.fetchCalls == 2,
      );
      expect(harness.beaconRepo.fetchCalls, 2);
    });
  });
}
