import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/entity/user_bookkeeping_result.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_admission_repository_port.dart';
import 'package:tentura_server/domain/port/user_bookkeeping_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_bookkeeping_case.dart';
import 'package:tentura_server/env.dart';
import 'package:injectable/injectable.dart' show Environment;

void main() {
  late _FakeBookkeepingRepo bookkeeping;
  late _FakeCoordination coordination;
  late _FakeAdmission admission;
  late _FakeForward forward;
  late UserBookkeepingCase case_;

  setUp(() {
    bookkeeping = _FakeBookkeepingRepo();
    coordination = _FakeCoordination();
    admission = _FakeAdmission();
    forward = _FakeForward();
    case_ = UserBookkeepingCase(
      bookkeeping,
      coordination,
      admission,
      forward,
      env: Env(environment: Environment.test),
      logger: Logger('test'),
    );
  });

  test('repairs admitted offers missing coordination', () async {
    bookkeeping.gaps = const [
      AdmittedOfferCoordinationGap(
        beaconId: 'B1',
        offerUserId: 'Uhelper',
        authorUserId: 'Uauthor',
      ),
    ];
    forward.directAuthorForward = true;

    final result = await case_.recalculateForUser(userId: 'Uauthor');

    expect(result.coordinationRepairedCount, 1);
    expect(coordination.upserts, hasLength(1));
    expect(
      coordination.upserts.single.responseType,
      CoordinationResponseType.useful.smallintValue,
    );
    expect(admission.records, hasLength(1));
    expect(admission.records.single.action, HelpOfferAdmissionAction.autoAdmit);
    expect(result.affectedBeaconIds, contains('B1'));
  });

  test('skips admission event when one already exists', () async {
    bookkeeping.gaps = const [
      AdmittedOfferCoordinationGap(
        beaconId: 'B1',
        offerUserId: 'Uhelper',
        authorUserId: 'Uauthor',
      ),
    ];
    admission.existing = HelpOfferAdmissionEvent(
      id: 'HA1',
      seq: 1,
      beaconId: 'B1',
      offerUserId: 'Uhelper',
      actorUserId: 'Uauthor',
      action: HelpOfferAdmissionAction.accept,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await case_.recalculateForUser(userId: 'Uauthor');

    expect(admission.records, isEmpty);
    expect(coordination.upserts, hasLength(1));
  });

  test('merges inbox reconcile beacon ids into result', () async {
    bookkeeping.inboxResult = const InboxReconcileResult(
      repairedCount: 2,
      insertedCount: 1,
      beaconIds: ['B2', 'B3'],
    );

    final result = await case_.recalculateForUser(userId: 'Uauthor');

    expect(result.inboxRowsRepairedCount, 2);
    expect(result.inboxRowsInsertedCount, 1);
    expect(result.affectedBeaconIds, containsAll(['B2', 'B3']));
  });
}

final class _FakeBookkeepingRepo implements UserBookkeepingRepositoryPort {
  List<AdmittedOfferCoordinationGap> gaps = const [];
  InboxReconcileResult inboxResult = const InboxReconcileResult(
    repairedCount: 0,
    insertedCount: 0,
    beaconIds: [],
  );

  @override
  Future<List<AdmittedOfferCoordinationGap>>
  listAdmittedOffersMissingCoordination(String authorUserId) async => gaps;

  @override
  Future<InboxReconcileResult> reconcileInboxForUser(String userId) async =>
      inboxResult;
}

final class _FakeCoordination implements CoordinationRepositoryPort {
  final upserts = <_UpsertCall>[];

  @override
  Future<void> upsertResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
  }) async {
    upserts.add(
      _UpsertCall(
        beaconId: beaconId,
        offerUserId: offerUserId,
        authorUserId: authorUserId,
        responseType: responseType,
      ),
    );
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError();
}

final class _UpsertCall {
  _UpsertCall({
    required this.beaconId,
    required this.offerUserId,
    required this.authorUserId,
    required this.responseType,
  });

  final String beaconId;
  final String offerUserId;
  final String authorUserId;
  final int responseType;
}

final class _FakeAdmission implements HelpOfferAdmissionRepositoryPort {
  HelpOfferAdmissionEvent? existing;
  final records = <_AdmissionCall>[];

  @override
  Future<HelpOfferAdmissionEvent?> latestFor({
    required String beaconId,
    required String offerUserId,
  }) async =>
      existing;

  @override
  Future<void> record({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required HelpOfferAdmissionAction action,
    String? reason,
  }) async {
    records.add(
      _AdmissionCall(
        beaconId: beaconId,
        offerUserId: offerUserId,
        actorUserId: actorUserId,
        action: action,
      ),
    );
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError();
}

final class _AdmissionCall {
  _AdmissionCall({
    required this.beaconId,
    required this.offerUserId,
    required this.actorUserId,
    required this.action,
  });

  final String beaconId;
  final String offerUserId;
  final String actorUserId;
  final HelpOfferAdmissionAction action;
}

final class _FakeForward implements ForwardEdgeRepositoryPort {
  bool directAuthorForward = false;

  @override
  Future<bool> isDirectAuthorForward({
    required String beaconId,
    required String authorId,
    required String userId,
  }) async =>
      directAuthorForward;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError();
}
