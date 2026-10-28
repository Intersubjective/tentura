import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../beacon_view/beacon_view_screen_harness.dart';
import '../../support/test_realtime_sync.dart';

const _target = Profile(
  id: 'recipient',
  displayName: 'Recipient',
  score: 1,
  rScore: 1,
);

class _ForwardRepository implements ForwardRepository {
  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => const [_target];

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon.empty.copyWith(
      id: beaconId,
      author: const Profile(id: 'U-me'),
    ),
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

  @override
  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) async => const LineageForwardSuggestions(
    sourceBeaconId: '',
    rootBeaconId: '',
    suggestedNote: '',
    suggestions: [],
  );

  final sentTo = <List<String>>[];

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
    sentTo.add(recipientIds);
    return ForwardDeliveryResult(
      batchId: 'delivery',
      deliveredRecipientIds: recipientIds,
      availabilitySkippedRecipientIds: const [],
    );
  }

  @override
  Future<void> dispose() => _forwardChanges.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileRepository implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (id == _target.id) _target,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<void> dispose() async {}
}

class _ContextCubit extends Cubit<ContextState> implements ContextCubit {
  _ContextCubit() : super(const ContextState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real forwarding case/cubit with in-memory backend ports. Screen navigation
/// and sending are exercised through product widgets, with no UI callbacks
/// replaced by the fixture.
Future<ContextCubit> registerChildSendCollaborators() async {
  final getIt = GetIt.I;
  await registerBeaconViewHarnessGetIt();
  addTearDown(getIt.reset);
  final authLocal = StreamingAuthLocal('U-me');
  final store = ContactNameStore();
  final realtime = buildTestRealtimeSync();
  final contacts = ContactsCase(
    FakeContactsRepository(),
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    realtime.case_,
    env: const Env(),
    logger: Logger('ChildSendWidget'),
  );
  final repo = _ForwardRepository();
  getIt
    ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
    ..registerSingleton<ContactNameStore>(store)
    ..registerSingleton<Logger>(Logger('ChildSendWidget'))
    ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
    ..registerSingleton<ForwardCase>(
      ForwardCase(
        repo,
        authLocal,
        _FactCardRepository(),
        _ProfileRepository(),
        contacts,
        noopBlockCase(),
        env: const Env(),
        logger: Logger('ChildSendWidget'),
      ),
    );
  addTearDown(() async {
    await repo.dispose();
    await contacts.dispose();
    await store.dispose();
    await realtime.port.dispose();
  });
  return _ContextCubit();
}
