import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_inbound_source.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _TrackingForwardRepository implements ForwardRepository {
  _TrackingForwardRepository({required this.beaconKind});

  final BeaconKind beaconKind;
  int fetchLineageForwardSuggestionsCalls = 0;
  int fetchInboundForwardSourcesCalls = 0;

  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => [
    const Profile(id: 'u1', displayName: 'User 1'),
  ];

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon.empty.copyWith(
      id: beaconId,
      kind: beaconKind,
      lineageParentBeaconId: 'parent_1',
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
  }) async {
    fetchLineageForwardSuggestionsCalls++;
    if (beaconKind == BeaconKind.post) {
      throw Exception('Operation is only available for Requests');
    }
    return const LineageForwardSuggestions(
      sourceBeaconId: '',
      rootBeaconId: '',
      suggestedNote: '',
      suggestions: [],
    );
  }

  @override
  Future<List<ForwardInboundSource>> fetchInboundForwardSources({
    required String beaconId,
  }) async {
    fetchInboundForwardSourcesCalls++;
    if (beaconKind == BeaconKind.post) {
      throw Exception('Operation is only available for Requests');
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _TrackingCapabilityRepository implements CapabilityRepositoryPort {
  int fetchForwardContextCalls = 0;

  @override
  Future<List<ForwardBandRow>> fetchForwardContext({
    required String beaconId,
    String? context,
  }) async {
    fetchForwardContextCalls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    _TrackingForwardRepository forwardRepo,
    _TrackingCapabilityRepository capRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({BeaconKind beaconKind = BeaconKind.request}) async {
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final capRepo = _TrackingCapabilityRepository();
  GetIt.I.registerSingleton<CapabilityRepositoryPort>(capRepo);

  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final forwardRepo = _TrackingForwardRepository(beaconKind: beaconKind);
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
    capRepo: capRepo,
    contactsCase: contactsCase,
    store: store,
  );
}

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<CapabilityRepositoryPort>()) {
      await GetIt.I.unregister<CapabilityRepositoryPort>();
    }
  });

  group('Post recipients flow skips Request-only calls', () {
    test('a Post creation flow (ForwardTargetProfile.post) skips Request-only reads', () async {
      final harness = await _buildHarness(beaconKind: BeaconKind.post);
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        if (GetIt.I.isRegistered<ContactNameStore>()) {
          await GetIt.I.unregister<ContactNameStore>();
        }
        await harness.store.dispose();
      });

      final cubit = ForwardCubit(
        beaconId: '',
        embedded: true,
        targetProfile: ForwardTargetProfile.post,
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere(
        (s) => s.candidatesLoad is ForwardCandidatesReady,
      );

      expect(harness.forwardRepo.fetchLineageForwardSuggestionsCalls, 0);
      expect(harness.capRepo.fetchForwardContextCalls, 0);

      final inbound = await cubit.fetchInboundSources();
      expect(inbound, isEmpty);
      expect(harness.forwardRepo.fetchInboundForwardSourcesCalls, 0);
    });

    test('a Post beacon flow (BeaconKind.post) skips Request-only reads', () async {
      final harness = await _buildHarness(beaconKind: BeaconKind.post);
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        if (GetIt.I.isRegistered<ContactNameStore>()) {
          await GetIt.I.unregister<ContactNameStore>();
        }
        await harness.store.dispose();
      });

      final cubit = ForwardCubit(
        beaconId: 'post_123',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere(
        (s) => s.candidatesLoad is ForwardCandidatesReady,
      );

      expect(harness.forwardRepo.fetchLineageForwardSuggestionsCalls, 0);
      expect(harness.capRepo.fetchForwardContextCalls, 0);

      final inbound = await cubit.fetchInboundSources();
      expect(inbound, isEmpty);
      expect(harness.forwardRepo.fetchInboundForwardSourcesCalls, 0);
    });

    test('control test: a Request Forward flow still makes Request-only reads', () async {
      final harness = await _buildHarness(beaconKind: BeaconKind.request);
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        if (GetIt.I.isRegistered<ContactNameStore>()) {
          await GetIt.I.unregister<ContactNameStore>();
        }
        await harness.store.dispose();
      });

      final cubit = ForwardCubit(
        beaconId: 'req_123',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere(
        (s) => s.candidatesLoad is ForwardCandidatesReady,
      );

      expect(harness.forwardRepo.fetchLineageForwardSuggestionsCalls, 1);
      expect(harness.capRepo.fetchForwardContextCalls, 1);

      await cubit.fetchInboundSources();
      expect(harness.forwardRepo.fetchInboundForwardSourcesCalls, 1);
    });
  });
}
