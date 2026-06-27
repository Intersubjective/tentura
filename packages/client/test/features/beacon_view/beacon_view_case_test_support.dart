import 'dart:async';

import 'package:logging/logging.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_activity_event_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_repository.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/beacon_view/data/repository/coordination_repository.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/coordination_item/data/repository/coordination_item_repository.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/my_work/data/repository/archive_repository.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

class FakeBeaconViewForwardRepository implements ForwardRepository {
  final _forwardCompleted = StreamController<String>.broadcast();
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();

  @override
  Stream<String> get forwardCompleted => _forwardCompleted.stream;

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  void emitForwardCompleted(String beaconId) => _forwardCompleted.add(beaconId);

  void emitHelpOfferChange(HelpOfferEvent event) =>
      _helpOfferChanges.add(event);

  Future<void> dispose() async {
    await _forwardCompleted.close();
    await _helpOfferChanges.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInvalidationService implements InvalidationService {
  final _beaconRoomController =
      StreamController<BeaconRoomInvalidation>.broadcast();

  void emitRoomInvalidation(BeaconRoomInvalidation invalidation) =>
      _beaconRoomController.add(invalidation);

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _beaconRoomController.stream;

  @override
  Stream<String> get beaconInvalidations => const Stream.empty();

  @override
  Stream<String> get helpOfferInvalidations => const Stream.empty();

  @override
  Stream<String> get forwardInvalidations => const Stream.empty();

  @override
  Stream<String> get capabilityInvalidations => const Stream.empty();

  Future<void> dispose() async {
    await _beaconRoomController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TrackingBeaconRepository implements BeaconRepository {
  final publishDraftCalls = <String>[];
  final refreshAndNotifyCalls = <String>[];
  int fetchByIdCalls = 0;
  Future<Beacon> Function(String id)? fetchByIdHandler;

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    fetchByIdCalls++;
    if (fetchByIdHandler != null) {
      return fetchByIdHandler!(id);
    }
    throw UnimplementedError('fetchBeaconById');
  }

  @override
  Future<void> publishDraft(String id) async {
    publishDraftCalls.add(id);
  }

  @override
  Future<void> refreshAndNotify(String id) async {
    refreshAndNotifyCalls.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewEvaluationRepository implements EvaluationRepository {
  @override
  Future<BeaconCloseResult> beaconClose({
    required String beaconId,
    required bool expectedRequiresReviewWindow,
  }) async =>
      BeaconCloseResult(beaconId: beaconId, state: 1);

  @override
  Future<BeaconLifecycleMutationResult> beaconCancel(String beaconId) async =>
      BeaconLifecycleMutationResult(beaconId: beaconId, state: 1);

  @override
  Future<BeaconExtendReviewResult> beaconExtendReview(String beaconId) async =>
      BeaconExtendReviewResult(
        beaconId: beaconId,
        closesAt: '2099-01-01T00:00:00.000Z',
      );

  @override
  Future<BeaconLifecycleMutationResult> beaconReopen(String beaconId) async =>
      BeaconLifecycleMutationResult(beaconId: beaconId, state: 1);

  @override
  Future<BeaconLifecycleMutationResult> beaconCloseNow(String beaconId) async =>
      BeaconLifecycleMutationResult(beaconId: beaconId, state: 1);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewArchiveRepository implements ArchiveRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewCoordinationRepository implements CoordinationRepository {
  FakeBeaconViewCoordinationRepository({
    this.enrichmentDelay = Duration.zero,
    this.enrichmentError,
  });

  final Duration enrichmentDelay;
  final Object? enrichmentError;

  @override
  Future<
    List<
      ({
        String beaconId,
        String userId,
        Profile user,
        String message,
        String? helpType,
        int status,
        String? withdrawReason,
        DateTime createdAt,
        DateTime updatedAt,
        int? responseType,
        DateTime? responseUpdatedAt,
        String? responseAuthorUserId,
        int? roomAccess,
      })
    >
  >
  fetchHelpOffersWithCoordination({required String beaconId}) async {
    await Future<void>.delayed(enrichmentDelay);
    if (enrichmentError != null) throw enrichmentError!;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewInboxRepository implements InboxRepository {
  @override
  Future<
    ({
      InboxItemStatus? status,
      InboxProvenance provenance,
      String latestNotePreview,
    })
  >
  fetchInboxContextForBeacon(String beaconId) async => (
    status: null,
    provenance: InboxProvenance.empty,
    latestNotePreview: '',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewActivityEventRepository
    implements BeaconActivityEventRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewRoomRepository implements BeaconRoomRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewRoomHintsRepository implements BeaconRoomHintsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewPollingRepository implements PollingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewCoordinationItemRepository
    implements CoordinationItemRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconRoomCase buildTestBeaconRoomCaseForView(
  RoomReadWatermarkStore watermark,
) =>
    BeaconRoomCase(
      FakeBeaconViewRoomRepository(),
      FakeBeaconViewFactCardRepository(),
      FakeBeaconViewPollingRepository(),
      FakeBeaconViewRoomHintsRepository(),
      watermark,
      CoordinationItemCase(FakeBeaconViewCoordinationItemRepository()),
      env: const Env(),
      logger: Logger('test'),
    );

BeaconViewCase buildTestBeaconViewCase({
  FakeBeaconViewForwardRepository? forward,
  FakeInvalidationService? invalidation,
  RoomReadWatermarkStore? watermarkStore,
  TrackingBeaconRepository? beaconRepo,
  FakeBeaconViewEvaluationRepository? evaluationRepo,
  FakeBeaconViewCoordinationRepository? coordinationRepo,
}) {
  final forwardRepo = forward ?? FakeBeaconViewForwardRepository();
  final invalidationSvc = invalidation ?? FakeInvalidationService();
  final watermark = watermarkStore ?? RoomReadWatermarkStore.testing();
  final beacon = beaconRepo ?? TrackingBeaconRepository();
  final evaluation = evaluationRepo ?? FakeBeaconViewEvaluationRepository();
  final coordination = coordinationRepo ?? FakeBeaconViewCoordinationRepository();

  return BeaconViewCase(
    beacon,
    forwardRepo,
    evaluation,
    FakeBeaconViewArchiveRepository(),
    coordination,
    FakeBeaconViewInboxRepository(),
    FakeBeaconViewFactCardRepository(),
    buildTestBeaconRoomCaseForView(watermark),
    FakeBeaconViewActivityEventRepository(),
    invalidationSvc,
    env: const Env(),
    logger: Logger('test'),
  );
}
