// Candidate baton card on the real room screen: (a) the optimistic card shown
// by RoomCubit.batonRespond before the server replies (together / Can't help),
// and (b) a recorded room response with an accepted partner invite rendered
// through the repository and cubit as the joined copy. 375x667, EN and RU.

import 'dart:async';

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
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
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


String _candidateJson({
  String response = 'waiting',
  List<(String id, String title, String status)> invites = const [],
}) =>
    '{"id":"Zbaton000001","status":"collecting","viewerRole":"candidate",'
    '"myResponse":"$response","partnerInvites":[${[for (final (id, title, status) in invites) '{"fromUserId":"$id","title":"$title","status":"$status"}'].join(',')}]}';

/// Serves one candidate baton message over the recorded wire.
class _ServerLink extends Link {
  _ServerLink(this.batonDataJson);

  final String batonDataJson;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(
        Response(
          data: {
            '__typename': 'query_root',
            'RoomMessageList': [
              _partnerMessageRow(
                id: 'Mbaton0000001',
                batonDataJson: batonDataJson,
              ),
            ],
          },
          response: const {},
        ),
      );
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

/// Room reads over the recorded wire when [wireRepo] is set, otherwise the
/// plain [messages]; baton answers wait on [gate].
class _RoomFake extends FakeBeaconThreadsRepository {
  _RoomFake({required super.userId, this.wireRepo});

  final BeaconThreadsRepository? wireRepo;
  Completer<void> gate = Completer<void>();

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) => wireRepo != null
      ? wireRepo!.fetchMessages(
          beaconId: beaconId,
          beforeIso: beforeIso,
          threadItemId: threadItemId,
        )
      : super.fetchMessages(
          beaconId: beaconId,
          beforeIso: beforeIso,
          threadItemId: threadItemId,
        );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #batonRespond) {
      return gate.future.then<RoomBatonData?>((_) => null);
    }
    return super.noSuchMethod(invocation);
  }
}

const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Viewer');

BeaconParticipant _person(String id, String title) => BeaconParticipant(
  id: 'p-$id',
  beaconId: kRoomCubitFakeBeaconId,
  userId: id,
  role: 0,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  userTitle: title,
);

Future<_RoomFake> _pumpRoom(
  WidgetTester tester, {
  required Locale locale,
  RoomBatonCandidateData? baton,
  String? wireJson,
}) async {
  await usePhoneSurface(tester);
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  GetIt.I
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final fake = _RoomFake(
    userId: kRoomCubitFakeMyUserId,
    wireRepo: wireJson == null ? null : _repositoryFor(_ServerLink(wireJson)),
  )
    ..participants = [
      _person(kRoomCubitFakeMyUserId, 'Viewer'),
      _person('u-bob', 'Bob'),
    ]
    ..messages = [
      if (baton != null)
        RoomMessage(
          id: 'msg-1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: 'u-anna',
          body: 'who can pick this up?',
          createdAt: DateTime.utc(2026, 10, 5),
          baton: baton,
        ),
    ];
  addTearDown(() {
    if (!fake.gate.isCompleted) fake.gate.complete();
  });
  late RoomCubit cubit;
  await tester.runAsync(() async {
    cubit = roomCubitForTest(fake);
    await awaitRoomCubitLoad(cubit).timeout(const Duration(seconds: 5));
    if (!cubit.state.participantsLoaded) {
      await cubit.stream
          .firstWhere((s) => s.participantsLoaded)
          .timeout(const Duration(seconds: 5));
    }
    cubit.syncBeaconStatus(BeaconStatus.open);
  });
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
        locale: locale,
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
  return fake;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  // The bubble's gesture arena resolves a tap after the double-tap window.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

const _waiting = RoomBatonCandidateData(
  id: 'Zbaton000001',
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.waiting,
);

const _pendingBob = RoomBatonCandidateData(
  id: 'Zbaton000001',
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.canHelp,
  myPartner: RoomBatonMyPartner(id: 'u-bob', title: 'Bob', status: 'pending'),
);

void main() {
  for (final (locale, together, pickTogether, answer) in [
    (
      const Locale('en'),
      'Together with…',
      'Bob',
      'Your answer: can help together with Bob. Waiting for Bob.',
    ),
    (
      const Locale('ru'),
      'Вместе с кем-то…',
      'Bob',
      'Ваш ответ: могу помочь вместе. Ждём ответа: Bob.',
    ),
  ]) {
    final lang = locale.languageCode.toUpperCase();
    group('Candidate card after an optimistic answer ($lang)', () {
      testWidgets('together shows the named partner while waiting for them', (
        tester,
      ) async {
        await _pumpRoom(tester, locale: locale, baton: _waiting);

        await _tap(tester, find.text(together));
        await tester.pumpAndSettle();
        await _tap(tester, find.text(pickTogether));
        await tester.pumpAndSettle();

        expect(find.text(answer), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets("Can't help drops the pending partner's waiting text", (
        tester,
      ) async {
        await _pumpRoom(tester, locale: locale, baton: _pendingBob);
        expect(
          find.textContaining('Bob'),
          findsWidgets,
          reason: 'precondition: the card names the pending partner',
        );

        await _tap(
          tester,
          find.text(locale.languageCode == 'en' ? "Can't help" : 'Не могу'),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            locale.languageCode == 'en'
                ? "Your answer: Can't help. You can change it."
                : 'Ваш ответ: Не могу. Его можно изменить.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Bob'), findsNothing);
      });
    });

    group('Candidate card from a recorded response ($lang)', () {
      final isEn = locale.languageCode == 'en';

      testWidgets("an accepted invite shows the joined copy and Can't after "
          'all, not the invite prompt', (tester) async {
        await _pumpRoom(
          tester,
          locale: locale,
          wireJson: _candidateJson(invites: [('Upat0000001', 'Pat', 'accepted')]),
        );

        expect(
          find.text(
            isEn
                ? "You'll take it together with Pat. "
                      "You can change your mind while it's open."
                : 'Вы согласились взяться вместе. Вместе с вами: Pat. '
                      'Пока выбор не сделан, это можно изменить.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(isEn ? "Can't after all" : 'Всё-таки не смогу'),
          findsOneWidget,
        );
        expect(
          find.text(
            isEn
                ? 'Pat wants to take this on together with you.'
                : 'Pat предлагает взяться за это вместе с вами.',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets("a pending invite keeps the prompt with Join and Can't", (
        tester,
      ) async {
        await _pumpRoom(
          tester,
          locale: locale,
          wireJson: _candidateJson(invites: [('Upat0000001', 'Pat', 'pending')]),
        );

        expect(
          find.text(
            isEn
                ? 'Pat wants to take this on together with you.'
                : 'Pat предлагает взяться за это вместе с вами.',
          ),
          findsOneWidget,
        );
        expect(find.text(isEn ? 'Join' : 'Возьмусь вместе'), findsOneWidget);
        expect(find.text(isEn ? "Can't" : 'Не смогу'), findsOneWidget);
      });
    });
  }
}
