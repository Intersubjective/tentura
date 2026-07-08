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
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _PreselectForwardRepository implements ForwardRepository {
  _PreselectForwardRepository({
    required this.involvement,
    this.candidates = const [],
    this.lineage = const LineageForwardSuggestions(
      sourceBeaconId: '',
      rootBeaconId: '',
      suggestedNote: '',
      suggestions: [],
    ),
  });

  final List<Profile> candidates;
  final BeaconInvolvementData involvement;
  final LineageForwardSuggestions lineage;

  int fetchCandidatesCalls = 0;
  final _forwardCompleted = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardCompleted => _forwardCompleted.stream;

  void emitForwardCompleted(String beaconId) {
    if (!_forwardCompleted.isClosed) {
      _forwardCompleted.add(beaconId);
    }
  }

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async {
    fetchCandidatesCalls++;
    return candidates;
  }

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => involvement;

  @override
  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) async => lineage;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardCompleted.close();
}

class _PreselectProfileRepository implements ProfileRepositoryPort {
  _PreselectProfileRepository(this.profiles);

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
    _PreselectForwardRepository forwardRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({
  required BeaconInvolvementData involvement,
  List<Profile> candidates = const [],
  List<Profile> profileExtras = const [],
  LineageForwardSuggestions lineage = const LineageForwardSuggestions(
    sourceBeaconId: '',
    rootBeaconId: '',
    suggestedNote: '',
    suggestions: [],
  ),
}) async {
  final authLocal = StreamingAuthLocal('U-me');
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
  contactsRepo.fetchMineHandler = () async => {};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('U-me');
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  final forwardRepo = _PreselectForwardRepository(
    candidates: candidates,
    involvement: involvement,
    lineage: lineage,
  );
  final profiles = {
    for (final profile in [...candidates, ...profileExtras])
      profile.id: profile,
  };
  final forwardCase = ForwardCase(
    forwardRepo,
    authLocal,
    _FakeBeaconFactCardRepository(),
    _PreselectProfileRepository(profiles),
    contactsCase,
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

Beacon _beacon({
  String id = 'B-draft',
  String? lineageParentBeaconId,
}) => Beacon.empty.copyWith(
  id: id,
  title: id,
  author: const Profile(id: 'U-me'),
  lineageParentBeaconId: lineageParentBeaconId,
);

BeaconInvolvementData _involvement(Beacon beacon) => (
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

Future<void> _disposeHarness(
  ({
    ForwardCase forwardCase,
    _PreselectForwardRepository forwardRepo,
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

void main() {
  test(
    'preselectLineageSuggestions checks autoSelect lineage rows once',
    () async {
      final beacon = _beacon(lineageParentBeaconId: 'B-parent');
      final harness = await _buildHarness(
        involvement: _involvement(beacon),
        profileExtras: const [
          Profile(id: 'U-lineage', displayName: 'Lineage', rScore: 1),
        ],
        lineage: const LineageForwardSuggestions(
          sourceBeaconId: 'B-draft',
          rootBeaconId: 'B-parent',
          suggestedNote: '',
          suggestions: [
            LineageForwardSuggestion(
              userId: 'U-lineage',
              group: LineageSuggestionGroup.involved,
              reasonCode: 'involved',
              autoSelect: true,
            ),
          ],
        ),
      );
      addTearDown(() => _disposeHarness(harness));

      final cubit = ForwardCubit(
        beaconId: 'B-draft',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
        preselectLineageSuggestions: true,
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.selectedIds.contains('U-lineage'));
      expect(cubit.state.selectedIds, {'U-lineage'});

      cubit.toggleSelection('U-lineage');
      expect(cubit.state.selectedIds, isEmpty);
      harness.forwardRepo.emitForwardCompleted('B-draft');
      await cubit.stream.firstWhere(
        (s) =>
            s.status is StateIsSuccess &&
            harness.forwardRepo.fetchCandidatesCalls >= 2,
      );

      expect(cubit.state.selectedIds, isEmpty);
    },
  );

  test(
    'initialSelectedIds applies once and is not re-applied after deselect',
    () async {
      final harness = await _buildHarness(
        involvement: _involvement(_beacon()),
        candidates: const [
          Profile(id: 'U-target', displayName: 'Target', rScore: 1),
        ],
      );
      addTearDown(() => _disposeHarness(harness));

      final cubit = ForwardCubit(
        beaconId: 'B-draft',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
        initialSelectedIds: const {'U-target'},
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.selectedIds.contains('U-target'));
      expect(cubit.state.selectedIds, {'U-target'});

      cubit.toggleSelection('U-target');
      expect(cubit.state.selectedIds, isEmpty);
      harness.forwardRepo.emitForwardCompleted('B-draft');
      await cubit.stream.firstWhere(
        (s) =>
            s.status is StateIsSuccess &&
            harness.forwardRepo.fetchCandidatesCalls >= 2,
      );

      expect(cubit.state.selectedIds, isEmpty);
    },
  );

  test(
    'unavailable initialSelectedIds surface as droppedPreselectedIds',
    () async {
      final harness = await _buildHarness(involvement: _involvement(_beacon()));
      addTearDown(() => _disposeHarness(harness));

      final cubit = ForwardCubit(
        beaconId: 'B-draft',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
        initialSelectedIds: const {'U-missing'},
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere(
        (s) => s.droppedPreselectedIds.contains('U-missing'),
      );

      expect(cubit.state.selectedIds, isEmpty);
      expect(cubit.state.droppedPreselectedIds, {'U-missing'});
    },
  );

  test('lineage and user-explicit preselects apply independently', () async {
    final beacon = _beacon(lineageParentBeaconId: 'B-parent');
    final harness = await _buildHarness(
      involvement: _involvement(beacon),
      candidates: const [
        Profile(id: 'U-target', displayName: 'Target', rScore: 1),
      ],
      profileExtras: const [
        Profile(id: 'U-lineage', displayName: 'Lineage', rScore: 1),
      ],
      lineage: const LineageForwardSuggestions(
        sourceBeaconId: 'B-draft',
        rootBeaconId: 'B-parent',
        suggestedNote: '',
        suggestions: [
          LineageForwardSuggestion(
            userId: 'U-lineage',
            group: LineageSuggestionGroup.involved,
            reasonCode: 'involved',
            autoSelect: true,
          ),
        ],
      ),
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = ForwardCubit(
      beaconId: 'B-draft',
      forwardCase: harness.forwardCase,
      effects: FakeUiEffectPort(),
      preselectLineageSuggestions: true,
      initialSelectedIds: const {'U-target'},
    );
    addTearDown(cubit.close);

    await cubit.stream.firstWhere((s) => s.selectedIds.length == 2);

    expect(cubit.state.selectedIds, {'U-target', 'U-lineage'});
  });
}
