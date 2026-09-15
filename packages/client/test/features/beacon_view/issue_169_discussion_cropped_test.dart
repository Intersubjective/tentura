import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/components/tentura_vertical_resize_handle.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart';
import 'beacon_view_screen_harness.dart';

const _kFormalRequestTitle = 'Structured parent request title';
const _kSnippetMessage = 'Не факт!';
const _kLongMessage =
    'Full discussion paragraph that must remain visible end-to-end without viewport clipping.';

BeaconViewState _issue169BeaconState() {
  final base = beaconViewHarnessAuthorState();
  return base.copyWith(
    beacon: base.beacon.copyWith(title: _kFormalRequestTitle),
  );
}

class _Issue169HostBundle {
  _Issue169HostBundle({required this.host, required this.roomCubits});

  final ThreadHostCubit host;
  final List<RoomCubit> roomCubits;
}

_Issue169HostBundle _issue169Host(FakeBeaconThreadsRepository repo) {
  final roomCubits = <RoomCubit>[];
  final host = ThreadHostCubit(
    beaconId: kBeaconViewHarnessBeaconId,
    roomCubitFactory: ({
      required String beaconId,
      String? threadItemId,
      DateTime? initialUnreadAnchorAt,
    }) {
      final cubit = RoomCubit(
        beaconId: beaconId,
        threadItemId: threadItemId,
        initialUnreadAnchorAt: initialUnreadAnchorAt,
        beaconRoomCase: roomCubitMakeCase(repo),
        coordinationItemRoomSync: CoordinationItemRoomSync(),
        presenceRepository: roomCubitFakePresenceRepository(),
        effects: FakeUiEffectPort(),
      );
      roomCubits.add(cubit);
      unawaited(cubit.load());
      return cubit;
    },
  );
  return _Issue169HostBundle(host: host, roomCubits: roomCubits);
}

Future<void> _waitForExpandedDiscussion(
  WidgetTester tester,
  List<RoomCubit> roomCubits,
) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final splitReady =
        find.byType(TenturaVerticalResizeHandle).evaluate().isNotEmpty &&
        find.byType(ThreadDetail).evaluate().isNotEmpty &&
        find.byType(BasicChatBody).evaluate().isNotEmpty;
    final messagesReady = roomCubits.isNotEmpty &&
        roomCubits.first.state.messages.length >= 2;
    if (splitReady && messagesReady) {
      return;
    }
  }
  fail('Expanded split discussion did not load seeded messages');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  testWidgets(
    'issue #169 discussion header and messages fit the visible pane',
    (tester) async {
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kBeaconViewHarnessAuthorId,
      );
      final author = Profile(
        id: kBeaconViewHarnessAuthorId,
        displayName: 'Author',
      );
      fakeRoom.messages = [
        RoomMessage(
          id: 'm-snippet',
          beaconId: kBeaconViewHarnessBeaconId,
          authorId: kBeaconViewHarnessAuthorId,
          body: _kSnippetMessage,
          createdAt: kBeaconViewHarnessNow,
          author: author,
        ),
        RoomMessage(
          id: 'm-long',
          beaconId: kBeaconViewHarnessBeaconId,
          authorId: kBeaconViewHarnessAuthorId,
          body: _kLongMessage,
          createdAt: kBeaconViewHarnessNow.add(const Duration(minutes: 1)),
          author: author,
        ),
      ];

      registerRoomCubitProfileCubit(kBeaconViewHarnessAuthorId);
      await registerBeaconViewHarnessGetIt(roomRepo: fakeRoom);

      final hostBundle = _issue169Host(fakeRoom);
      addTearDown(() async {
        for (final cubit in hostBundle.roomCubits) {
          await cubit.close();
        }
      });

      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessExpanded,
        beaconState: _issue169BeaconState(),
        threadsState: beaconViewHarnessThreadsState(),
        host: hostBundle.host,
      );

      await _waitForExpandedDiscussion(tester, hostBundle.roomCubits);
      await pumpUntilViewportDone(tester);

      // Acceptance (#169): formal request title in discussion chrome — not a
      // message snippet standing in for the title.
      expect(find.text(_kFormalRequestTitle), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(_kSnippetMessage),
        ),
        findsNothing,
      );

      final discussionHeader = tester.getRect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(ThreadDetailGeneralTitle),
        ),
      );
      final discussionPane = tester.getRect(find.byType(ThreadDetail));
      final appBar = tester.getRect(find.byType(AppBar));

      // Header chrome must align with the discussion pane below (split widths
      // are computed from the same budget).
      expect(
        discussionHeader.left,
        closeTo(discussionPane.left, 1),
        reason: 'discussion header must start at the pane edge',
      );
      expect(
        discussionHeader.width,
        closeTo(discussionPane.width, 1),
        reason: 'discussion header width must match the pane',
      );

      // Two-line discussion title must not clip inside the app bar viewport.
      expect(
        discussionHeader.bottom,
        lessThanOrEqualTo(appBar.bottom + 0.5),
        reason: 'discussion header must fit inside the app bar height',
      );

      final chatViewport = tester.getRect(find.byType(BasicChatBody));
      final chatBody = tester.state<BasicChatBodyState>(
        find.byType(BasicChatBody),
      );
      const seededMessages = <String, String>{
        'm-snippet': _kSnippetMessage,
        'm-long': _kLongMessage,
      };
      for (final entry in seededMessages.entries) {
        expect(
          await chatBody.scrollToMessage(entry.key),
          isTrue,
          reason: '${entry.key} must scroll into the discussion viewport',
        );
        await tester.pump(const Duration(milliseconds: 320));

        final messageTile = find.byWidgetPredicate(
          (widget) =>
              widget is RoomMessageTile && widget.message.id == entry.key,
        );
        expect(
          messageTile,
          findsOneWidget,
          reason: 'seeded message tile must be on screen in the discussion',
        );
        final messageBody = find.descendant(
          of: messageTile,
          matching: find.textContaining(
            entry.value.length > 48
                ? entry.value.substring(0, 48)
                : entry.value,
            skipOffstage: false,
          ),
        );
        expect(
          messageBody,
          findsWidgets,
          reason: 'message body text must be built inside the on-screen tile',
        );
        final messageRect = tester.getRect(messageBody.at(0));
        expect(
          messageRect.left,
          greaterThanOrEqualTo(chatViewport.left - 0.5),
          reason: '${entry.value} must not clip on the left',
        );
        expect(
          messageRect.right,
          lessThanOrEqualTo(chatViewport.right + 0.5),
          reason: '${entry.value} must not clip on the right',
        );
        expect(
          messageRect.bottom,
          lessThanOrEqualTo(chatViewport.bottom + 0.5),
          reason: '${entry.value} must not clip at the bottom',
        );
      }
    },
  );
}
