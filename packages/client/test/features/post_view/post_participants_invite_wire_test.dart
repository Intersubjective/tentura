import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/post_view/ui/widget/post_participants_list.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';

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

const _beaconId = 'Bpostparticipants719';
const _viewerId = 'Uviewer719';
const _inviterName = 'Q71VeryLongInviterNameFromWire';

void main() {
  test('fetchParticipants maps invite attribution from the wire', () async {
    final client = Client(
      link: _FakeLink(
        const Response(
          data: {
            '__typename': 'query_root',
            'BeaconParticipantList': [
              {
                '__typename': 'v2_BeaconParticipantRow',
                'id': 'p-viewer',
                'beaconId': _beaconId,
                'userId': _viewerId,
                'userTitle': 'Viewer',
                'userHandle': null,
                'userHasPicture': false,
                'userPicHeight': 0,
                'userPicWidth': 0,
                'userBlurHash': '',
                'userImageId': '',
                'role': BeaconParticipantRoleBits.addressee,
                'status': 0,
                'roomAccess': RoomAccessBits.admitted,
                'offerNote': null,
                'nextMoveText': null,
                'nextMoveStatus': null,
                'nextMoveSource': null,
                'linkedMessageId': null,
                'lastSeenRoomAt': '2026-11-01T10:00:00.000Z',
                'opened': true,
                'helpType': null,
                'roleLabel': null,
                'broughtById': null,
                'broughtBy': null,
                'broughtHow': null,
                'createdAt': '2026-11-01T10:00:00.000Z',
                'updatedAt': '2026-11-01T10:00:00.000Z',
              },
              {
                '__typename': 'v2_BeaconParticipantRow',
                'id': 'p-invitee',
                'beaconId': _beaconId,
                'userId': 'Uinvitee',
                'userTitle': 'Invitee',
                'userHandle': null,
                'userHasPicture': false,
                'userPicHeight': 0,
                'userPicWidth': 0,
                'userBlurHash': '',
                'userImageId': '',
                'role': BeaconParticipantRoleBits.addressee,
                'status': 0,
                'roomAccess': RoomAccessBits.admitted,
                'offerNote': null,
                'nextMoveText': null,
                'nextMoveStatus': null,
                'nextMoveSource': null,
                'linkedMessageId': null,
                'lastSeenRoomAt': '2026-11-01T10:00:00.000Z',
                'opened': true,
                'helpType': null,
                'roleLabel': null,
                'broughtById': 'Uinviter',
                'broughtBy': {
                  '__typename': 'v2_ProfileSummary',
                  'userId': 'Uinviter',
                  'displayName': _inviterName,
                },
                'broughtHow': BeaconParticipantBroughtHow.invite,
                'createdAt': '2026-11-01T10:00:00.000Z',
                'updatedAt': '2026-11-01T10:00:00.000Z',
              },
            ],
          },
          response: {},
        ),
      ),
      defaultFetchPolicies: const {OperationType.query: FetchPolicy.NoCache},
    );
    final realtime = buildTestRealtimeSync();
    addTearDown(realtime.port.dispose);
    final repo = BeaconThreadsRepository(
      _StubRemoteApiClient(client),
      realtime.port,
    );

    final rows = await repo.fetchParticipants(_beaconId);

    final invitee = rows.singleWhere((p) => p.userId == 'Uinvitee');
    expect(invitee.broughtByName, _inviterName);
    expect(invitee.broughtHow, BeaconParticipantBroughtHow.invite);
  });

  testWidgets('375×667 RU: wire-mapped invite note renders in full', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final createdAt = DateTime.utc(2026, 11);
    final participants = [
      BeaconParticipant(
        id: 'p-viewer',
        beaconId: _beaconId,
        userId: _viewerId,
        userTitle: 'Viewer',
        role: BeaconParticipantRoleBits.addressee,
        status: 0,
        roomAccess: RoomAccessBits.admitted,
        createdAt: createdAt,
        updatedAt: createdAt,
        lastSeenRoomAt: createdAt,
        opened: true,
      ),
      BeaconParticipant(
        id: 'p-invitee',
        beaconId: _beaconId,
        userId: 'Uinvitee',
        userTitle: 'Катя',
        role: BeaconParticipantRoleBits.addressee,
        status: 0,
        roomAccess: RoomAccessBits.admitted,
        createdAt: createdAt,
        updatedAt: createdAt,
        lastSeenRoomAt: createdAt,
        opened: true,
        broughtByName: _inviterName,
        broughtHow: BeaconParticipantBroughtHow.invite,
      ),
    ];
    final l10n = lookupL10n(const Locale('ru'));
    final note = l10n.postParticipantInvitedBy(_inviterName);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: PostParticipantsList(
                viewerId: _viewerId,
                participants: participants,
                forwardEdges: const [],
                onForwardsGraph: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(note), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _arrivalNotesMatrix();
}

void _noop() {}

/// A `BeaconParticipantList` wire row on the arrival-attribution Post.
Map<String, dynamic> _arrivalRow({
  required String userId,
  required String title,
  int role = BeaconParticipantRoleBits.addressee,
  String? broughtById,
  String? broughtByName,
  String? broughtHow,
}) => {
  '__typename': 'v2_BeaconParticipantRow',
  'id': 'p-$userId',
  'beaconId': _beaconId,
  'userId': userId,
  'userTitle': title,
  'userHandle': null,
  'userHasPicture': false,
  'userPicHeight': 0,
  'userPicWidth': 0,
  'userBlurHash': '',
  'userImageId': '',
  'role': role,
  'status': 0,
  'roomAccess': RoomAccessBits.admitted,
  'offerNote': null,
  'nextMoveText': null,
  'nextMoveStatus': null,
  'nextMoveSource': null,
  'linkedMessageId': null,
  'lastSeenRoomAt': '2026-11-01T10:00:00.000Z',
  'opened': true,
  'helpType': null,
  'roleLabel': null,
  'broughtById': broughtById,
  'broughtBy': broughtById == null
      ? null
      : {
          '__typename': 'v2_ProfileSummary',
          'userId': broughtById,
          'displayName': broughtByName,
        },
  'broughtHow': broughtHow,
  'createdAt': '2026-11-01T10:00:00.000Z',
  'updatedAt': '2026-11-01T10:00:00.000Z',
};

/// Reads the Post's members as the server reports them: Dave joined through
/// Alice's Post invite (an account he had before), Carol through Bob's
/// forward.
Future<List<BeaconParticipant>> _fetchArrivals() async {
  final client = Client(
    link: _FakeLink(
      Response(
        data: {
          '__typename': 'query_root',
          'BeaconParticipantList': [
            _arrivalRow(userId: _viewerId, title: 'Viewer'),
            _arrivalRow(
              userId: 'Ualice',
              title: 'Alice',
              role: BeaconParticipantRoleBits.author,
            ),
            _arrivalRow(
              userId: 'Udave',
              title: 'Dave',
              broughtById: 'Ualice',
              broughtByName: 'Alice',
              broughtHow: BeaconParticipantBroughtHow.invite,
            ),
            _arrivalRow(
              userId: 'Ucarol',
              title: 'Carol',
              broughtById: 'Ubob',
              broughtByName: 'Bob',
              broughtHow: BeaconParticipantBroughtHow.forward,
            ),
          ],
        },
        response: const {},
      ),
    ),
    defaultFetchPolicies: const {OperationType.query: FetchPolicy.NoCache},
  );
  final realtime = buildTestRealtimeSync();
  try {
    return await BeaconThreadsRepository(
      _StubRemoteApiClient(client),
      realtime.port,
    ).fetchParticipants(_beaconId);
  } finally {
    await realtime.port.dispose();
  }
}

void _arrivalNotesMatrix() {
  group('Participants sheet arrival notes from the wire', () {
    for (final sample in [
      (
        locale: const Locale('en'),
        size: const Size(1280, 800),
        invited: 'invited by Alice',
        forwarded: 'via Bob',
      ),
      (
        locale: const Locale('ru'),
        size: kPhoneSurface,
        invited: 'приглашён(а) Alice',
        forwarded: 'через Bob',
      ),
    ]) {
      testWidgets(
        'an invited member reads «${sample.invited}» and a forwarded one '
        '«${sample.forwarded}» '
        '(${sample.locale.languageCode} '
        '${sample.size.width.toInt()}×${sample.size.height.toInt()})',
        (tester) async {
          final members = (await tester.runAsync(_fetchArrivals))!;
          await tester.binding.setSurfaceSize(sample.size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: sample.locale,
              home: TenturaResponsiveScope(
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: PostParticipantsList(
                      viewerId: _viewerId,
                      participants: members,
                      forwardEdges: const [],
                      onForwardsGraph: _noop,
                      peopleTagsEnabled: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          for (final note in [sample.invited, sample.forwarded]) {
            final shown = find.text(note);
            expect(shown, findsOneWidget, reason: note);
            expect(
              tester.renderObject<RenderParagraph>(shown).didExceedMaxLines,
              isFalse,
              reason: '«$note» is readable in full',
            );
          }
          final l10n = lookupL10n(sample.locale);
          expect(find.text(l10n.postParticipantVia('Alice')), findsNothing);
          expect(find.text(l10n.postParticipantInvitedBy('Bob')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
