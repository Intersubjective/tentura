import 'dart:async';

import 'dart:io';

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
import 'package:tentura/features/forward/domain/entity/forward_delivery_result.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../block/support/controllable_block_case.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/test_realtime_sync.dart';

class _RecordingForwardRepository implements ForwardRepository {
  _RecordingForwardRepository({
    required this.involvement,
    this.candidates = const [],
  });

  final List<Profile> candidates;
  final BeaconInvolvementData involvement;

  String? lastForwardArguments;
  List<String>? lastRecipientIds;
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
    Map<String, ({String? tier, bool isExploration})>? recipientBandProvenance,
  }) async {
    lastForwardArguments = [
      beaconId,
      recipientIds,
      note,
      perRecipientNotes,
      recipientReasons,
      context,
      parentEdgeId,
      attributionParentEdgeIds,
      recipientBandProvenance,
    ].join('|');
    lastRecipientIds = recipientIds;
    return const ForwardDeliveryResult(
      batchId: 'batch-attribution',
      deliveredRecipientIds: [],
      availabilitySkippedRecipientIds: [],
    );
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
  myForwardedRecipientHasOnwardChild: <String, bool>{},
  myForwardedRecipientRejected: <String, bool>{},
);

Future<
  ({
    ForwardCase forwardCase,
    _RecordingForwardRepository forwardRepo,
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

  final forwardRepo = _RecordingForwardRepository(
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
    _RecordingForwardRepository forwardRepo,
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
  test('forward call carries the picked people and no tag data', () async {
    final harness = await _buildHarness(
      involvement: _involvement(_beacon()),
      candidates: const [
        Profile(id: 'U-a', displayName: 'A', score: 1, rScore: 1),
        Profile(id: 'U-b', displayName: 'B', score: 1, rScore: 1),
      ],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = ForwardCubit(
      beaconId: 'B-draft',
      forwardCase: harness.forwardCase,
      effects: FakeUiEffectPort(),
      embedded: true,
    );
    addTearDown(cubit.close);

    await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
    cubit
      ..toggleTag('tag-secret-id', ['U-a', 'U-b']);
    expect(cubit.state.selectedIds, {'U-a', 'U-b'});

    cubit.setNote('tag forward');
    final ok = await cubit.forward();

    expect(ok, isTrue);
    expect(harness.forwardRepo.lastRecipientIds, ['U-a', 'U-b']);
    expect(
      harness.forwardRepo.lastForwardArguments,
      isNot(contains('tag-secret-id')),
    );
  });

  group('forward mutation contract', () {
    test('the GraphQL document has no tag variable or argument', () {
      final doc = File(
        'lib/features/forward/data/gql/forward_beacon.graphql',
      ).readAsStringSync();

      expect(doc.toLowerCase(), isNot(contains('tag')));
    });

    test('the generated variables class has no tag field', () {
      final vars = File(
        'lib/features/forward/data/gql/_g/forward_beacon.var.gql.dart',
      ).readAsStringSync();

      expect(vars.toLowerCase(), isNot(contains('tag')));
    });

    test('the repository forwardBeacon signature takes no tag parameter', () {
      final src = File(
        'lib/features/forward/data/repository/forward_repository.dart',
      ).readAsStringSync();
      final start = src.indexOf('Future<ForwardDeliveryResult> forwardBeacon(');
      final signature = src.substring(start, src.indexOf('}) =>', start));

      expect(signature.toLowerCase(), isNot(contains('tag')));
    });
  });
}
