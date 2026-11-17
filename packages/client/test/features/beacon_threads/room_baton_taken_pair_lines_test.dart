// «Who'll take it?» baton together, what everyone else reads once a PAIR took
// it: the room's marker-12 system line and the baton card's status line say
// «{A} and {X} took it.» (EN) / «Берут на себя: {A} и {X}» (RU), with the ask
// variant further down the room. Without a co-taker both stay the solo line.
// The last group feeds a recorded room GraphQL response through the real
// repository and RoomCubit into the room screen.

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
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

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
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'u-viewer', displayName: 'Viewer');
const _author = Profile(id: 'u-author', displayName: 'Author');

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

BeaconParticipant _participant(String userId, String title) =>
    BeaconParticipant(
      id: 'p-$userId',
      beaconId: 'b-baton',
      userId: userId,
      role: 0,
      status: 0,
      roomAccess: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      userTitle: title,
    );

final _participants = [
  _participant('u-anna', 'Anna'),
  _participant('u-xenia', 'Xenia'),
];

RoomMessage _message(String id, String body, {int minute = 0}) => RoomMessage(
  id: id,
  beaconId: 'b-baton',
  authorId: _author.id,
  author: _author,
  body: body,
  createdAt: DateTime.utc(2026, 10, 3, 12, minute),
);

final _source = _message('msg-1', 'Carry the boxes');
final _other = _message('msg-2', 'See you at nine', minute: 30);

RoomMessage _takenLine({bool pair = true, bool withSource = false}) =>
    RoomMessage(
      id: 'sys-1',
      beaconId: 'b-baton',
      authorId: _author.id,
      author: _author,
      body: '',
      createdAt: DateTime.utc(2026, 10, 3, 13),
      semanticMarker: BeaconRoomSemanticMarker.batonTaken,
      systemPayloadJson: jsonEncode({
        'batonId': 'baton-1',
        if (withSource) 'sourceMessageId': 'msg-1',
        'takerUserId': 'u-anna',
        if (pair) 'coTakerUserId': 'u-xenia',
      }),
    );

Widget _app(Widget child, {String locale = 'en'}) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: Locale(locale),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 900)),
    child: TenturaResponsiveScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

