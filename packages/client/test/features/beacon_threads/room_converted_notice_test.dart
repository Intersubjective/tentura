// A room message with `system_message_kind = 4` (the author converted a Post
// into a Request) renders as the one-line notice «‹author› превратил пост в
// запрос»; the other system kinds keep their existing rendering.

import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_notice.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_closure_story_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Мария');
const _author = Profile(id: 'author', displayName: 'Олег');

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _StubRouter extends Mock implements StackRouter {}

RoomMessage _message({
  required String body,
  int? systemMessageKind,
  String? systemPayloadJson,
  Profile author = _author,
}) => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: author.id,
  author: author,
  body: body,
  createdAt: DateTime.utc(2026, 10, 2, 12),
  systemMessageKind: systemMessageKind,
  systemPayloadJson: systemPayloadJson,
);

Future<void> _pumpTile(WidgetTester tester, RoomMessage message) async {
  await tester.pumpWidget(
    StackRouterScope(
      controller: _StubRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider<PresenceCubit>.value(
            value: RoomBodyHarnessPresenceCubit(),
          ),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 900)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RoomMessageTile(
                    message: message,
                    myProfile: _viewer,
                    participants: const [],
                    capabilities: const RoomCapabilities.request(),
                    onToggleReaction: (_, _) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _text(String s) => find.text(s, findRichText: true);

void main() {
  group('converted-to-request notice in the room', () {
    testWidgets('a kind-4 system message reads «<author> превратил пост в '
        'запрос»', (tester) async {
      await _pumpTile(
        tester,
        _message(
          body: '',
          systemMessageKind: BeaconRoomSystemMessageKind.convertedToRequest,
        ),
      );

      expect(_text('Олег превратил пост в запрос'), findsOneWidget);
    });

    testWidgets('names whoever authored the kind-4 message', (tester) async {
      await _pumpTile(
        tester,
        _message(
          body: '',
          systemMessageKind: BeaconRoomSystemMessageKind.convertedToRequest,
          author: const Profile(id: 'other', displayName: 'Дима'),
        ),
      );

      expect(_text('Дима превратил пост в запрос'), findsOneWidget);
      expect(_text('Олег превратил пост в запрос'), findsNothing);
    });

    testWidgets('a closure story keeps its centered card with title and '
        'story text', (tester) async {
      final l10n = lookupL10n(const Locale('ru'));
      await _pumpTile(
        tester,
        _message(
          body: 'Всё получилось, спасибо',
          systemMessageKind: BeaconRoomSystemMessageKind.closureStory,
        ),
      );

      expect(find.byType(RoomClosureStoryCard), findsOneWidget);
      expect(find.text(l10n.closureStoryRoomTitle), findsOneWidget);
      expect(find.text('Всё получилось, спасибо'), findsOneWidget);
      expect(find.textContaining('превратил пост в запрос'), findsNothing);
    });

    testWidgets('a hierarchy lifecycle notice keeps its one-line notice', (
      tester,
    ) async {
      const line = 'Дочерний запрос закрыт 2026-01-04';
      await _pumpTile(
        tester,
        _message(
          body: line,
          systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
          systemPayloadJson: jsonEncode({
            'version': 1,
            'kind': 'hierarchyLifecycle',
            'eventId': 'e1',
            'targetBeaconId': 'b1',
            'direction': 'child',
            'toStatus': 'closed',
            'occurredAt': '2026-01-04T00:00:00Z',
            'sourceDeleted': false,
          }),
        ),
      );

      expect(find.byType(BeaconHierarchyNotice), findsOneWidget);
      expect(find.text(line), findsOneWidget);
      expect(find.textContaining('превратил пост в запрос'), findsNothing);
    });

    testWidgets('an ordinary message is not turned into the notice', (
      tester,
    ) async {
      await _pumpTile(tester, _message(body: 'Привет всем'));

      expect(
        find.textContaining('Привет всем', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('превратил пост в запрос'), findsNothing);
    });
  });
}
