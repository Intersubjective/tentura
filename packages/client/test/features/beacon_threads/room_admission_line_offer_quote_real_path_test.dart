// The «You admitted X to the discussion» line quotes what the helper wrote in
// their offer, over the real client stack: the server's GraphQL row (and its
// `entity_changes` frame) enter through the fake transport, cross the real
// RemoteApiService, GraphQL mapper, InvalidationService and
// BeaconThreadsRepository into the room cubit and the widget (only the socket
// and the HTTP transport are faked; see support/room_hint_wire_harness.dart).
//
// The helper offered through «Offer help», so the room's participant list
// carries no offer text for them (BeaconParticipantList reports it empty): the
// quote can only come from the admission line itself. The line is shown to an
// open room without a reload, on a phone (375×667), in Russian.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

const _viewerName = 'Автор';
const _helperId = 'Uhelper000001';
const _helperName = 'Омар Динер';
const _lineId = 'Mjoinedline01';
const _offer = 'Есть машина, свободен с 10 до 12';

final _admittedAt = DateTime.utc(2026, 10, 21, 9);

/// The admission line as the server stores and returns it: the offer text is
/// in the line's own payload (`offerNote`).
Map<String, dynamic> _joinedRow({String? offerNote = _offer}) => {
  ...roomHintWireMessageRow(
    id: _lineId,
    authorId: roomHintWireViewerId,
    authorTitle: _viewerName,
    createdAt: _admittedAt.toIso8601String(),
  ),
  'semanticMarker': BeaconRoomSemanticMarker.participantJoined,
  'systemPayloadJson': jsonEncode({
    'joinedUserId': _helperId,
    'actorUserId': roomHintWireViewerId,
    'admissionReason': 'accept',
    'offerNote': ?offerNote,
  }),
};

BeaconParticipant _admitted(String userId, String title, {int? role}) =>
    BeaconParticipant(
      id: 'p-$userId',
      beaconId: kRoomCubitFakeBeaconId,
      userId: userId,
      userTitle: title,
      role: role ?? BeaconParticipantRoleBits.helper,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      // What BeaconParticipantList returns for an offer made through
      // «Offer help»: no text on the participant row.
    );

