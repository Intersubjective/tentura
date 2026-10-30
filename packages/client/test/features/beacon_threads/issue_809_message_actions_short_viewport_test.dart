import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockRoomCubit extends Mock implements RoomCubit {
  _MockRoomCubit(this._state);

  final RoomState _state;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => const Stream<RoomState>.empty();

  @override
  Future<void> markReadToBottom() async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      const Stream<Map<String, UserPresenceStatus>>.empty();
}

Rect _viewport(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

void _expectFullyVisible(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  final view = _viewport(tester);
  expect(rect.top, greaterThanOrEqualTo(view.top));
  expect(rect.bottom, lessThanOrEqualTo(view.bottom + 0.5));
}

void main() {
  const viewer = Profile(id: 'me', displayName: 'Me');
  const author = Profile(id: 'other', displayName: 'Alex');

  Future<void> pumpRoom(WidgetTester tester) async {
    const viewport = Size(375, 667);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final profileCubit = _MockProfileCubit(viewer);
    final presenceCubit = _MockPresenceCubit();
    final roomCubit = _MockRoomCubit(
      RoomState(
        beaconId: 'b1',
        myUserId: viewer.id,
        beaconStatus: BeaconStatus.open,
        participants: [
          BeaconParticipant(
            id: 'p-me',
            beaconId: 'b1',
            userId: viewer.id,
            role: BeaconParticipantRoleBits.helper,
            status: 0,
            roomAccess: RoomAccessBits.admitted,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            userTitle: viewer.displayName,
          ),
        ],
        participantsLoaded: true,
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
      ),
    );

    GetIt.I
      ..registerSingleton<ProfileCubit>(profileCubit)
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(
        ClipboardImageRepository(),
      );
    addTearDown(GetIt.I.reset);

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
          home: const TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconRoomBody(enableComposer: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('#809 Create child request is reachable at 375×667', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpRoom(tester);

    final body = find.byType(RoomMessageTextBody);
    await tester.longPressAt(tester.getTopLeft(body) + const Offset(8, 8));
    await tester.pumpAndSettle();

    final createChild = find.text(l10n.beaconCreateChildRequest);
    if (createChild.hitTestable().evaluate().isEmpty) {
      final sheetScroll = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      expect(sheetScroll, findsWidgets);
      await tester.drag(sheetScroll.first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }

    _expectFullyVisible(tester, createChild);
    expect(tester.takeException(), isNull);
  });

  test('hover toolbar clears the child-request footer strip', () {
    const bounds = Rect.fromLTWH(0, 0, 320, 600);
    const strip = Size(160, 40);
    // Near the top of the chat so the strip flips below the bubble (#478).
    const bubble = Rect.fromLTWH(12, 8, 200, 48);
    const clearance = 48.0;

    const withoutClearance = HoverToolbarLayout(
      bubble: bubble,
      bounds: bounds,
      alignLeft: true,
      overlap: 4,
    );
    const withClearance = HoverToolbarLayout(
      bubble: bubble,
      bounds: bounds,
      alignLeft: true,
      overlap: 4,
      clearanceBelowBubble: clearance,
    );

    final withoutPos = withoutClearance.getPositionForChild(bounds.size, strip);
    final withPos = withClearance.getPositionForChild(bounds.size, strip);

    expect(withoutPos.dy, lessThan(bubble.bottom + clearance));
    expect(withPos.dy, greaterThanOrEqualTo(bubble.bottom + clearance));
  });

}
