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
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import 'beacon_view_screen_harness.dart';

/// #451: the next step («NOW …») sat twice on a wide window: once in the Now
/// pane (pinned HUD) and once as the pinned strip at the top of the chat.
/// It is shown once: the Now pane on a wide (split) window, the chat strip on
/// a narrow one (where Now and Chat are separate tabs).
const _kNowLine = 'Frame on Saturday at the school gate';

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

({ThreadHostCubit host, List<RoomCubit> cubits}) _host(
  FakeBeaconThreadsRepository repo,
) {
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
  return (host: host, cubits: cubits);
}

Future<({ThreadHostCubit host, List<RoomCubit> cubits})> _setUpRoom(
  WidgetTester tester,
) async {
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
  final bundle = _host(repo);
  addTearDown(() async {
    for (final cubit in bundle.cubits) {
      await cubit.close();
    }
  });
  return bundle;
}

/// Pumps until the chat pane is built and its room state (the NOW line)
/// has loaded.
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

Finder _nowLineIn(Finder scope) => find.descendant(
  of: scope,
  matching: find.textContaining(_kNowLine, findRichText: true),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  testWidgets('wide window: the next step shows once, in the Now pane', (
    tester,
  ) async {
    final bundle = await _setUpRoom(tester);
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessExpanded,
      beaconState: _beaconState(),
      threadsState: beaconViewHarnessThreadsState(),
      host: bundle.host,
    );
    await _waitForRoomState(tester, bundle.cubits);

    // Precondition: the split shows the chat and the Now pane side by side.
    expect(find.byType(ThreadDetail), findsOneWidget);
    expect(find.byType(BeaconHudPinnedBlock), findsOneWidget);

    // The Now pane keeps its NOW row.
    expect(_nowLineIn(find.byType(BeaconHudPinnedBlock)), findsOneWidget);
    // The chat pane does not repeat it as a pinned strip.
    expect(_nowLineIn(find.byType(ThreadDetail)), findsNothing);
    // Once on the whole screen.
    expect(
      find.textContaining(_kNowLine, findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('narrow window: the chat tab keeps the pinned next step', (
    tester,
  ) async {
    final bundle = await _setUpRoom(tester);
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessCompact,
      beaconState: _beaconState(),
      threadsState: beaconViewHarnessThreadsState(),
      host: bundle.host,
    );
    // Narrow: Now is its own tab and carries the NOW row.
    expect(_nowLineIn(find.byType(BeaconHudPinnedBlock)), findsOneWidget);

    await tapBeaconChatTabAndWaitForRoom(tester);
    await _waitForRoomState(tester, bundle.cubits);

    // Chat is its own tab: the strip is the only place the step shows here.
    expect(find.byType(BeaconHudPinnedBlock), findsNothing);
    expect(_nowLineIn(find.byType(ThreadDetail)), findsOneWidget);
  });
}
