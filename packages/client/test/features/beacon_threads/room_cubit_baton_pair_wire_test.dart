// Pair pick result over the recorded wire: the roomBatonSelect response
// (taker A, coTaker X) goes through the repository into a real RoomCubit, and
// RoomCubit.batonSelect returns both people.

import 'dart:convert';

import 'package:ferry/ferry.dart'
    show
        Client,
        FetchPolicy,
        Link,
        NextLink,
        OperationRequest,
        OperationResponse,
        OperationType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';

Map<String, dynamic> _partnerMessageRow({
  required String id,
  required String batonDataJson,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': 'Bbeacon0000001',
  'authorId': kRoomCubitFakeMyUserId,
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

const _boris = 'Ubbbbbbbbbbb';
const _xenia = 'Uxxxxxxxxxxx';

final _authorJson = jsonEncode({
  'id': 'Zbaton000001',
  'status': 'collecting',
  'viewerRole': 'author',
  'allAnswered': false,
  'eligibleCount': 1,
  'candidates': [
    {
      'userId': _boris,
      'title': 'Boris Driver',
      'tier': 1,
      'response': 'can_help',
      'partner': {'id': _xenia, 'title': 'Xenia Partner'},
    },
    {
      'userId': 'Uccccccccccc',
      'title': 'Clara Pending',
      'tier': 1,
      'response': 'waiting',
    },
  ],
  'pairs': [
    {'takerId': _boris, 'partnerId': _xenia, 'tier': 1},
  ],
});

final _takenJson = jsonEncode({
  'id': 'Zbaton000001',
  'status': 'taken',
  'viewerRole': 'author',
  'allAnswered': true,
  'eligibleCount': 1,
  'candidates': <Object>[],
  'taker': {'id': _boris, 'title': 'Boris Driver'},
  'coTaker': {'id': _xenia, 'title': 'Xenia Partner'},
  'selectionMode': 'manual',
});

late RoomCubit _roomCubit;

class _ServerLink extends Link {
  String current = _authorJson;
  final requests = <Request>[];

  List<Request> get selects => [
    for (final r in requests)
      if (r.operation.operationName == 'RoomBatonSelect') r,
  ];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    requests.add(request);
    if (request.operation.operationName == 'RoomBatonSelect') {
      current = _takenJson;
      return Stream.value(
        Response(
          data: {'__typename': 'mutation_root', 'roomBatonSelect': _takenJson},
          response: const {},
        ),
      );
    }
    return Stream.value(
      Response(
        data: {
          '__typename': 'query_root',
          'RoomMessageList': [
            _partnerMessageRow(id: 'Mbaton0000001', batonDataJson: current),
          ],
        },
        response: const {},
      ),
    );
  }
}

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

class _WireBackedRoomFake extends FakeBeaconThreadsRepository {
  _WireBackedRoomFake({required super.userId, required this.wireRepo});

  final BeaconThreadsRepository wireRepo;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) => wireRepo.fetchMessages(
    beaconId: beaconId,
    beforeIso: beforeIso,
    threadItemId: threadItemId,
  );

  @override
  Future<RoomBatonData?> batonSelect({
    required String batonId,
    String? userId,
  }) => wireRepo.batonSelect(batonId: batonId, userId: userId);
}

const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Viewer');

Future<_ServerLink> _pumpRoom(WidgetTester tester) async {
  await usePhoneSurface(tester);
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  GetIt.I
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final link = _ServerLink();
  final fake = _WireBackedRoomFake(
    userId: kRoomCubitFakeMyUserId,
    wireRepo: _repositoryFor(link),
  );
  late RoomCubit cubit;
  await tester.runAsync(() async {
    cubit = roomCubitForTest(fake);
    await awaitRoomCubitLoad(cubit).timeout(const Duration(seconds: 5));
    cubit.syncBeaconStatus(BeaconStatus.open);
  });
  _roomCubit = cubit;
  addTearDown(() => tester.runAsync(cubit.close));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(
          value: RoomBodyHarnessProfileCubit(_viewer),
        ),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const TenturaResponsiveScope(
          child: Scaffold(body: BeaconRoomBody()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return link;
}

void main() {
  group('RoomCubit.batonSelect over the recorded wire', () {
    testWidgets('the select response is decoded into a taker and co-taker', (
      tester,
    ) async {
      final link = await _pumpRoom(tester);
      late BatonSelectResult result;
      await tester.runAsync(() async {
        result = await _roomCubit.batonSelect(
          batonId: 'Zbaton000001',
          userId: _boris,
        );
      });

      expect(link.selects.single.variables['userId'], _boris);
      expect(result, isA<BatonSelected>());
      final selected = result as BatonSelected;
      expect(selected.taker?.id, _boris);
      expect(selected.coTaker?.id, _xenia);
      expect(selected.coTaker?.title, 'Xenia Partner');
    });
  });
}
