import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_repository.dart';
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
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
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

  Object? fetchInitError;

  @override
  Future<MyWorkInitResult> fetchInit({required String userId}) async {
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
  ) async =>
      {};

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
  @override
  Stream<HelpOfferEvent> get helpOfferChanges => const Stream.empty();

  @override
  Stream<String> get forwardCompleted => const Stream.empty();

  @override
  Future<bool> currentUserHasForwardedBeacon(String beaconId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeBeaconRepository implements BeaconRepository {
  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeCoordinationItemRepository implements CoordinationItemRepository {
  @override
  Future<Map<String, CoordinationResponsibility>> fetchResponsibilityBatch(
    List<String> beaconIds,
  ) async =>
      {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRoomHints implements BeaconRoomHintsRepository {
  @override
  Future<Map<String, InboxRoomCardHints>> fetchByBeaconIds(
    Iterable<String> beaconIds,
  ) async =>
      {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeBeaconRoomRepository implements BeaconRoomRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakePollingRepository implements PollingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

BeaconRoomCase buildTestBeaconRoomCase(FakeRoomHints hints) {
  return BeaconRoomCase(
    FakeBeaconRoomRepository(),
    FakeFactCardRepository(),
    FakePollingRepository(),
    hints,
    RoomReadWatermarkStore.testing(),
    CoordinationItemCase(FakeCoordinationItemRepository()),
    env: const Env(),
    logger: Logger('test'),
  );
}

MyWorkCase buildTestMyWorkCase([FakeMyWorkRepository? repo]) {
  final hints = FakeRoomHints();
  return MyWorkCase(
    repo ?? FakeMyWorkRepository(),
    FakeArchiveRepository(),
    FakeForwardRepository(),
    FakeBeaconRepository(),
    CoordinationItemCase(FakeCoordinationItemRepository()),
    buildTestBeaconRoomCase(hints),
    hints,
    env: const Env(),
    logger: Logger('test'),
  );
}
