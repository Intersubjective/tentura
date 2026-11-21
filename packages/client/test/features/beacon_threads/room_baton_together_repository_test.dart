import 'package:ferry/ferry.dart'
    show
        Client,
        FetchPolicy,
        Link,
        NextLink,
        OperationRequest,
        OperationResponse,
        OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

import '../../support/baton_together_projection_accessors.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

Map<String, dynamic> _partnerMessageRow({
  required String id,
  required String batonDataJson,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': 'Bbeacon0000001',
  'authorId': 'Uauthor000001',
  'body': 'who can pick this up?',
  'createdAt': '2026-10-05T10:00:00.000Z',
  'editedAt': null,
  'semanticMarker': null,
  'systemMessageKind': null,
  'linkedBlockerId': null,
  'linkedFactCardId': null,
  'linkedPollingId': null,
  'linkedItemId': null,
  'linkedEventKind': null,
  'linkedItemKind': null,
  'linkedItemStatus': null,
  'linkedItemTitle': null,
  'linkedItemBody': null,
  'linkedItemCreatorId': null,
  'linkedItemTargetPersonId': null,
  'linkedItemCreatedAt': null,
  'linkedItemUpdatedAt': null,
  'linkedItemLinkedMessageId': null,
  'linkedItemResolvedAt': null,
  'pollDataJson': null,
  'batonDataJson': batonDataJson,
  'systemPayloadJson': null,
  'authorTitle': 'Alice',
  'authorHasPicture': false,
  'authorPicHeight': 0,
  'authorPicWidth': 0,
  'authorBlurHash': '',
  'authorImageId': '',
  'reactionsJson': null,
  'myReaction': null,
  'reactorsJson': null,
  'attachmentsJson': '[]',
  'mentions': <String>[],
  'mentionSpansJson': '[]',
  'replyToAuthorId': null,
  'replyToAuthorTitle': null,
  'replyToBodyExcerpt': null,
  'replyToHasAttachments': false,
  'replyToMessageId': null,
  'threadItemId': null,
  'quotedFact': null,
};

/// Records every outgoing request so tests can assert on wire variables.
class _RecordingLink extends Link {
  _RecordingLink(this.response);

  final Response response;

  final requests = <Request>[];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    requests.add(request);
    return Stream.value(response);
  }
}

Response _mutationResponse(String field, Object? value) => Response(
  data: {'__typename': 'mutation_root', field: value},
  response: const {},
);

final class _StubRemoteApiClient extends RemoteApiClient {
  _StubRemoteApiClient(this._client)
    : super(
        apiEndpointUrl: 'http://test/graphql',
        apiEndpointUrlV2: 'http://test/api/v2/graphql',
        authJwtExpiresIn: const Duration(hours: 1),
        requestTimeout: const Duration(minutes: 1),
        userAgent: 'test',
      );

  final Client _client;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => _client.request(request);
}

BeaconThreadsRepository _repositoryFor(Link link) {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  return BeaconThreadsRepository(
    _StubRemoteApiClient(
      Client(
        link: link,
        defaultFetchPolicies: const {
          OperationType.query: FetchPolicy.NoCache,
          OperationType.mutation: FetchPolicy.NoCache,
        },
      ),
    ),
    realtime.port,
  );
}

const _partnerPendingJson =
    '{"id":"Zbaton000001","status":"collecting","viewerRole":"partner",'
    '"partnerInvites":[{"fromUserId":"Uaaaaaaaaaaa","title":"Alice",'
    '"status":"pending"}]}';

const _candidateAcceptedPartnerJson =
    '{"id":"Zbaton000001","status":"collecting","viewerRole":"candidate",'
    '"myResponse":"can_help","myPartner":{"id":"Uyyyyyyyyyyy","title":"Yuri",'
    '"status":"accepted"}}';

class _WireBackedRoomFake extends FakeBeaconThreadsRepository {
  _WireBackedRoomFake({
    required super.userId,
    required this.wireRepo,
  });

  final BeaconThreadsRepository wireRepo;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) =>
      wireRepo.fetchMessages(
        beaconId: beaconId,
        beforeIso: beforeIso,
        threadItemId: threadItemId,
      );
}

class _PartnerArgRecordingRepository extends FakeBeaconThreadsRepository {
  _PartnerArgRecordingRepository({required super.userId});

