import 'dart:async';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

/// Test [RoomCubit] that can emit state and record scroll-target clears.
class RoomBodyHarnessCubit extends Mock implements RoomCubit {
  RoomBodyHarnessCubit(RoomState initial)
      : _state = initial,
        _streamController = StreamController<RoomState>.broadcast() {
    _streamController.add(_state);
  }

  RoomState _state;
  final StreamController<RoomState> _streamController;

  var clearScrollTargetInvocations = 0;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => _streamController.stream;

  void emitHarnessState(RoomState next) {
    _state = next;
    _streamController.add(next);
  }

  @override
  void clearScrollToMessageTarget() {
    clearScrollTargetInvocations++;
    if (_state.scrollToMessageId != null) {
      emitHarnessState(_state.copyWith(scrollToMessageId: null));
    }
  }

  @override
  Future<void> markReadToBottom() async {}
}

class RoomBodyHarnessProfileCubit extends Mock implements ProfileCubit {
  RoomBodyHarnessProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class RoomBodyHarnessPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

ScrollableState listScrollableState(WidgetTester tester) {
  final listScrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(listScrollable);
}

Future<void> pumpUntilViewportDone(
  WidgetTester tester, {
  int maxFrames = 40,
}) async {
  final chatFinder = find.byType(BasicChatBody);
  final chatState = tester.state<BasicChatBodyState>(chatFinder);
  if (!chatState.isViewportScrollDone) {
    chatState.onRoomDataChangedForViewport(
      firstUnreadMessageId: null,
      messagesEmpty: false,
    );
  }
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (tester.state<BasicChatBodyState>(chatFinder).isViewportScrollDone) {
      return;
    }
  }
}

Future<void> pumpUntilScrollTargetCleared(
  WidgetTester tester,
  RoomBodyHarnessCubit cubit, {
  int maxFrames = 80,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (cubit.clearScrollTargetInvocations > 0) {
      return;
    }
  }
}

/// Pumps frames while [scroll] runs so [Scrollable.ensureVisible] can finish.
Future<bool> pumpWhileScrolling(
  WidgetTester tester,
  Future<bool> scroll, {
  int maxFrames = 120,
}) async {
  var done = false;
  late bool result;
  unawaited(
    scroll.then((value) {
      done = true;
      result = value;
    }),
  );
  for (var i = 0; i < maxFrames && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (!done) {
    return false;
  }
  return result;
}

/// Pumps [BeaconRoomBody] under a seeded [RoomCubit] with required GetIt deps.
Future<RoomBodyHarnessCubit> pumpBeaconRoomBody(
  WidgetTester tester, {
  required RoomState roomState,
  Profile viewer = const Profile(id: 'me', displayName: 'Me'),
  double width = 390,
  double height = 720,
  bool enableComposer = true,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();

  final profileCubit = RoomBodyHarnessProfileCubit(viewer);
  final presenceCubit = RoomBodyHarnessPresenceCubit();
  final roomCubit = RoomBodyHarnessCubit(roomState);

  getIt.registerSingleton<ProfileCubit>(profileCubit);
  getIt.registerSingleton<ImageRepository>(ImageRepository());
  getIt.registerSingleton<ClipboardImageRepository>(
    ClipboardImageRepository(),
  );

  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: roomCubit),
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconRoomBody(enableComposer: enableComposer),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return roomCubit;
}

RoomState roomBodyState({
  String beaconId = 'b1',
  String? threadItemId,
  String myUserId = 'me',
  List<RoomMessage> messages = const [],
  RoomMessage? replyTarget,
  String? scrollToMessageId,
  List<String> pinnedJumpMessageIds = const [],
}) {
  return RoomState(
    beaconId: beaconId,
    threadItemId: threadItemId,
    myUserId: myUserId,
    messages: messages,
    replyTarget: replyTarget,
    scrollToMessageId: scrollToMessageId,
    pinnedJumpMessageIds: pinnedJumpMessageIds,
  );
}