/// Lets a pushed frame cross the real stack (InvalidationService batches
/// hints, the room coalesces refetches for one [BurstCoalescer.window]) and
/// the refetch over the fake transport finish, then rebuilds.
Future<void> _settleWire(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(
      BurstCoalescer.window + const Duration(milliseconds: 600),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('The admission line quotes the helper’s offer in an open room', () {
    final l10n = L10nRu();
    final line = l10n.beaconRoomParticipantJoinedBySelf(_helperName);
    final quote = l10n.beaconRoomParticipantJoinedOfferQuote(_offer);

    late RoomHintWireServer server;
    late RoomHintWire wire;

    Future<void> openRoom(WidgetTester tester) async {
      await usePhoneSurface(tester);
      await GetIt.I.reset();
      addTearDown(GetIt.I.reset);
      registerRoomCubitProfileCubit(roomHintWireViewerId);
      GetIt.I
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        );

      wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
      addTearDown(() => tester.runAsync(wire.close));

      final repo = RoomOverRealHintWireRepository(wire.repository)
        ..participants = [
          _admitted(
            roomHintWireViewerId,
            _viewerName,
            role: BeaconParticipantRoleBits.author,
          ),
          _admitted(_helperId, _helperName),
        ];
      late RoomCubit cubit;
      await tester.runAsync(() async {
        cubit = roomCubitForTest(
          repo,
          effects: FakeUiEffectPort(),
          realtimeSyncCase: RealtimeSyncCase(wire.realtime),
        );
        await awaitRoomCubitLoad(cubit);
        cubit.syncBeaconStatus(BeaconStatus.open);
      });
      addTearDown(() => tester.runAsync(cubit.close));

      const viewer = Profile(
        id: roomHintWireViewerId,
        displayName: _viewerName,
      );
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RoomCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(
              value: RoomBodyHarnessProfileCubit(viewer),
            ),
            BlocProvider<PresenceCubit>.value(
              value: RoomBodyHarnessPresenceCubit(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const TenturaResponsiveScope(
              child: Scaffold(body: BeaconRoomBody(enableComposer: false)),
            ),
          ),
        ),
      );
      await _settleWire(tester);
    }

    /// What the server sends the open room when a message is inserted:
    /// `{entity: room_message, id: <request id>, message_id, [message: paint]}`
    /// (websocket_path_entity_changes.dart).
    void pushJoinedLineInserted({Object? paint}) => wire.socket.frames.add(
      jsonEncode({
        'type': 'subscription',
        'path': 'entity_changes',
        'payload': {
          'entity': 'room_message',
          'id': kRoomCubitFakeBeaconId,
          'event': 'insert',
          'actor_user_id': roomHintWireViewerId,
          'message_id': _lineId,
          'message': ?paint,
        },
      }),
    );

    void expectLineWithQuoteOnPhone(WidgetTester tester) {
      final lineFinder = find.text(line);
      final quoteFinder = find.text(quote);
      expect(lineFinder, findsOneWidget, reason: 'the admission line');
      expect(
        quoteFinder,
        findsOneWidget,
        reason: 'the helper’s offer, quoted from the line',
      );
      expect(
        tester.getTopLeft(quoteFinder).dy,
        greaterThan(tester.getBottomLeft(lineFinder).dy),
        reason: 'the quote sits under the line',
      );
      expect(tester.getRect(quoteFinder).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(quoteFinder).right, lessThanOrEqualTo(375));
    }

    setUp(() => server = RoomHintWireServer());

    testWidgets(
      'a room opened after the admission shows the offer text the server '
      'stored in the line',
      (tester) async {
        server.messageRows = [_joinedRow()];

        await openRoom(tester);

        expectLineWithQuoteOnPhone(tester);
      },
    );

    testWidgets(
      'the line the server announces with a bare hint arrives with its quote '
      'and no reload',
      (tester) async {
        server.messageRows = [];
        await openRoom(tester);
        expect(find.text(line), findsNothing);

        // The author admits the helper: the server stores the line with the
        // snapshot, then tells everyone with the room open.
        server.messageRows = [_joinedRow()];
        final listQueriesBefore = server.queried
            .where((q) => q == 'RoomMessageList')
            .length;
        await tester.runAsync(() async => pushJoinedLineInserted());
        await _settleWire(tester);

        expect(
          server.queried.where((q) => q == 'RoomMessageList').length,
          greaterThan(listQueriesBefore),
          reason: 'a hint without a paint must refetch the chat',
        );
        expectLineWithQuoteOnPhone(tester);
      },
    );

    testWidgets(
      'the line the server paints into the frame arrives with its quote '
      'and no reload',
      (tester) async {
        server.messageRows = [];
        await openRoom(tester);
        expect(find.text(line), findsNothing);

        server.messageRows = [_joinedRow()];
        await tester.runAsync(
          () async => pushJoinedLineInserted(
            paint: {
              'id': _lineId,
              'beaconId': kRoomCubitFakeBeaconId,
              'authorId': roomHintWireViewerId,
              'body': '',
              'createdAt': _admittedAt.toIso8601String(),
              'editedAt': null,
              'mentions': <String>[],
              'mentionSpans': <Object>[],
              'threadItemId': null,
              'replyToMessageId': null,
              'replyToAuthorId': null,
              'replyToAuthorTitle': null,
              'replyToBodyExcerpt': null,
              'replyToHasAttachments': false,
              'semanticMarker': BeaconRoomSemanticMarker.participantJoined,
              'systemPayload': {
                'joinedUserId': _helperId,
                'actorUserId': roomHintWireViewerId,
                'admissionReason': 'accept',
                'offerNote': _offer,
              },
              'systemMessageKind': null,
              'quotedFact': null,
            },
          ),
        );
        await _settleWire(tester);

        expectLineWithQuoteOnPhone(tester);
      },
    );

    testWidgets(
      'a line stored without a snapshot shows no quote',
      (tester) async {
        server.messageRows = [_joinedRow(offerNote: null)];

        await openRoom(tester);

        expect(find.text(line), findsOneWidget);
        expect(find.textContaining('«'), findsNothing);
      },
    );
  });
}