  String? lastRespondPartnerUserId;
  ({String inviterUserId, bool accept})? lastPartnerRespond;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #batonRespond) {
      lastRespondPartnerUserId =
          invocation.namedArguments[#partnerUserId] as String?;
      return Future<RoomBatonData?>.value();
    }
    if (invocation.memberName == #batonPartnerRespond) {
      lastPartnerRespond = (
        inviterUserId: invocation.namedArguments[#inviterUserId] as String,
        accept: invocation.namedArguments[#accept] as bool,
      );
      return Future<RoomBatonData?>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

BeaconThreadsCase _caseFor(
  BeaconThreadsRepository repo, {
  RealtimeSyncCase? realtime,
}) => BeaconThreadsCase(
  repo,
  FakeBeaconFactCardRepository(),
  FakePollingRepository(),
  FakeBeaconRoomHintsRepository(),
  RoomReadWatermarkStore.testing(),
  realtime ?? buildTestRealtimeSync().case_,
);

void main() {
  group('batonRespond mutation variables', () {
    test('forwards partnerUserId on the wire', () async {
      final link = _RecordingLink(
        _mutationResponse('roomBatonRespond', _candidateAcceptedPartnerJson),
      );
      final repo = _repositoryFor(link);

      await (repo as dynamic).batonRespond(
        batonId: 'Zbaton000001',
        canHelp: true,
        partnerUserId: 'Uyyyyyyyyyyy',
      );

      final vars = link.requests.single.variables;
      expect(vars['batonId'], 'Zbaton000001');
      expect(vars['canHelp'], isTrue);
      expect(vars['partnerUserId'], 'Uyyyyyyyyyyy');
    });
  });

  group('batonPartnerRespond mutation variables', () {
    test('forwards inviterUserId and accept on the wire', () async {
      final link = _RecordingLink(
        _mutationResponse('roomBatonPartnerRespond', _partnerPendingJson),
      );
      final repo = _repositoryFor(link);

      await (repo as dynamic).batonPartnerRespond(
        batonId: 'Zbaton000001',
        inviterUserId: 'Uaaaaaaaaaaa',
        accept: true,
      );

      final vars = link.requests.single.variables;
      expect(vars['batonId'], 'Zbaton000001');
      expect(vars['inviterUserId'], 'Uaaaaaaaaaaa');
      expect(vars['accept'], isTrue);
    });
  });

  group('BeaconThreadsCase baton together forwarding', () {
    test('forwards partnerUserId into batonRespond', () async {
      final recording = _PartnerArgRecordingRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final case_ = _caseFor(recording);

      await (case_ as dynamic).batonRespond(
        batonId: 'Zbaton000001',
        canHelp: true,
        partnerUserId: 'Uyyyyyyyyyyy',
      );

      expect(recording.lastRespondPartnerUserId, 'Uyyyyyyyyyyy');
    });

    test('forwards inviter and accept into batonPartnerRespond', () async {
      final recording = _PartnerArgRecordingRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final case_ = _caseFor(recording);

      await (case_ as dynamic).batonPartnerRespond(
        batonId: 'Zbaton000001',
        inviterUserId: 'Uaaaaaaaaaaa',
        accept: false,
      );

      expect(recording.lastPartnerRespond?.inviterUserId, 'Uaaaaaaaaaaa');
      expect(recording.lastPartnerRespond?.accept, isFalse);
    });
  });

  group('recorded partner payload through repository', () {
    test('lands on RoomMessage.baton for the named partner', () async {
      final link = _RecordingLink(
        Response(
          data: {
            '__typename': 'query_root',
            'RoomMessageList': [
              _partnerMessageRow(
                id: 'Mbaton0000001',
                batonDataJson: _partnerPendingJson,
              ),
            ],
          },
          response: const {},
        ),
      );
      final repo = _repositoryFor(link);

      final messages = await repo.fetchMessages(beaconId: 'Bbeacon0000001');
      final baton = messages.single.baton;

      expect(baton, isRoomBatonPartnerData());
    });
  });

  group('recorded partner payload through repository into RoomCubit state', () {
    test('shows RoomBatonPartnerData on the loaded message', () async {
      final link = _RecordingLink(
        Response(
          data: {
            '__typename': 'query_root',
            'RoomMessageList': [
              _partnerMessageRow(
                id: 'Mbaton0000001',
                batonDataJson: _partnerPendingJson,
              ),
            ],
          },
          response: const {},
        ),
      );
      final wireRepo = _repositoryFor(link);
      final backing = _WireBackedRoomFake(
        userId: kRoomCubitFakeMyUserId,
        wireRepo: wireRepo,
      );

      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final cubit = RoomCubit(
        beaconId: kRoomCubitFakeBeaconId,
        beaconRoomCase: _caseFor(backing, realtime: realtime.case_),
        coordinationItemRoomSync: CoordinationItemRoomSync(),
        presenceRepository: roomCubitFakePresenceRepository(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      final baton = cubit.state.messages
          .singleWhere((m) => m.id == 'Mbaton0000001')
          .baton;
      expect(baton, isRoomBatonPartnerData());
    });
  });
}
