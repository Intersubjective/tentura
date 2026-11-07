import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
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
}

void _noop() {}
