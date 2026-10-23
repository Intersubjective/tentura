// #528: a next-step or title edit posts a `requestEdited` system line
// (kind 8) with payload `{version: 1, field, from, to, edits?}`. The room
// shows who changed what, to what, as a centered system line.

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
const _author = Profile(id: 'u-author', displayName: 'Tab QA');

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

RoomMessage _editLine({
  required String field,
  required String to,
  String from = '',
  bool authorless = false,
  Profile author = _author,
  int version = 1,
}) => RoomMessage(
  id: 'R-edit',
  beaconId: 'B1',
  authorId: authorless ? '' : author.id,
  author: authorless ? const Profile() : author,
  body: '',
  createdAt: DateTime.utc(2026, 10, 23, 9),
  systemMessageKind: BeaconRoomSystemMessageKind.requestEdited,
  systemPayloadJson:
      '{"version":$version,"field":"$field","from":"$from","to":"$to"}',
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
  testWidgets('a next-step edit names who set it and the new step', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_editLine(field: 'nextStep', to: 'Nina: van 9:45')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Tab QA set the next step: “Nina: van 9:45”',
        findRichText: true,
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _harness(
        _editLine(field: 'nextStep', to: 'Nina: van 9:45'),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Tab QA задал(а) следующий шаг: «Nina: van 9:45»',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a rename shows the old and the new title', (tester) async {
    await tester.pumpWidget(
      _harness(_editLine(field: 'title', from: 'Move', to: 'Move on Sat')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Tab QA renamed the request: “Move” → “Move on Sat”',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('own edits read «Вы …», a deleted account a former member', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _editLine(field: 'nextStep', to: 'x', author: _viewer),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Вы задали следующий шаг', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _harness(_editLine(field: 'title', from: 'a', to: 'b', authorless: true)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'A former member renamed the request',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable payload renders nothing', (tester) async {
    await tester.pumpWidget(
      _harness(_editLine(field: 'nextStep', to: 'x', version: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('next step', findRichText: true), findsNothing);
    expect(find.textContaining('Tab QA', findRichText: true), findsNothing);
  });
}
