import 'dart:async';

import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/data/repository/archive_repository.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/features/my_work/domain/port/my_work_desk_preferences_port.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../beacon_view/beacon_view_case_test_support.dart' show FakeBeaconDisplayRepository;
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import '../evaluation/evaluation_case_test.dart' show FakeEvaluationRepository;
import '../../support/test_realtime_sync.dart';

class StubAttentionRepository extends AttentionRepositoryFake {
  Set<String> obligationBeaconIds = const {};

  @override
  Future<Set<String>> liveObligationBeacons() async => obligationBeaconIds;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      throw UnimplementedError();

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => throw UnimplementedError();

  @override
  Future<int> markSeen(List<String> ids) async => throw UnimplementedError();

  @override
  Future<int> markUnseen(List<String> ids) async => throw UnimplementedError();

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      throw UnimplementedError();
}

class _StubAttentionAccounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

AttentionCase buildStubAttentionCase({
  StubAttentionRepository? repository,
}) {
  final repo = repository ?? StubAttentionRepository();
  return AttentionCase(
    repo,
    _StubAttentionAccounts(),
    buildTestRealtimeSync().case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-test-attention'),
    qaLatencyMeasurementEnabled: false,
  );
}

class FakeMyWorkRepository implements MyWorkRepository {
  MyWorkInitResult initResult = (
    authoredNonArchived: const <Beacon>[],
    helpOfferedNonArchived: const [],
    obligationBeacons: const [],
    archivedCountHint: 0,
  );

  List<String> lastObligationBeaconIds = const [];

  MyWorkArchivedResult archivedResult = (
    authoredArchived: const <Beacon>[],
    helpOfferedArchived: const [],
  );

  Exception? fetchInitError;

  int fetchInitCallCount = 0;

  Duration fetchInitDelay = Duration.zero;

  @override
  Future<MyWorkInitResult> fetchInit({
    required String userId,
    List<String> obligationBeaconIds = const [],
  }) async {
    lastObligationBeaconIds = obligationBeaconIds;
    fetchInitCallCount++;
    if (fetchInitDelay > Duration.zero) {
      await Future<void>.delayed(fetchInitDelay);
    }
    final error = fetchInitError;
    if (error != null) {
      throw error;
    }
    return initResult;
  }

  @override
  Future<MyWorkArchivedResult> fetchArchived({required String userId}) async =>
      archivedResult;

