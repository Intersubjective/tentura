import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import 'beacon_view_screen_harness.dart';

/// #609 (with #509) had the chat pin the next step whenever the Now pane
/// beside it gave way to People or Plan. The owner reversed that: the pinned
/// step took too much room over the chat, so the chat never pins it — the
/// step lives on the Now tab, where it is edited.
const _kNowLine = 'Van at 9:45, dolly from Omar';

class _NowLineRoomRepository extends FakeBeaconThreadsRepository {
  _NowLineRoomRepository() : super(userId: kBeaconViewHarnessAuthorId);

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      BeaconRoomState(
        beaconId: beaconId,
        updatedAt: kBeaconViewHarnessNow,
        currentLine: _kNowLine,
      );
}

BeaconViewState _beaconState() => beaconViewHarnessAuthorState().copyWith(
  beaconRoomCue: BeaconRoomState(
    beaconId: kBeaconViewHarnessBeaconId,
    updatedAt: kBeaconViewHarnessNow,
    currentLine: _kNowLine,
  ),
);

Future<({ThreadHostCubit host, List<RoomCubit> cubits})> _setUpRoom() async {
  final repo = _NowLineRoomRepository()
    ..messages = [
      RoomMessage(
        id: 'm-1',
        beaconId: kBeaconViewHarnessBeaconId,
        authorId: kBeaconViewHarnessAuthorId,
        body: 'Hello team',
        createdAt: kBeaconViewHarnessNow,
        author: const Profile(
          id: kBeaconViewHarnessAuthorId,
          displayName: 'Author',
        ),
      ),
    ];
  registerRoomCubitProfileCubit(kBeaconViewHarnessAuthorId);
  await registerBeaconViewHarnessGetIt(roomRepo: repo);
  final cubits = <RoomCubit>[];
  RoomCubit roomFactory({
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
    cubits.add(cubit);
    unawaited(cubit.load());
    return cubit;
  }

  final host = ThreadHostCubit(
    beaconId: kBeaconViewHarnessBeaconId,
    roomCubitFactory: roomFactory,
  );
  addTearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
  });
  return (host: host, cubits: cubits);
}

Future<void> _waitForRoomState(
  WidgetTester tester,
  List<RoomCubit> cubits,
) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final chatReady =
        find.byType(ThreadDetail).evaluate().isNotEmpty &&
        find.byType(BasicChatBody).evaluate().isNotEmpty;
    final roomReady =
        cubits.isNotEmpty &&
        cubits.first.state.roomState?.currentLine == _kNowLine;
    if (chatReady && roomReady) {
      await tester.pump(const Duration(milliseconds: 50));
      return;
    }
  }
  fail('chat pane did not load the room state');
}

Future<void> _tapTab(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(TestIds.key(id)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _nowLineIn(Finder scope) => find.descendant(
  of: scope,
  matching: find.textContaining(_kNowLine, findRichText: true),
);

Finder get _nowLineAnywhere =>
    find.textContaining(_kNowLine, findRichText: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  testWidgets('wide window, People beside the chat: the chat does not pin '
      'the next step', (tester) async {
    final bundle = await _setUpRoom();
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessExpanded,
      beaconState: _beaconState(),
      threadsState: beaconViewHarnessThreadsState(),
      host: bundle.host,
    );
    await _waitForRoomState(tester, bundle.cubits);

    // Precondition (#451): with Now beside the chat the step shows once, in
    // the Now pane.
    expect(_nowLineIn(find.byType(BeaconHudPinnedBlock)), findsOneWidget);
    expect(_nowLineIn(find.byType(ThreadDetail)), findsNothing);

    await _tapTab(tester, TestIds.beaconTabPeople);

    // The Now pane is gone; the chat stays beside People.
    expect(find.byType(BeaconHudPinnedBlock), findsNothing);
    expect(find.byType(ThreadDetail), findsOneWidget);
    expect(_nowLineAnywhere, findsNothing);
  });

  testWidgets('wide window, back to Now: the step is shown once again, in '
      'the Now pane', (tester) async {
    final bundle = await _setUpRoom();
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessExpanded,
      beaconState: _beaconState(),
      threadsState: beaconViewHarnessThreadsState(),
      host: bundle.host,
    );
    await _waitForRoomState(tester, bundle.cubits);

    await _tapTab(tester, TestIds.beaconTabPeople);
    expect(_nowLineAnywhere, findsNothing);

    await _tapTab(tester, TestIds.beaconTabNow);

    expect(_nowLineIn(find.byType(BeaconHudPinnedBlock)), findsOneWidget);
    expect(_nowLineIn(find.byType(ThreadDetail)), findsNothing);
    expect(_nowLineAnywhere, findsOneWidget);
  });
}
