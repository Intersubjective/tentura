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

class MockRoomCubit extends Mock implements RoomCubit {
  MockRoomCubit(this._state);

  final RoomState _state;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream<RoomState>.value(_state);

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

/// Pumps [BeaconRoomBody] under a seeded [RoomCubit] with required GetIt deps.
Future<void> pumpBeaconRoomBody(
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
  final roomCubit = MockRoomCubit(roomState);

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