  @override
  Future<Map<String, MyWorkLastEvent?>> fetchLastActivityEventsByBeaconId(
    List<String> beaconIds,
  ) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeArchiveRepository implements ArchiveRepository {
  @override
  Future<void> archive(String beaconId) async {}

  @override
  Future<void> unarchive({
    required String beaconId,
    required String userId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeForwardRepository implements ForwardRepository {
  FakeForwardRepository()
    : _helpOfferController = StreamController<HelpOfferEvent>.broadcast(),
      _forwardChangesController = StreamController<String>.broadcast();

  final StreamController<HelpOfferEvent> _helpOfferController;
  final StreamController<String> _forwardChangesController;

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferController.stream;

  @override
  Stream<String> get forwardChanges => _forwardChangesController.stream;

  void emitHelpOffer(HelpOfferEvent event) => _helpOfferController.add(event);

  void emitForwardCompleted(String beaconId) =>
      _forwardChangesController.add(beaconId);

  @override
  Future<void> dispose() async {
    await _helpOfferController.close();
    await _forwardChangesController.close();
  }

  @override
  Future<bool> currentUserHasForwardedBeacon(String beaconId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconRepository implements BeaconRepository {
  FakeBeaconRepository()
    : _changesController =
          StreamController<RepositoryEvent<Beacon>>.broadcast();

  final StreamController<RepositoryEvent<Beacon>> _changesController;

  @override
  Stream<RepositoryEvent<Beacon>> get changes => _changesController.stream;

  void emitChange(RepositoryEvent<Beacon> event) =>
      _changesController.add(event);

  @override
  Future<void> dispose() async => _changesController.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRoomHints implements BeaconRoomHintsRepository {
  Map<String, InboxRoomCardHints> hintsByBeaconId =
      const <String, InboxRoomCardHints>{};

  List<String>? fetchByBeaconIdsBeaconIds;

  @override
  Future<Map<String, InboxRoomCardHints>> fetchByBeaconIds(
    Iterable<String> beaconIds,
  ) async {
    fetchByBeaconIdsBeaconIds = List<String>.from(beaconIds);
    return {
      for (final beaconId in beaconIds)
        if (hintsByBeaconId.containsKey(beaconId))
          beaconId: hintsByBeaconId[beaconId]!,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconThreadsRepository implements BeaconThreadsRepository {
  FakeBeaconThreadsRepository()
    : _roomInvalidations = StreamController<BeaconRoomInvalidation>.broadcast();

  final StreamController<BeaconRoomInvalidation> _roomInvalidations;

  @override
  Stream<String> get beaconRoomRefresh =>
      _roomInvalidations.stream.map((e) => e.beaconId);

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _roomInvalidations.stream;

  void emitRoomInvalidation(BeaconRoomInvalidation invalidation) {
    _roomInvalidations.add(invalidation);
  }

  @override
  Future<void> dispose() => _roomInvalidations.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePollingRepository implements PollingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconThreadsCase buildTestBeaconThreadsCase(
  FakeRoomHints hints, {
  RoomReadWatermarkStore? watermarkStore,
  FakeBeaconThreadsRepository? roomRepo,
}) {
  return BeaconThreadsCase(
    roomRepo ?? FakeBeaconThreadsRepository(),
    FakeFactCardRepository(),
    FakePollingRepository(),
    hints,
    watermarkStore ?? RoomReadWatermarkStore.testing(),
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
}

class FakeMyWorkDeskPreferencesPort implements MyWorkDeskPreferencesPort {
  final dismissedByUserId = <String, bool>{};

  @override
  Future<bool> isFinishedArchiveHintDismissed({required String userId}) async =>
      dismissedByUserId[userId] ?? false;

  @override
  Future<void> setFinishedArchiveHintDismissed({required String userId}) async {
    dismissedByUserId[userId] = true;
  }
}

MyWorkCase buildTestMyWorkCase({
  FakeMyWorkRepository? repo,
  FakeMyWorkDeskPreferencesPort? deskPreferences,
  FakeBeaconRepository? beaconRepo,
  FakeForwardRepository? forwardRepo,
  FakeRoomHints? roomHints,
  FakeBeaconDisplayRepository? displayRepo,
  FakeEvaluationRepository? evaluationRepo,
  RoomReadWatermarkStore? watermarkStore,
  FakeBeaconThreadsRepository? roomRepo,
  BookkeepingRefreshSignal? bookkeepingRefreshSignal,
  RealtimeSyncCase? realtimeSyncCase,
  AttentionCase? attentionCase,
  StubAttentionRepository? attentionRepository,
  bool obligationsGateEnabled = false,
}) {
  final hints = roomHints ?? FakeRoomHints();
  final prefs = deskPreferences ?? FakeMyWorkDeskPreferencesPort();
  final beacon = beaconRepo ?? FakeBeaconRepository();
  final forward = forwardRepo ?? FakeForwardRepository();
  final watermark = watermarkStore ?? RoomReadWatermarkStore.testing();
  final realtime = realtimeSyncCase ?? buildTestRealtimeSync().case_;
  return MyWorkCase(
    repo ?? FakeMyWorkRepository(),
    FakeArchiveRepository(),
    forward,
    beacon,
    buildTestBeaconThreadsCase(
      hints,
      watermarkStore: watermark,
      roomRepo: roomRepo,
    ),
    hints,
    prefs,
    displayRepo ?? FakeBeaconDisplayRepository(),
    evaluationRepo ?? FakeEvaluationRepository(),
    realtime,
    bookkeepingRefreshSignal ?? BookkeepingRefreshSignal(),
    attentionCase ??
        buildStubAttentionCase(repository: attentionRepository),
    obligationsGateEnabled,
    env: const Env(),
    logger: Logger('test'),
  );
}
