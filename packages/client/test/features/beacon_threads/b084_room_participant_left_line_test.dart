// B084: when an admitted helper withdraws, the server posts a
// `participantLeft` system line (marker 18) with the reason key and the
// helper's note. The room must show who left and why, as a centered system
// line, not an empty chat bubble.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _omar = Profile(id: 'u-omar', displayName: 'Omar Dinner');

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

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

RoomMessage _leftLine({String note = 'Saturday morning fell through.'}) =>
    RoomMessage(
      id: 'R-left',
      beaconId: 'B1',
      authorId: _omar.id,
      author: _omar,
      body: '',
      createdAt: DateTime.utc(2026, 10, 14, 9),
      semanticMarker: BeaconRoomSemanticMarker.participantLeft,
      systemPayloadJson: note.isEmpty
          ? '{"leftUserId":"u-omar","withdrawReason":"timing"}'
          : '{"leftUserId":"u-omar","withdrawReason":"timing",'
                '"note":"$note"}',
    );

Widget _harness(RoomMessage message, {Locale locale = const Locale('en')}) =>
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: RoomMessageTile(
                  message: message,
                  myProfile: _viewer,
                  onToggleReaction: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows who left, the reason and the note', (tester) async {
    await tester.pumpWidget(_harness(_leftLine()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Omar Dinner left the request (Timing no longer works): '
        '“Saturday morning fell through.”',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('without a note shows who left and the reason', (tester) async {
    await tester.pumpWidget(_harness(_leftLine(note: '')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Omar Dinner left the request (Timing no longer works)',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('“', findRichText: true), findsNothing);
  });

  testWidgets('is localized (ru)', (tester) async {
    await tester.pumpWidget(
      _harness(_leftLine(), locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Omar Dinner покинул(а) запрос', findRichText: true),
      findsOneWidget,
    );
  });
}
