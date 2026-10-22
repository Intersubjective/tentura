// #415: in the request room on a wide window (1280x800, tab=now: chat on
// the left, the Now pane on the right) Tab wandered between the two panes in
// screen-row order — the Now pane's tabs and cards came before the chat's
// messages and composer, and every message was two stops (bubble, then its
// selectable text). After 28 presses the composer had not been reached.
//
// Spec, walking one Tab cycle from «Skip to content» (#500):
// - the rail comes once, right after Skip, as one run;
// - then the screen in visual order: the header row, then the chat pane
//   (its messages, then the composer), then the Now pane — no Now-pane stop
//   before the chat pane is done, no chat-pane stop after the Now pane began;
// - each chat message is exactly one stop;
// - no control is a stop twice: no focus node is visited twice in the cycle,
//   and no stop is followed by a stop nested inside it (or around it) — the
//   issue's "Back x2 / pinned fact x2 / Details x2 / NEXT x4" class;
// - the composer is reachable within a handful of presses after the rail.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/components/tentura_vertical_resize_handle.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/a11y_focus.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart';
import 'beacon_view_screen_harness.dart';

const _kFirstMessage = 'Ladder is in the garage';
const _kSecondMessage = 'I can bring it on Saturday morning';

/// A real room cubit per thread, loading [repo]'s messages.
(ThreadHostCubit, List<RoomCubit>) _host(FakeBeaconThreadsRepository repo) {
  final roomCubits = <RoomCubit>[];
  final host = ThreadHostCubit(
    beaconId: kBeaconViewHarnessBeaconId,
    roomCubitFactory:
        ({
          required String beaconId,
          String? threadItemId,
          DateTime? initialUnreadAnchorAt,
          RoomCapabilities? capabilities,
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
  return (host, roomCubits);
}

Future<void> _waitForSplitRoom(
  WidgetTester tester,
  List<RoomCubit> roomCubits,
) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final splitReady =
        find.byType(TenturaVerticalResizeHandle).evaluate().isNotEmpty &&
        find.byType(ThreadDetail).evaluate().isNotEmpty &&
        find.byType(BasicChatBody).evaluate().isNotEmpty;
    final messagesReady =
        roomCubits.isNotEmpty && roomCubits.first.state.messages.length >= 2;
    if (splitReady && messagesReady) return;
  }
  fail('the chat|Now split did not load the seeded messages');
}

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// One focus stop: where it is, and which chat message (if any) holds it.
class _Stop {
  _Stop(this.where, this.tile, this.label, [this.node]);

  final String where;
  final Element? tile;
  final String label;
  final FocusNode? node;

  @override
  String toString() => '$where:$label';
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
    '#415 room 1280x800: rail once, header, chat to composer, then Now',
    (tester) async {
      final repo = FakeBeaconThreadsRepository(
        userId: kBeaconViewHarnessAuthorId,
      );
      const author = Profile(id: kBeaconViewHarnessAuthorId, displayName: 'A');
      repo.messages = [
        RoomMessage(
          id: 'm-1',
          beaconId: kBeaconViewHarnessBeaconId,
          authorId: kBeaconViewHarnessAuthorId,
          body: _kFirstMessage,
          createdAt: kBeaconViewHarnessNow,
          author: author,
        ),
        RoomMessage(
          id: 'm-2',
          beaconId: kBeaconViewHarnessBeaconId,
          authorId: kBeaconViewHarnessAuthorId,
          body: _kSecondMessage,
          createdAt: kBeaconViewHarnessNow.add(const Duration(minutes: 1)),
          author: author,
        ),
      ];
      registerRoomCubitProfileCubit(kBeaconViewHarnessAuthorId);
      await registerBeaconViewHarnessGetIt(roomRepo: repo);
      final (host, roomCubits) = _host(repo);
      // pumpBeaconViewHarness skips BeaconViewScope, which in the app syncs
      // the beacon status into the host; without it the room is read-only
      // and the composer is disabled (not a Tab stop).
      host.syncBeaconStatus(
        BeaconStatus.open,
        authorId: kBeaconViewHarnessAuthorId,
      );
      addTearDown(() async {
        for (final cubit in roomCubits) {
          await cubit.close();
        }
      });

      await pumpBeaconViewHarness(
        tester,
        size: const Size(1280, 800),
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        host: host,
        viewTab: 'now',
      );
      await _waitForSplitRoom(tester, roomCubits);
      await pumpUntilViewportDone(tester);

      final rail = tester.getRect(find.byType(NavigationRail));
      final handle = tester.getRect(find.byType(TenturaVerticalResizeHandle));
      // The room's own app bar: the Now pane has a Scaffold of its own, so
      // pick the AppBar that starts left of the chat|Now handle.
      final appBar = find
          .byType(AppBar)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .where((r) => r.left < handle.left)
          .reduce((a, b) => a.top <= b.top ? a : b);
      final tiles = find.byType(RoomMessageTile).evaluate().toList();
      expect(tiles, hasLength(2), reason: 'precondition: two messages shown');
      final composer = tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(TestIds.key(TestIds.roomMessageInput)),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      final skip = Focus.of(tester.element(find.text('Skip to content')));

      Element? tileOf(Element focused) {
        Element? hit;
        if (tiles.contains(focused)) return focused;
        focused.visitAncestorElements((e) {
          if (tiles.contains(e)) hit = e;
          return hit == null;
        });
        return hit;
      }

      _Stop stopNow() {
        final focus = FocusManager.instance.primaryFocus;
        final context = focus?.context;
        if (focus == null || context is! Element) {
          return _Stop('none', null, '');
        }
        final label = '${focus.debugLabel ?? context.widget.runtimeType}';
        if (identical(focus, skip)) return _Stop('skip', null, label);
        if (identical(focus, composer)) return _Stop('composer', null, label);
        final c = focus.rect.center;
        _Stop at(String where, [Element? tile]) =>
            _Stop(where, tile, label, focus);
        if (rail.contains(c)) return at('rail');
        if (c.dy < appBar.bottom) return at('header');
        if (c.dx < handle.left) return at('chat', tileOf(context));
        if (c.dx > handle.right) return at('now');
        return at('other');
      }

      // Start on Skip to content (the first Tab stop since #500), then walk
      // one full cycle: until Skip comes round again.
      skip.requestFocus();
      await tester.pump();
      expect(stopNow().where, 'skip', reason: 'precondition: on Skip');
      final stops = <_Stop>[stopNow()];
      for (var i = 0; i < 80; i++) {
        await _tab(tester);
        final stop = stopNow();
        if (stop.where == 'skip') break;
        stops.add(stop);
      }
      final where = [for (final s in stops) s.where];

      // No control is a stop twice. (a) No focus node comes round twice in
      // one cycle.
      final nodes = [for (final s in stops) s.node];
      for (var i = 0; i < stops.length; i++) {
        final n = nodes[i];
        if (n == null) continue;
        expect(
          nodes.indexOf(n),
          i,
          reason: 'stop $i (${stops[i]}) was already visited: $stops',
        );
      }
      // (b) No stop is directly followed by a stop nested inside it, or by
      // the control around it: that is one control taking two presses.
      for (var i = 1; i < stops.length; i++) {
        final a = nodes[i - 1];
        final b = nodes[i];
        if (a == null || b == null) continue;
        expect(
          a.ancestors.contains(b) || b.ancestors.contains(a),
          isFalse,
          reason:
              'stops ${i - 1} and $i (${stops[i - 1]}, ${stops[i]}) '
              'are one control: $stops',
        );
      }

      // The rail: right after Skip, one contiguous run, once.
      expect(where[1], 'rail', reason: 'rail right after Skip: $stops');
      final firstRail = where.indexOf('rail');
      final lastRail = where.lastIndexOf('rail');
      expect(
        where.sublist(firstRail, lastRail + 1).every((w) => w == 'rail'),
        isTrue,
        reason: 'the rail is one run, visited once: $stops',
      );

      // The composer is in the cycle, soon after the rail.
      final composerAt = where.indexOf('composer');
      expect(composerAt, greaterThan(lastRail), reason: 'composer: $stops');
      expect(
        composerAt - lastRail,
        lessThanOrEqualTo(12),
        reason: 'composer within a handful of presses after the rail: $stops',
      );

      // Visual order: the chat pane (messages, then composer) is done before
      // the Now pane starts; no interleaving between the panes.
      final firstNow = where.indexOf('now');
      expect(firstNow, greaterThan(0), reason: 'the Now pane is reachable');
      expect(
        composerAt,
        lessThan(firstNow),
        reason: 'the composer comes before the Now pane: $stops',
      );
      expect(
        where.lastIndexOf('chat'),
        lessThan(firstNow),
        reason: 'no chat-pane stop after the Now pane began: $stops',
      );
      expect(
        where.sublist(firstNow).where((w) => w == 'header' || w == 'rail'),
        isEmpty,
        reason: 'header and rail are not revisited after the panes: $stops',
      );

      // Each message is one stop (bubble only, not its text again).
      for (final tile in tiles) {
        expect(
          stops.where((s) => identical(s.tile, tile)).length,
          1,
          reason: 'each chat message is exactly one Tab stop: $stops',
        );
      }
      // Messages before the composer (top to bottom in the chat pane).
      final lastMessage = stops.lastIndexWhere((s) => s.tile != null);
      expect(lastMessage, lessThan(composerAt), reason: '$stops');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    '#415 room 1280x800: every Tab moves the browser focus, once',
    (tester) async {
      // QA residual (dev 7.41.26): on the web «More actions» took two Tab
      // presses, every message group two, the NOW pencil five. The browser
      // focuses the element of the semantics node that says it has focus;
      // a stop whose focus no node carries leaves the browser where it was.
      final handle = tester.ensureSemantics();
      final repo = FakeBeaconThreadsRepository(
        userId: kBeaconViewHarnessAuthorId,
      );
      const author = Profile(id: kBeaconViewHarnessAuthorId, displayName: 'A');
      repo.messages = [
        RoomMessage(
          id: 'm-1',
          beaconId: kBeaconViewHarnessBeaconId,
          authorId: kBeaconViewHarnessAuthorId,
          body: _kFirstMessage,
          createdAt: kBeaconViewHarnessNow,
          author: author,
        ),
        RoomMessage(
          id: 'm-2',
          beaconId: kBeaconViewHarnessBeaconId,
          authorId: kBeaconViewHarnessAuthorId,
          body: _kSecondMessage,
          createdAt: kBeaconViewHarnessNow.add(const Duration(minutes: 1)),
          author: author,
        ),
      ];
      registerRoomCubitProfileCubit(kBeaconViewHarnessAuthorId);
      await registerBeaconViewHarnessGetIt(roomRepo: repo);
      final (host, roomCubits) = _host(repo);
      host.syncBeaconStatus(
        BeaconStatus.open,
        authorId: kBeaconViewHarnessAuthorId,
      );
      addTearDown(() async {
        for (final cubit in roomCubits) {
          await cubit.close();
        }
      });

      await pumpBeaconViewHarness(
        tester,
        size: const Size(1280, 800),
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        host: host,
        viewTab: 'now',
      );
      await _waitForSplitRoom(tester, roomCubits);
      await pumpUntilViewportDone(tester);

      final skip = Focus.of(tester.element(find.text('Skip to content')))
        ..requestFocus();
      // requestFocus applies in a microtask after this pump's (absent)
      // frame; the second pump rebuilds Focus's semantics with the focus.
      await tester.pump();
      await tester.pump();
      var previous = focusedSemanticsNodes().map((n) => n.id).toSet();
      var previousSaid = 'Skip to content';
      final stops = <String>[];
      var bubbles = 0;
      for (var i = 0; i < 80; i++) {
        await _tab(tester);
        final focus = FocusManager.instance.primaryFocus;
        if (identical(focus, skip)) break;
        final label = focus?.debugLabel ?? '${focus?.context?.widget}';
        if (label == 'RoomMessageBubble') bubbles++;
        final nodes = focusedSemanticsNodes();
        final ids = nodes.map((n) => n.id).toSet();
        final said = nodes.map(describeSemanticsNode).join(' + ');
        expect(
          ids,
          isNotEmpty,
          reason:
              'Tab ${i + 1} is on $label, but no semantics node says it has '
              'focus: the browser stays on «$previousSaid». Stops: $stops',
        );
        expect(
          ids,
          isNot(equals(previous)),
          reason:
              'Tab ${i + 1} ($label) left the browser focus on the same node '
              'as the press before ($said). Stops: $stops',
        );
        stops.add('$label → $said');
        previous = ids;
        previousSaid = said;
      }
      expect(bubbles, 2, reason: 'both messages were stops: $stops');
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
