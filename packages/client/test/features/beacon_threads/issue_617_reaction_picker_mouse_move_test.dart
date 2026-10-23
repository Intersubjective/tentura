import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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

// #617 (from #456): the reaction picker opened from the hover strip must
// stay open while the mouse moves off the bubble and the strip, e.g. on the
// way from the heart to the picker, until an emoji is picked.

void main() {
  const viewer = Profile(id: 'me', displayName: 'Me');
  final createdAt = DateTime.utc(2026, 6, 30, 12);

  Future<void> pumpTile(
    WidgetTester tester, {
    required RoomMessage message,
    void Function(RoomMessage message)? onReplyPressed,
    void Function(RoomMessage message)? onActionsPressed,
    Future<void> Function(String messageId, String emoji)? onToggleReaction,
  }) async {
    final profileCubit = _MockProfileCubit(viewer);
    final presenceCubit = _MockPresenceCubit();

    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: profileCubit),
          BlocProvider<PresenceCubit>.value(value: presenceCubit),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: RoomMessageTile(
                message: message,
                myProfile: viewer,
                onActionsPressed: onActionsPressed ?? (_) {},
                onReplyPressed: onReplyPressed,
                onToggleReaction: onToggleReaction ?? (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The bubble's own enter/exit hover region: an ancestor of the bubble's
  // press-scale transform. Scoped so other pointer regions in the tile (e.g.
  // the tappable author avatar's InkWell) do not count.
  Finder hoverToolbarMouseRegion() => find.ancestor(
    of: find.byKey(TestIds.key(TestIds.roomMessageBubblePressScale)),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.onEnter != null &&
          widget.onExit != null,
    ),
  );

  testWidgets('reaction picker stays open when the mouse leaves the bubble', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final toggled = <(String, String)>[];
    await pumpTile(
      tester,
      message: RoomMessage(
        id: 'm1',
        beaconId: 'b1',
        authorId: 'other',
        author: const Profile(id: 'other', displayName: 'Other'),
        body: 'Hello',
        createdAt: createdAt,
      ),
      onToggleReaction: (id, emoji) async => toggled.add((id, emoji)),
    );

    final bubble = hoverToolbarMouseRegion();
    expect(bubble, findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(bubble));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(bubble));
    await tester.pumpAndSettle();

    // Click the heart with the same mouse.
    final heart = find.byTooltip(l10n.beaconRoomReactionAddTooltip);
    final heartRect = tester.getRect(heart);
    await mouse.moveTo(heartRect.center);
    await tester.pumpAndSettle();
    await mouse.down(heartRect.center);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconRoomReactionPickerHint), findsOneWidget);

    // A small step off the strip, then well away from bubble, strip and
    // picker alike.
    await mouse.moveTo(heartRect.bottomCenter + const Offset(0, 6));
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconRoomReactionPickerHint), findsOneWidget);
    await mouse.moveTo(const Offset(4, 596));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.beaconRoomReactionPickerHint),
      findsOneWidget,
      reason: 'moving the mouse must not tear the picker down',
    );

    // The picker still works by mouse.
    const pray = '\u{1F64F}';
    final prayCenter = tester.getCenter(find.text(pray));
    await mouse.moveTo(prayCenter);
    await tester.pumpAndSettle();
    await mouse.down(prayCenter);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(toggled, [('m1', pray)]);
    expect(find.text(l10n.beaconRoomReactionPickerHint), findsNothing);

    // Closed, with the mouse away, the strip goes too.
    await mouse.moveTo(const Offset(4, 596));
    await tester.pumpAndSettle();
    expect(heart, findsNothing);
  });
}