Widget _line(
  RoomMessage line, {
  RoomMessage? previous,
  RoomCubit? room,
  String locale = 'en',
}) => MultiBlocProvider(
  providers: [
    if (room != null) BlocProvider<RoomCubit>.value(value: room),
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: _app(
    RoomMessageTile(
      message: line,
      previousMessage: previous,
      myProfile: _viewer,
      participants: _participants,
      onToggleReaction: (_, _) async {},
    ),
    locale: locale,
  ),
);

Future<RoomCubit> _roomWith(
  WidgetTester tester,
  List<RoomMessage> messages,
) async {
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final repo = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
    ..messages = messages;
  final room = roomCubitForTest(repo);
  await tester.runAsync(() => awaitRoomCubitLoad(room));
  addTearDown(() => tester.runAsync(room.close));
  return room;
}

const _anna = RoomBatonTaker(id: 'u-anna', title: 'Anna');
const _xenia = RoomBatonTaker(id: 'u-xenia', title: 'Xenia');

Widget _card(RoomBatonData baton, {String locale = 'en'}) =>
    _app(RoomBatonCard(baton: baton), locale: locale);

/// Whose avatars are on screen, in reading order.
List<String> _avatarNames(WidgetTester tester) => [
  for (final a in tester.widgetList<TenturaAvatar>(find.byType(TenturaAvatar)))
    a.profile.displayName,
];

void main() {
  group('room line «{A} and {X} took it.»', () {
    testWidgets('names both takers', (tester) async {
      await tester.pumpWidget(_line(_takenLine(), previous: _other));
      await tester.pump();

      expect(find.text('Anna and Xenia took it.'), findsOneWidget);
    });

    testWidgets('names both takers in Russian', (tester) async {
      await tester.pumpWidget(
        _line(_takenLine(), previous: _other, locale: 'ru'),
      );
      await tester.pump();

      expect(find.text('Берут на себя: Anna и Xenia'), findsOneWidget);
    });

    testWidgets('says what was taken when the ask is loaded', (tester) async {
      final room = await _roomWith(tester, [_source, _other, _takenLine()]);

      await tester.pumpWidget(
        _line(_takenLine(withSource: true), previous: _other, room: room),
      );
      await tester.pump();

      expect(
        find.text('Anna and Xenia took it: Carry the boxes'),
        findsOneWidget,
      );
    });

    testWidgets('says what was taken in Russian', (tester) async {
      final room = await _roomWith(tester, [_source, _other, _takenLine()]);

      await tester.pumpWidget(
        _line(
          _takenLine(withSource: true),
          previous: _other,
          room: room,
          locale: 'ru',
        ),
      );
      await tester.pump();

      expect(
        find.text('Берут на себя: Anna и Xenia — Carry the boxes'),
        findsOneWidget,
      );
    });

    testWidgets('is not shown right under its baton card', (tester) async {
      await tester.pumpWidget(
        _line(_takenLine(withSource: true), previous: _source),
      );
      await tester.pump();

      expect(find.textContaining('took it'), findsNothing);
      expect(find.textContaining('Xenia'), findsNothing);
    });

    testWidgets('without a co-taker stays the solo line', (tester) async {
      await tester.pumpWidget(_line(_takenLine(pair: false), previous: _other));
      await tester.pump();

      expect(find.text('Anna took it.'), findsOneWidget);
      expect(find.textContaining('Xenia'), findsNothing);
      expect(find.textContaining(' and '), findsNothing);
    });

    testWidgets('without a co-taker keeps the solo ask line', (tester) async {
      final room = await _roomWith(tester, [_source, _other, _takenLine()]);

      await tester.pumpWidget(
        _line(
          _takenLine(pair: false, withSource: true),
          previous: _other,
          room: room,
        ),
      );
      await tester.pump();

      expect(find.text('Anna took it: Carry the boxes'), findsOneWidget);
      expect(find.textContaining('Xenia'), findsNothing);
    });

    testWidgets('without a co-taker keeps the Russian solo ask line', (
      tester,
    ) async {
      final room = await _roomWith(tester, [_source, _other, _takenLine()]);

      await tester.pumpWidget(
        _line(
          _takenLine(pair: false, withSource: true),
          previous: _other,
          room: room,
          locale: 'ru',
        ),
      );
      await tester.pump();

      expect(
        find.text('Берёт на себя: Anna — Carry the boxes'),
        findsOneWidget,
      );
      expect(find.textContaining('Xenia'), findsNothing);
    });

    testWidgets('without a co-taker keeps the Russian solo line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _line(_takenLine(pair: false), previous: _other, locale: 'ru'),
      );
      await tester.pump();

      expect(find.text('Берёт на себя: Anna'), findsOneWidget);
      expect(find.textContaining('Xenia'), findsNothing);
      expect(find.textContaining(' и '), findsNothing);
    });
  });

  group('baton card status line once a pair took it', () {
    final pairObserver = [
      const RoomBatonObserverData(
        id: 'baton-1',
        status: RoomBatonStatus.taken,
        taker: _anna,
        coTaker: _xenia,
      ),
      const RoomBatonAuthorData(
        id: 'baton-1',
        status: RoomBatonStatus.taken,
        candidates: [],
        allAnswered: true,
        eligibleCount: 0,
        taker: _anna,
        coTaker: _xenia,
      ),
    ];
    final solo = [
      const RoomBatonObserverData(
        id: 'baton-1',
        status: RoomBatonStatus.taken,
        taker: _anna,
      ),
      const RoomBatonAuthorData(
        id: 'baton-1',
        status: RoomBatonStatus.taken,
        candidates: [],
        allAnswered: true,
        eligibleCount: 0,
        taker: _anna,
      ),
    ];

    for (final baton in pairObserver) {
      final role = baton.runtimeType.toString();
      testWidgets('$role names both, with an avatar for each', (tester) async {
        await tester.pumpWidget(_card(baton));
        await tester.pump();

        expect(find.text('Anna and Xenia took it.'), findsOneWidget);
        expect(find.byType(TenturaAvatar), findsNWidgets(2));
        expect(_avatarNames(tester), ['Anna', 'Xenia']);
      });

      testWidgets('$role names both in Russian', (tester) async {
        await tester.pumpWidget(_card(baton, locale: 'ru'));
        await tester.pump();

        expect(find.text('Берут на себя: Anna и Xenia'), findsOneWidget);
        expect(find.byType(TenturaAvatar), findsNWidgets(2));
      });
    }

    for (final baton in solo) {
      final role = baton.runtimeType.toString();
      testWidgets('$role without a co-taker keeps the solo line', (
        tester,
      ) async {
        await tester.pumpWidget(_card(baton));
        await tester.pump();

        expect(find.text('Anna took it.'), findsOneWidget);
        expect(find.textContaining('Xenia'), findsNothing);
        expect(find.byType(TenturaAvatar), findsOneWidget);
        expect(_avatarNames(tester), ['Anna']);
      });
    }
  });

  group('room screen fed by a recorded response', () {
    testWidgets('a marker-12 row with coTakerUserId reads «A and X took it: '
        'ask»', (tester) async {
      await usePhoneSurface(tester);
      await GetIt.I.reset();
      addTearDown(GetIt.I.reset);
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      GetIt.I
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        );
      final wire = _wireRepository(_RoomLink());
      final fake =
          _WireBackedRoomFake(userId: kRoomCubitFakeMyUserId, wireRepo: wire)
            ..participants = [
              _participant(kRoomCubitFakeMyUserId, 'Viewer'),
              _participant('Uaaaaaaaaaaa', 'Anna'),
              _participant('Uxxxxxxxxxxx', 'Xenia'),
            ];
      late RoomCubit cubit;
      await tester.runAsync(() async {
        cubit = roomCubitForTest(fake);
        await awaitRoomCubitLoad(cubit).timeout(const Duration(seconds: 5));
        cubit.syncBeaconStatus(BeaconStatus.open);
      });
      addTearDown(() => tester.runAsync(cubit.close));
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RoomCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(
              value: RoomBodyHarnessProfileCubit(
                const Profile(
                  id: kRoomCubitFakeMyUserId,
                  displayName: 'Viewer',
                ),
              ),
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

      expect(
        find.text('Anna and Xenia took it: Carry the boxes'),
        findsOneWidget,
      );
    });
  });
}

