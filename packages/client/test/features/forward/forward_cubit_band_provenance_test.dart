import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/capability/projection_tier.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/domain/entity/forward_delivery_result.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../block/support/controllable_block_case.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/test_realtime_sync.dart';

class _BandProvenanceForwardRepository implements ForwardRepository {
  _BandProvenanceForwardRepository({
    required this.involvement,
    this.candidates = const [],
  });

  final List<Profile> candidates;
  final BeaconInvolvementData involvement;

  Map<String, ({String? tier, bool isExploration})>?
  lastRecipientBandProvenance;
  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => candidates;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => involvement;

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
  Future<ForwardDeliveryResult> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
    List<String>? attributionParentEdgeIds,
    Map<String, ({String? tier, bool isExploration})>?
    recipientBandProvenance,
  }) async {
    lastRecipientBandProvenance = recipientBandProvenance;
    return const ForwardDeliveryResult(
      batchId: 'batch-band-provenance',
      deliveredRecipientIds: [],
      availabilitySkippedRecipientIds: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _FakeCapabilityRepositoryForBand implements CapabilityRepositoryPort {
  _FakeCapabilityRepositoryForBand(this.band);

  final List<ForwardBandRow> band;

  @override
  Future<List<ForwardBandRow>> fetchForwardContext({
    required String beaconId,
    String? context,
  }) async => band;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

Beacon _beacon({String id = 'B-draft'}) => Beacon.empty.copyWith(
  id: id,
  title: id,
  status: BeaconStatus.open,
  author: const Profile(id: 'U-me'),
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

Future<
  ({
    ForwardCase forwardCase,
    _BandProvenanceForwardRepository forwardRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({
  required BeaconInvolvementData involvement,
  required List<ForwardBandRow> band,
  List<Profile> candidates = const [],
}) async {
  final authLocal = StreamingAuthLocal('U-me');
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  GetIt.I.registerSingleton<CapabilityRepositoryPort>(
    _FakeCapabilityRepositoryForBand(band),
  );
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

  final forwardRepo = _BandProvenanceForwardRepository(
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
    _BandProvenanceForwardRepository forwardRepo,
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
  if (GetIt.I.isRegistered<CapabilityRepositoryPort>()) {
    await GetIt.I.unregister<CapabilityRepositoryPort>();
  }
  await harness.store.dispose();
}

void main() {
  test(
    'forward tags recipients with their band tier/exploration provenance (G1a)',
    () async {
      final harness = await _buildHarness(
        involvement: _involvement(_beacon()),
        candidates: const [
          Profile(id: 'U-tiered', displayName: 'Tiered', score: 1, rScore: 1),
          Profile(
            id: 'U-exploration',
            displayName: 'Exploration',
            score: 1,
            rScore: 1,
          ),
          Profile(
            id: 'U-main-list',
            displayName: 'MainList',
            score: 1,
            rScore: 1,
          ),
        ],
        band: const [
          ForwardBandRow(
            userId: 'U-tiered',
            rowTier: ProjectionTier.networkOutcome,
            rank: 0,
          ),
          ForwardBandRow(
            userId: 'U-exploration',
            rowTier: null,
            rank: 1,
            isExploration: true,
          ),
        ],
      );
      addTearDown(() => _disposeHarness(harness));

      final effects = FakeUiEffectPort();
      final cubit = ForwardCubit(
        beaconId: 'B-draft',
        forwardCase: harness.forwardCase,
        effects: effects,
        embedded: true,
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
      cubit.toggleSelection('U-tiered');
      cubit.toggleSelection('U-exploration');
      cubit.toggleSelection('U-main-list');

      final ok = await cubit.forward();

      expect(ok, isTrue);
      final provenance = harness.forwardRepo.lastRecipientBandProvenance;
      expect(provenance, isNotNull);
      expect(provenance!['U-tiered'], (tier: 'networkOutcome', isExploration: false));
      expect(provenance['U-exploration'], (tier: null, isExploration: true));
      expect(provenance.containsKey('U-main-list'), isFalse);
    },
  );
}
