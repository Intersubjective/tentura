import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/util/beacon_pinned_facts.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_status_change.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

import '../../support/phone_surface.dart';
import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
final _createdAt = DateTime.utc(2026, 7, 1, 10);

const _blockerTitle = 'Waiting on parts delivery';

RoomState _roomWithBlocker({List<RoomMessage> messages = const []}) =>
    RoomState(
      beaconId: 'b915',
      myUserId: _viewer.id,
      messages: messages,
      roomState: BeaconRoomState(
        beaconId: 'b915',
        updatedAt: _createdAt,
        openBlockerTitle: _blockerTitle,
      ),
      openCoordinationBlocker: CoordinationItem(
        id: 'blocker-1',
        beaconId: 'b915',
        creatorId: 'author',
        title: _blockerTitle,
        kind: CoordinationItemKind.blocker,
        status: CoordinationItemStatus.open,
        createdAt: _createdAt,
        updatedAt: _createdAt,
      ),
    );

RoomMessage _statusLine({
  required String id,
  required int from,
  required int to,
  required String reason,
}) => RoomMessage(
  id: id,
  beaconId: 'b915',
  authorId: 'author',
  author: const Profile(id: 'author', displayName: 'Alice'),
  body: '',
  createdAt: _createdAt,
  systemMessageKind: 7,
  systemPayloadJson:
      '{"version":1,"fromStatus":$from,"toStatus":$to,"reason":"$reason"}',
);

Future<void> _pumpRoom(
  WidgetTester tester, {
  required RoomState roomState,
  bool? closureHadNoFinalCheck,
  Size viewport = const Size(800, 600),
}) async {
  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpBeaconRoomBody(
    tester,
    roomState: roomState,
    width: viewport.width,
    height: viewport.height,
    locale: const Locale('ru'),
    closureHadNoFinalCheck: closureHadNoFinalCheck,
  );
}

void main() {
  testWidgets('Request room pins open blocker HUD at 375×667 RU', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await _pumpRoom(
      tester,
      roomState: _roomWithBlocker(),
      viewport: kPhoneSurface,
    );

    expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
    expect(find.byType(HudLabeledMultiline), findsOneWidget);
    final l10n = L10n.of(tester.element(find.byType(HudLabeledMultiline)))!;
    expect(
      find.textContaining(l10n.beaconHudNowBlocked(_blockerTitle)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Request room pins open blocker HUD at desktop width', (
    tester,
  ) async {
    await _pumpRoom(
      tester,
      roomState: _roomWithBlocker(),
      viewport: const Size(1280, 800),
    );

    expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
    expect(find.byType(HudLabeledMultiline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('shared pinned-facts helpers stay available to the room', () {
    const factText = 'Код от ворот — 4821';
    final fact = BeaconFactCard(
      id: 'fact-915',
      beaconId: 'b915',
      factText: factText,
      visibility: 0,
      pinnedBy: _viewer.id,
      createdAt: _createdAt,
      status: 0,
    );
    expect(activePinnedFacts([fact]), hasLength(1));
    expect(
      pinFactTextForPin(
        body: factText,
        attachmentCount: 0,
        attachmentFileNames: const [],
        attachmentFallback: 'attachments',
      ),
      factText,
    );
  });

  group('#825 closureHadNoFinalCheck on BeaconRoomBody', () {
    final lifecycleMessages = [
      _statusLine(
        id: 'open',
        from: 8,
        to: 5,
        reason: 'closureOpened',
      ),
      _statusLine(
        id: 'close',
        from: 5,
        to: 6,
        reason: 'authorCloseNow',
      ),
    ];

    testWidgets('true hides the skipped Final check status line', (
      tester,
    ) async {
      await _pumpRoom(
        tester,
        roomState: _roomWithBlocker(messages: lifecycleMessages),
        closureHadNoFinalCheck: true,
      );

      expect(find.byType(RoomMessageTile), findsOneWidget);
      expect(
        omitSkippedFinalCheckStatusLines(lifecycleMessages),
        hasLength(1),
      );
    });

    testWidgets('null keeps every lifecycle line', (tester) async {
      await _pumpRoom(
        tester,
        roomState: _roomWithBlocker(messages: lifecycleMessages),
      );

      expect(find.byType(RoomMessageTile), findsNWidgets(2));
    });

    testWidgets('false keeps every lifecycle line', (tester) async {
      await _pumpRoom(
        tester,
        roomState: _roomWithBlocker(messages: lifecycleMessages),
        closureHadNoFinalCheck: false,
      );

      expect(find.byType(RoomMessageTile), findsNWidgets(2));
    });
  });
}
