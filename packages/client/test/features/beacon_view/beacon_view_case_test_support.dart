import 'dart:async';

import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
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

typedef FakeHelpOfferCoordinationRow = ({
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
  int? admissionAction,
  String? lastDeclineReason,
  String? lastRemoveReason,
});

Never _throwTestError(Object error) {
  if (error is Exception) {
    throw error;
  }
  if (error is Error) {
    throw error;
  }
  throw StateError(error.toString());
}

class FakeBeaconViewForwardRepository implements ForwardRepository {
  final _forwardChanges = StreamController<String>.broadcast();
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final notifiedHelpOfferEvents = <HelpOfferEvent>[];

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  void emitForwardCompleted(String beaconId) => _forwardChanges.add(beaconId);

  void emitHelpOfferChange(HelpOfferEvent event) =>
      _helpOfferChanges.add(event);

  @override
  void notifyHelpOfferChanged(HelpOfferEvent event) {
    notifiedHelpOfferEvents.add(event);
    emitHelpOfferChange(event);
  }

  @override
  Future<void> dispose() async {
    await _forwardChanges.close();
    await _helpOfferChanges.close();
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
  }) async => BeaconCloseResult(beaconId: beaconId, state: 1);

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
    List<FakeHelpOfferCoordinationRow>? rows,
  }) : rows = rows ?? const [];

  final Duration enrichmentDelay;
  final Object? enrichmentError;
  final List<FakeHelpOfferCoordinationRow> rows;
  final setBeaconStatusCalls = <({String beaconId, int status})>[];
  final setCoordinationResponseCalls =
      <
        ({
          String beaconId,
          String offerUserId,
          int responseType,
          bool inviteToRoom,
          bool removeFromRoom,
        })
      >[];
  final acceptHelpOfferCalls = <({String beaconId, String offerUserId})>[];
  final declineHelpOfferCalls =
      <({String beaconId, String offerUserId, String reason})>[];
  final removeFromRoomCalls =
      <({String beaconId, String offerUserId, String reason})>[];

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) async {
    await Future<void>.delayed(enrichmentDelay);
    if (enrichmentError != null) _throwTestError(enrichmentError!);
    return rows;
  }

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> setBeaconStatus({
    required String beaconId,
    required int status,
  }) async {
    setBeaconStatusCalls.add((beaconId: beaconId, status: status));
    return (status: BeaconStatus.open, updatedAt: DateTime.utc(2026));
  }

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> setCoordinationResponse({
    required String beaconId,
    required String offerUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) async {
    setCoordinationResponseCalls.add((
      beaconId: beaconId,
      offerUserId: offerUserId,
      responseType: responseType,
      inviteToRoom: inviteToRoom,
      removeFromRoom: removeFromRoom,
    ));
    return (status: BeaconStatus.open, updatedAt: DateTime.utc(2026));
  }

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
  }) async {
    acceptHelpOfferCalls.add((beaconId: beaconId, offerUserId: offerUserId));
    return (status: BeaconStatus.open, updatedAt: DateTime.utc(2026));
  }

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String reason,
  }) async {
    declineHelpOfferCalls.add((
      beaconId: beaconId,
      offerUserId: offerUserId,
      reason: reason,
    ));
    return (status: BeaconStatus.open, updatedAt: DateTime.utc(2026));
  }

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String reason,
  }) async {
    removeFromRoomCalls.add((
      beaconId: beaconId,
      offerUserId: offerUserId,
      reason: reason,
    ));
    return (status: BeaconStatus.open, updatedAt: DateTime.utc(2026));
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
  FakeBeaconViewActivityEventRepository({this.listError});

  final Object? listError;

  @override
  Future<List<BeaconActivityEvent>> list({required String beaconId}) async {
    if (listError != null) _throwTestError(listError!);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewFactCardRepository implements BeaconFactCardRepository {
  FakeBeaconViewFactCardRepository({this.listError});

  final Object? listError;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    if (listError != null) _throwTestError(listError!);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBeaconViewRoomRepository implements BeaconRoomRepository {
  final _roomInvalidations =
      StreamController<BeaconRoomInvalidation>.broadcast();

  final localChanges = <BeaconRoomInvalidation>[];

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
    final invalidation = BeaconRoomInvalidation(
      beaconId: beaconId,
      entityType: entityType,
    );
    localChanges.add(invalidation);
    emitRoomInvalidation(invalidation);
  }

  @override
  Future<void> dispose() => _roomInvalidations.close();

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
  RoomReadWatermarkStore watermark, {
  FakeBeaconViewRoomRepository? room,
}) => BeaconRoomCase(
  room ?? FakeBeaconViewRoomRepository(),
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
  RoomReadWatermarkStore? watermarkStore,
  TrackingBeaconRepository? beaconRepo,
  FakeBeaconViewEvaluationRepository? evaluationRepo,
  FakeBeaconViewCoordinationRepository? coordinationRepo,
  FakeBeaconViewFactCardRepository? factCardsRepo,
  FakeBeaconViewActivityEventRepository? activityEventsRepo,
  FakeBeaconViewRoomRepository? roomRepo,
}) {
  final forwardRepo = forward ?? FakeBeaconViewForwardRepository();
  final watermark = watermarkStore ?? RoomReadWatermarkStore.testing();
  final beacon = beaconRepo ?? TrackingBeaconRepository();
  final evaluation = evaluationRepo ?? FakeBeaconViewEvaluationRepository();
  final coordination =
      coordinationRepo ?? FakeBeaconViewCoordinationRepository();
  final factCards = factCardsRepo ?? FakeBeaconViewFactCardRepository();
  final activityEvents =
      activityEventsRepo ?? FakeBeaconViewActivityEventRepository();

  return BeaconViewCase(
    beacon,
    forwardRepo,
    evaluation,
    FakeBeaconViewArchiveRepository(),
    coordination,
    FakeBeaconViewInboxRepository(),
    factCards,
    buildTestBeaconRoomCaseForView(watermark, room: roomRepo),
    activityEvents,
    env: const Env(),
    logger: Logger('test'),
  );
}