Map<String, dynamic> _row({
  required String id,
  required String body,
  required String createdAt,
  int? semanticMarker,
  String? systemPayloadJson,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': 'Bbeacon0000001',
  'authorId': kRoomCubitFakeMyUserId,
  'body': body,
  'createdAt': createdAt,
  'editedAt': null,
  'semanticMarker': semanticMarker,
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
  'batonDataJson': null,
  'systemPayloadJson': systemPayloadJson,
  'authorTitle': 'Viewer',
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

class _RoomLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(
        Response(
          data: {
            '__typename': 'query_root',
            'RoomMessageList': [
              _row(
                id: 'Mask00000001',
                body: 'Carry the boxes',
                createdAt: '2026-10-05T10:00:00.000Z',
              ),
              _row(
                id: 'Mother0000001',
                body: 'See you at nine',
                createdAt: '2026-10-05T10:30:00.000Z',
              ),
              _row(
                id: 'Mtaken0000001',
                body: '',
                createdAt: '2026-10-05T11:00:00.000Z',
                semanticMarker: BeaconRoomSemanticMarker.batonTaken,
                systemPayloadJson: jsonEncode({
                  'batonId': 'Zbaton000001',
                  'sourceMessageId': 'Mask00000001',
                  'takerUserId': 'Uaaaaaaaaaaa',
                  'coTakerUserId': 'Uxxxxxxxxxxx',
                }),
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

BeaconThreadsRepository _wireRepository(Link link) {
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
}
