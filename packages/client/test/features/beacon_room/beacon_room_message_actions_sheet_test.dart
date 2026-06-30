import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

class _MockRoomCubit extends Mock implements RoomCubit {
  _MockRoomCubit(this._state);

  final RoomState _state;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream<RoomState>.empty();

  @override
  Future<void> markReadToBottom() async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.empty();
}

void main() {
  final getIt = GetIt.I;

  const viewer = Profile(id: 'me', displayName: 'Me');
  const author = Profile(id: 'other', displayName: 'Alex');

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpRoom(
    WidgetTester tester, {
    required double width,
  }) async {
    final profileCubit = _MockProfileCubit(viewer);
    final presenceCubit = _MockPresenceCubit();
    final state = RoomState(
      beaconId: 'b1',
      myUserId: viewer.id,
      messages: [
        RoomMessage(
          id: 'm1',
          beaconId: 'b1',
          authorId: author.id,
          author: author,
          body: 'Hello room',
          createdAt: DateTime.utc(2026, 6, 30, 12),
        ),
      ],
    );
    final roomCubit = _MockRoomCubit(state);

    getIt.registerSingleton<ProfileCubit>(profileCubit);
    getIt.registerSingleton<ImageRepository>(ImageRepository());

    await tester.binding.setSurfaceSize(Size(width, 900));
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
            data: MediaQueryData(size: Size(width, 900)),
            child: const TenturaResponsiveScope(
              child: Scaffold(
                body: BeaconRoomBody(enableComposer: false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<double> openMessageActionsSheetWidth(WidgetTester tester) async {
    expect(find.byType(RoomMessageTile), findsOneWidget);
    final inlineBody = find.byType(RoomMessageTextBody);
    final body = inlineBody.evaluate().isNotEmpty
        ? inlineBody
        : find.byType(ShowMoreText);
    await tester.longPress(body);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final scroller = find.descendant(
      of: sheet,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scroller, findsOneWidget);

    return tester.getSize(scroller).width;
  }

  testWidgets('message actions sheet stays full-width on compact windows', (
    tester,
  ) async {
    await pumpRoom(tester, width: 375);

    expect(await openMessageActionsSheetWidth(tester), 375);
  });

  testWidgets('message actions sheet is width-capped on regular windows', (
    tester,
  ) async {
    await pumpRoom(tester, width: 700);

    expect(await openMessageActionsSheetWidth(tester), 560);
  });
}
