import 'dart:async';

import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_repository.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/coordination_item/data/repository/coordination_item_repository.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/data/repository/archive_repository.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/features/my_work/domain/port/my_work_desk_preferences_port.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

class FakeMyWorkRepository implements MyWorkRepository {
  MyWorkInitResult initResult = (
    authoredNonArchived: const <Beacon>[],
    helpOfferedNonArchived: const [],
    archivedCountHint: 0,
    lastItemDiscussionMessageAtByBeaconId: const <String, DateTime>{},
  );

  MyWorkArchivedResult archivedResult = (
    authoredArchived: const <Beacon>[],
    helpOfferedArchived: const [],
  );

  Exception? fetchInitError;

  int fetchInitCallCount = 0;

  Duration fetchInitDelay = Duration.zero;

  @override
  Future<MyWorkInitResult> fetchInit({required String userId}) async {
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
      _forwardCompletedController = StreamController<String>.broadcast();

  final StreamController<HelpOfferEvent> _helpOfferController;
  final StreamController<String> _forwardCompletedController;

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferController.stream;

  @override
  Stream<String> get forwardCompleted => _forwardCompletedController.stream;

  void emitHelpOffer(HelpOfferEvent event) => _helpOfferController.add(event);

  void emitForwardCompleted(String beaconId) =>
      _forwardCompletedController.add(beaconId);

  @override
  Future<void> dispose() async {
    await _helpOfferController.close();
    await _forwardCompletedController.close();
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

class FakeCoordinationItemRepository implements CoordinationItemRepository {
  Map<String, CoordinationResponsibility> responsibilityByBeaconId =
      const <String, CoordinationResponsibility>{};

  Object? fetchResponsibilityBatchError;

  List<String>? fetchResponsibilityBatchBeaconIds;

  @override
  Future<Map<String, CoordinationResponsibility>> fetchResponsibilityBatch(
    List<String> beaconIds,
  ) async {
    fetchResponsibilityBatchBeaconIds = List<String>.from(beaconIds);
    final error = fetchResponsibilityBatchError;
    if (error is Exception) {
      throw error;
    }
    if (error is Error) {
      throw error;
    }
    return {
      for (final beaconId in beaconIds)
        if (responsibilityByBeaconId.containsKey(beaconId))
          beaconId: responsibilityByBeaconId[beaconId]!,
    };
  }

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

class FakeBeaconRoomRepository implements BeaconRoomRepository {
  FakeBeaconRoomRepository()
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
  void notifyLocalChange({
    required String beaconId,
    required BeaconRoomEntityType entityType,
  }) {
    emitRoomInvalidation(
      BeaconRoomInvalidation(
        beaconId: beaconId,
        entityType: entityType,
      ),
    );
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

BeaconRoomCase buildTestBeaconRoomCase(
  FakeRoomHints hints, {
  RoomReadWatermarkStore? watermarkStore,
  FakeBeaconRoomRepository? roomRepo,
}) {
  return BeaconRoomCase(
    roomRepo ?? FakeBeaconRoomRepository(),
    FakeFactCardRepository(),
    FakePollingRepository(),
    hints,
    watermarkStore ?? RoomReadWatermarkStore.testing(),
    CoordinationItemCase(FakeCoordinationItemRepository()),
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
  FakeCoordinationItemRepository? coordinationRepo,
  FakeRoomHints? roomHints,
  RoomReadWatermarkStore? watermarkStore,
  FakeBeaconRoomRepository? roomRepo,
  BookkeepingRefreshSignal? bookkeepingRefreshSignal,
}) {
  final hints = roomHints ?? FakeRoomHints();
  final coordination = coordinationRepo ?? FakeCoordinationItemRepository();
  final prefs = deskPreferences ?? FakeMyWorkDeskPreferencesPort();
  final beacon = beaconRepo ?? FakeBeaconRepository();
  final forward = forwardRepo ?? FakeForwardRepository();
  final watermark = watermarkStore ?? RoomReadWatermarkStore.testing();
  return MyWorkCase(
    repo ?? FakeMyWorkRepository(),
    FakeArchiveRepository(),
    forward,
    beacon,
    CoordinationItemCase(coordination),
    buildTestBeaconRoomCase(
      hints,
      watermarkStore: watermark,
      roomRepo: roomRepo,
    ),
    hints,
    prefs,
    bookkeepingRefreshSignal ?? BookkeepingRefreshSignal(),
    env: const Env(),
    logger: Logger('test'),
  );
}
