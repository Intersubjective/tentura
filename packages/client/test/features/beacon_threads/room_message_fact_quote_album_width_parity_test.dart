// A quoted fact's photo album in a short-text quoting message is as wide and
// as tall as the album of a direct album message with the same photos, with
// the same arrow placement, on a phone and on a desktop surface, in EN and RU.

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

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/design_system/components/room_message_bubble_shape.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../support/test_realtime_sync.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Me'),
  );

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

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
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

Map<String, dynamic> _roomMessageRow({
  required String id,
  required String createdAt,
  String body = 'ok',
  String attachmentsJson = '[]',
  Map<String, dynamic>? quotedFact,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': 'Bbeacon0000001',
  'authorId': 'Uauthor000001',
  'body': body,
  'createdAt': createdAt,
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
  'attachmentsJson': attachmentsJson,
  'mentions': <String>[],
  'mentionSpansJson': '[]',
  'replyToAuthorId': null,
  'replyToAuthorTitle': null,
  'replyToBodyExcerpt': null,
  'replyToHasAttachments': false,
  'replyToMessageId': null,
  'threadItemId': null,
  'quotedFact': quotedFact,
};

List<RoomMessageAttachment> _images(int n, String prefix) => [
  for (var i = 0; i < n; i++)
    RoomMessageAttachment(
      id: '$prefix$i',
      kind: BeaconRoomMessageAttachmentKind.image,
      position: i,
      mime: 'image/jpeg',
      sizeBytes: 1,
      imageId: '$prefix-img-$i',
      imageAuthorId: 'u1',
    ),
];

RoomMessage _direct(int n) => RoomMessage(
  id: 'm-direct',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: 'ok',
  createdAt: DateTime.utc(2026),
  attachments: _images(n, 'd'),
);

RoomMessage _quoting(int n) => RoomMessage(
  id: 'm-quote',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: 'ok',
  createdAt: DateTime.utc(2026),
  quotedFact: QuotedFact(
    factCardId: 'fact-1',
    seq: 1,
    currentSeq: 1,
    status: BeaconFactCardStatusBits.active,
    factText: 'The venue moved to 221B Baker Street',
    pinnedById: 'peer-1',
    pinnedByTitle: 'Peer One',
    attachments: _images(n, 'q'),
  ),
);

Future<void> _pumpTile(
  WidgetTester tester,
  Size size,
  RoomMessage message, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: RoomMessageTile(
                message: message,
                myProfile: const Profile(id: 'viewer', displayName: 'Me'),
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder get _quoteAlbum => find.descendant(
  of: find.byType(RoomMessageFactQuote),
  matching: find.byType(RoomMessageInlineImageAlbum),
);

/// The message bubble: the Material carrying the bubble shape around the
/// quote.
Finder get _bubble => find.ancestor(
  of: find.byType(RoomMessageFactQuote),
  matching: find.byWidgetPredicate(
    (w) => w is Material && w.shape is RoomMessageBubbleShape,
  ),
);

/// The previous / next arrow buttons of an album, by role: its IconButtons in
/// document order (previous first, next last), whatever glyph they show.
Finder _arrows(Finder album) =>
    find.descendant(of: album, matching: find.byType(IconButton));

void _expectNear(double actual, double expected, String what) =>
    expect(actual, closeTo(expected, 1), reason: what);

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(
      _FakePlatformRepository(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  final sizes = [
    ('phone 375x667', const Size(375, 667)),
    ('desktop 1280x800', const Size(1280, 800)),
  ];
  final locales = [
    ('EN', const Locale('en')),
    ('RU', const Locale('ru')),
  ];

  group('quoted fact album in a short-text bubble matches a direct album', () {
    for (final (sizeName, size) in sizes) {
      for (final (localeName, locale) in locales) {
        for (final count in [1, 3]) {
          testWidgets(
            'same width and height, $count photo(s), $localeName, $sizeName',
            (tester) async {
              await _pumpTile(tester, size, _direct(count), locale: locale);
              final direct = tester.getRect(
                find.byType(RoomMessageInlineImageAlbum),
              );
              await _pumpTile(tester, size, _quoting(count), locale: locale);
              expect(tester.takeException(), isNull);
              final quoted = tester.getRect(_quoteAlbum);
              _expectNear(quoted.width, direct.width, 'album width');
              _expectNear(quoted.height, direct.height, 'album height');
            },
          );
        }
      }

      testWidgets('quoted arrows sit where the direct arrows sit, $sizeName', (
        tester,
      ) async {
        // Offsets of [previous.topLeft, next.topRight] from the album rect.
        List<Offset> offsets(Finder album) {
          final arrows = _arrows(album);
          expect(arrows, findsNWidgets(2));
          final rect = tester.getRect(album);
          final prev = tester.getRect(arrows.first);
          final next = tester.getRect(arrows.last);
          return [prev.topLeft - rect.topLeft, next.topRight - rect.topRight];
        }

        await _pumpTile(tester, size, _direct(3));
        final direct = offsets(find.byType(RoomMessageInlineImageAlbum));
        await _pumpTile(tester, size, _quoting(3));
        final quoted = offsets(_quoteAlbum);
        for (var i = 0; i < 2; i++) {
          _expectNear(quoted[i].dx, direct[i].dx, 'arrow $i dx');
          _expectNear(quoted[i].dy, direct[i].dy, 'arrow $i dy');
        }
      });

      testWidgets('quoted album stays inside the bubble, $sizeName', (
        tester,
      ) async {
        await _pumpTile(tester, size, _quoting(3));
        expect(tester.takeException(), isNull);
        final bubble = tester.getRect(_bubble.first);
        final album = tester.getRect(_quoteAlbum);
        expect(album.left, greaterThanOrEqualTo(bubble.left));
        expect(album.right, lessThanOrEqualTo(bubble.right));
        expect(album.top, greaterThanOrEqualTo(bubble.top));
        expect(album.bottom, lessThanOrEqualTo(bubble.bottom));
      });
    }

    testWidgets('the quote uses exactly one existing album widget', (
      tester,
    ) async {
      await _pumpTile(tester, const Size(375, 667), _quoting(3));
      expect(_quoteAlbum, findsOneWidget);
    });
  });

  testWidgets('real path: a server-decoded quoted album is same size as a '
      'server-decoded direct album at 375x667', (tester) async {
    String imagesJson(String prefix) => jsonEncode([
      for (var i = 0; i < 3; i++)
        {
          'id': '$prefix$i',
          'kind': BeaconRoomMessageAttachmentKind.image,
          'position': i,
          'mime': 'image/jpeg',
          'sizeBytes': 1,
          'imageId': '$prefix-img-$i',
          'imageAuthorId': 'Uauthor000001',
        },
    ]);
    final repo = _repositoryFor(
      _FakeLink(
        Response(
          data: {
            '__typename': 'query_root',
            'RoomMessageList': [
              _roomMessageRow(
                id: 'Mquote0000001',
                createdAt: '2026-08-14T10:00:00.000Z',
                quotedFact: {
                  '__typename': 'v2_RoomMessageQuotedFact',
                  'factCardId': 'Ffact00000001',
                  'seq': 1,
                  'text': 'Meet at the station at 9',
                  'pinnedById': 'Upinner000001',
                  'pinnedByTitle': 'Bob',
                  'visibility': 1,
                  'status': 1,
                  'currentSeq': 1,
                  'attachmentsJson': imagesJson('q'),
                },
              ),
              _roomMessageRow(
                id: 'Mdirect000001',
                createdAt: '2026-08-14T11:00:00.000Z',
                attachmentsJson: imagesJson('d'),
              ),
            ],
          },
          response: const {},
        ),
      ),
    );
    final messages = (await tester.runAsync(
      () => repo.fetchMessages(beaconId: 'Bbeacon0000001'),
    ))!;
    final quoting = messages.firstWhere((m) => m.id == 'Mquote0000001');
    final direct = messages.firstWhere((m) => m.id == 'Mdirect000001');
    const phone = Size(375, 667);

    await _pumpTile(tester, phone, direct);
    final directRect = tester.getRect(find.byType(RoomMessageInlineImageAlbum));
    await _pumpTile(tester, phone, quoting);
    expect(_quoteAlbum, findsOneWidget);
    final quoted = tester.getRect(_quoteAlbum);
    _expectNear(quoted.width, directRect.width, 'album width');
    _expectNear(quoted.height, directRect.height, 'album height');
  });
}
