import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/components/tentura_capability_glyph.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/presence_avatar.dart';
import 'package:tentura_root/domain/enums.dart';

class _RecordingEffects implements UiEffectPort {
  final List<UiEffect> emitted = [];

  @override
  void emit(UiEffect effect) => emitted.add(effect);

  @override
  Stream<UiEffect> get effects => const Stream.empty();
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
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

const _logicalSize = Size(360, 600);
const _me = Profile(id: 'me', displayName: 'Me');
const _other = Profile(id: 'other', displayName: 'Alex River');

BeaconParticipant _participant({
  required String helpType,
  String offerNote = '',
  String? nextMoveText,
}) => BeaconParticipant(
  id: 'p-other',
  beaconId: 'b1',
  userId: 'other',
  role: BeaconParticipantRoleBits.helper,
  status: BeaconParticipantStatusBits.offeredHelp,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  userTitle: 'Alex River',
  handle: 'alex',
  helpType: helpType,
  offerNote: offerNote,
  nextMoveText: nextMoveText,
);

RoomMessage _otherMessage() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'other',
  author: _other,
  body: 'I can pick this up tomorrow.',
  createdAt: DateTime.utc(2026, 5, 22, 12, 34),
);

void main() {
  late _RecordingEffects effects;
  late ScreenCubit screenCubit;

  setUp(() {
    effects = _RecordingEffects();
    screenCubit = ScreenCubit.local(effects);
  });

  tearDown(() async {
    await screenCubit.close();
  });

  Future<void> pumpTile(
    WidgetTester tester, {
    required List<BeaconParticipant> participants,
    RoomMessage? message,
    Profile myProfile = _me,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
          BlocProvider<ScreenCubit>.value(value: screenCubit),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: _logicalSize),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: SizedBox(
                  width: _logicalSize.width,
                  child: RoomMessageTile(
                    message: message ?? _otherMessage(),
                    myProfile: myProfile,
                    participants: participants,
                    onToggleReaction: (_, _) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'group-end incoming tile shows two glyphs for four legacy help types',
    (tester) async {
      await pumpTile(
        tester,
        participants: [
          _participant(
            helpType: '["transport","storage","tools","money"]',
            offerNote: 'I can store the parts.',
          ),
        ],
      );

      expect(find.byType(TenturaCapabilityGlyph), findsNWidgets(2));
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);
      expect(find.byIcon(Icons.warehouse_rounded), findsOneWidget);
      expect(find.byIcon(Icons.build_rounded), findsNothing);
    },
  );

  testWidgets('glyph tap opens commitment sheet with note and labels', (
    tester,
  ) async {
    await pumpTile(
      tester,
      participants: [
        _participant(
          helpType: '["transport","storage"]',
          offerNote: 'I can store the parts.',
          nextMoveText: 'Confirm pickup window',
        ),
      ],
    );

    await tester.tap(find.byKey(TestIds.key(TestIds.roomAuthorCommitmentGlyphs)));
    await tester.pumpAndSettle();

    expect(find.text('Alex River'), findsWidgets);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('I can store the parts.'), findsOneWidget);
    expect(find.text('Confirm pickup window'), findsOneWidget);
    expect(effects.emitted, isEmpty);
  });

  testWidgets('avatar tap opens profile and does not open sheet', (
    tester,
  ) async {
    await pumpTile(
      tester,
      participants: [
        _participant(helpType: '["transport","storage"]'),
      ],
    );

    await tester.tap(find.byType(PresenceAvatar));
    await tester.pumpAndSettle();

    expect(find.text('Transport'), findsNothing);
    expect(
      effects.emitted.whereType<NavigatePush>().map((e) => e.path),
      contains('/profile/view/other'),
    );
  });

  testWidgets('glyphs hidden for mine messages', (tester) async {
    await pumpTile(
      tester,
      myProfile: _other,
      message: RoomMessage(
        id: 'm1',
        beaconId: 'b1',
        authorId: 'other',
        author: _other,
        body: 'mine',
        createdAt: DateTime.utc(2026),
      ),
      participants: [
        _participant(helpType: '["transport"]'),
      ],
    );

    expect(find.byType(TenturaCapabilityGlyph), findsNothing);
  });
}
