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

  Finder hoverToolbarMouseRegion() => find.byWidgetPredicate(
    (widget) =>
        widget is MouseRegion &&
        widget.onEnter != null &&
        widget.onExit != null,
  );

  Future<void> hoverBubble(WidgetTester tester) async {
    final hoverTarget = hoverToolbarMouseRegion();
    expect(hoverTarget, findsOneWidget);
    final center = tester.getCenter(hoverTarget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();
  }

  testWidgets('hover toolbar shows Reply for server messages', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    RoomMessage? replied;
    await pumpTile(
      tester,
      message: RoomMessage(
        id: 'm1',
        beaconId: 'b1',
        authorId: viewer.id,
        author: viewer,
        body: 'Hello',
        createdAt: createdAt,
      ),
      onReplyPressed: (m) => replied = m,
    );

    await hoverBubble(tester);

    final replyButton = find.byTooltip(l10n.beaconRoomActionReply);
    expect(replyButton, findsOneWidget);
    await tester.tap(replyButton);
    expect(replied?.id, 'm1');
  });

  testWidgets('hover toolbar hides Reply for local pending messages', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpTile(
      tester,
      message: RoomMessage(
        id: 'local:pending',
        beaconId: 'b1',
        authorId: viewer.id,
        author: viewer,
        body: 'Sending…',
        createdAt: createdAt,
      ),
      onReplyPressed: (_) {},
    );

    await hoverBubble(tester);

    expect(find.byTooltip(l10n.beaconRoomActionReply), findsNothing);
  });

  testWidgets('hover heart opens the reaction picker instead of reacting', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final toggled = <(String, String)>[];
    var actionsCount = 0;
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
      onActionsPressed: (_) => actionsCount++,
      onToggleReaction: (id, emoji) async => toggled.add((id, emoji)),
    );

    await hoverBubble(tester);
    await tester.tap(find.byTooltip(l10n.beaconRoomReactionAddTooltip));
    await tester.pumpAndSettle();

    expect(toggled, isEmpty);
    expect(actionsCount, 0);
    expect(find.text(l10n.beaconRoomReactionPickerHint), findsOneWidget);

    const pray = '\u{1F64F}';
    await tester.tap(find.text(pray));
    await tester.pumpAndSettle();

    expect(toggled, [('m1', pray)]);
    expect(find.text(l10n.beaconRoomReactionPickerHint), findsNothing);
  });
}
