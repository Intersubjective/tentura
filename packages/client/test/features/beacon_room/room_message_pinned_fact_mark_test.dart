import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
        profile: Profile(id: 'viewer', displayName: 'Me'),
      );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

BeaconFactCard _publicFact() => BeaconFactCard(
      id: 'f1',
      beaconId: 'b1',
      factText: 'Pinned text',
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: 'u1',
      createdAt: DateTime.utc(2026),
      status: BeaconFactCardStatusBits.active,
      sourceMessageId: 'm1',
    );

RoomMessage _message() => RoomMessage(
      id: 'm1',
      beaconId: 'b1',
      authorId: 'u1',
      author: const Profile(id: 'u1', displayName: 'Author'),
      body: 'Source message body',
      createdAt: DateTime.utc(2026),
    );

Widget _harness({required BeaconFactCard? pinnedFact}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
      BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
    ],
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 600)),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: RoomMessageTile(
              message: _message(),
              myProfile: const Profile(id: 'viewer', displayName: 'Me'),
              onToggleReaction: (_, _) async {},
              pinnedFact: pinnedFact,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('public pinned fact shows visibility mark on message', (tester) async {
    await tester.pumpWidget(_harness(pinnedFact: _publicFact()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pinned · public fact'), findsOneWidget);
    expect(find.byIcon(Icons.public_outlined), findsOneWidget);
  });

  testWidgets('chat-only pinned fact shows private mark on message', (tester) async {
    await tester.pumpWidget(
      _harness(
        pinnedFact: _publicFact().copyWith(
          visibility: BeaconFactCardVisibilityBits.room,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pinned · chat fact'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
  });
}
