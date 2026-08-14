import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _EditReasonsForwardRepository implements ForwardRepository {
  _EditReasonsForwardRepository({
    required this.involvement,
    this.candidates = const [],
  });

  final List<Profile> candidates;
  final BeaconInvolvementData involvement;

  List<String>? lastUpdateReasonSlugs;
  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async =>
      candidates;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async =>
      involvement;

  @override
  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) async =>
      const LineageForwardSuggestions(
        sourceBeaconId: '',
        rootBeaconId: '',
        suggestedNote: '',
        suggestions: [],
      );

  @override
  Future<bool> updateForward({
    required String edgeId,
    String? note,
    List<String>? reasonSlugs,
  }) async {
    lastUpdateReasonSlugs = reasonSlugs;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _ProfileRepo implements ProfileRepositoryPort {
  _ProfileRepo(this.profiles);

  final Map<String, Profile> profiles;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (profiles[id] != null) profiles[id]!,
  ];

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
    _EditReasonsForwardRepository forwardRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({
  required BeaconInvolvementData involvement,
  List<Profile> candidates = const [],
}) async {
  final authLocal = StreamingAuthLocal('U-me');
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
  contactsRepo.fetchMineHandler = () async => {};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('U-me');
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  final forwardRepo = _EditReasonsForwardRepository(
    candidates: candidates,
    involvement: involvement,
  );
  final profiles = {for (final profile in candidates) profile.id: profile};
  final forwardCase = ForwardCase(
    forwardRepo,
    authLocal,
    _FakeBeaconFactCardRepository(),
    _ProfileRepo(profiles),
    contactsCase,
    noopBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
  return (
    forwardCase: forwardCase,
    forwardRepo: forwardRepo,
    contactsCase: contactsCase,
    store: store,
  );
}

Future<void> _disposeHarness(
  ({
    ForwardCase forwardCase,
    _EditReasonsForwardRepository forwardRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
  harness,
) async {
  await harness.forwardRepo.dispose();
  await harness.contactsCase.dispose();
  if (GetIt.I.isRegistered<ContactNameStore>()) {
    await GetIt.I.unregister<ContactNameStore>();
  }
  await harness.store.dispose();
}

Beacon _beacon({String id = 'B-draft'}) => Beacon.empty.copyWith(
  id: id,
  title: id,
  status: BeaconStatus.open,
  author: const Profile(id: 'U-me'),
);

BeaconInvolvementData _involvementWithForward({
  required Beacon beacon,
  required String recipientId,
  required String edgeId,
}) => (
  beacon: beacon,
  forwardedToIds: {recipientId},
  helpOfferedIds: <String>{},
  withdrawnIds: <String>{},
  rejectedIds: <String>{},
  watchingIds: <String>{},
  onwardForwarderIds: <String>{},
  myForwardedRecipientNotes: <String, String>{},
  myForwardedRecipientEdgeIds: {recipientId: edgeId},
  myForwardedRecipientReadAts: <String, DateTime?>{},
);

Future<ForwardCubit> _openEditCubit({
  required ForwardCase forwardCase,
  required String recipientId,
}) async {
  final cubit = ForwardCubit(
    beaconId: 'B-draft',
    forwardCase: forwardCase,
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);

  await cubit.stream.firstWhere(
    (s) => s.candidates.any((c) => c.id == recipientId),
  );
  cubit.startEditForward(recipientId);
  return cubit;
}

void main() {
  const recipientId = 'U-forwarded';
  const edgeId = 'edge-1';

  test('startEditForward leaves editReasons null', () async {
    final harness = await _buildHarness(
      involvement: _involvementWithForward(
        beacon: _beacon(),
        recipientId: recipientId,
        edgeId: edgeId,
      ),
      candidates: const [
        Profile(
          id: recipientId,
          displayName: 'Forwarded',
          score: 1,
          rScore: 1,
        ),
      ],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = await _openEditCubit(
      forwardCase: harness.forwardCase,
      recipientId: recipientId,
    );

    expect(cubit.state.editReasons, isNull);
  });

  test(
    'saveForwardEdit passes null reasonSlugs when editReasons untouched',
    () async {
      final harness = await _buildHarness(
        involvement: _involvementWithForward(
          beacon: _beacon(),
          recipientId: recipientId,
          edgeId: edgeId,
        ),
        candidates: const [
          Profile(
            id: recipientId,
            displayName: 'Forwarded',
            score: 1,
            rScore: 1,
          ),
        ],
      );
      addTearDown(() => _disposeHarness(harness));

      final cubit = await _openEditCubit(
        forwardCase: harness.forwardCase,
        recipientId: recipientId,
      );

      await cubit.saveForwardEdit();

      expect(cubit.state.editingRecipientId, isNull);
      expect(harness.forwardRepo.lastUpdateReasonSlugs, isNull);
    },
  );

  test(
    'saveForwardEdit passes empty list when editReasons explicitly cleared',
    () async {
      final harness = await _buildHarness(
        involvement: _involvementWithForward(
          beacon: _beacon(),
          recipientId: recipientId,
          edgeId: edgeId,
        ),
        candidates: const [
          Profile(
            id: recipientId,
            displayName: 'Forwarded',
            score: 1,
            rScore: 1,
          ),
        ],
      );
      addTearDown(() => _disposeHarness(harness));

      final cubit = await _openEditCubit(
        forwardCase: harness.forwardCase,
        recipientId: recipientId,
      );
      cubit.setEditReasons(const []);

      await cubit.saveForwardEdit();

      expect(cubit.state.editingRecipientId, isNull);
      expect(harness.forwardRepo.lastUpdateReasonSlugs, isEmpty);
    },
  );

  test(
    'saveForwardEdit passes non-empty reasonSlugs unchanged',
    () async {
      final harness = await _buildHarness(
        involvement: _involvementWithForward(
          beacon: _beacon(),
          recipientId: recipientId,
          edgeId: edgeId,
        ),
        candidates: const [
          Profile(
            id: recipientId,
            displayName: 'Forwarded',
            score: 1,
            rScore: 1,
          ),
        ],
      );
      addTearDown(() => _disposeHarness(harness));

      final cubit = await _openEditCubit(
        forwardCase: harness.forwardCase,
        recipientId: recipientId,
      );
      cubit.setEditReasons(const ['transport']);

      await cubit.saveForwardEdit();

      expect(cubit.state.editingRecipientId, isNull);
      expect(harness.forwardRepo.lastUpdateReasonSlugs, ['transport']);
    },
  );
}
