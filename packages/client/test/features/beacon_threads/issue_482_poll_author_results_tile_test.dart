import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

// Issue #482, wiring: the room tile tells the poll card whether the viewer
// authored the poll message, so the author sees results without voting.

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

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

final _pollJson = jsonEncode({
  'id': 'poll-482',
  'question': 'Which day works?',
  'pollType': 'single',
  'isAnonymous': false,
  'allowRevote': true,
  'myVariantIds': <String>[],
  'totalVotes': 3,
  'variants': [
    {'id': 'variant-sun', 'description': 'Sunday', 'votesCount': 2},
    {'id': 'variant-sat', 'description': 'Saturday', 'votesCount': 1},
  ],
});

RoomMessage _pollMessage({required String authorId}) => RoomMessage(
  id: 'm-poll',
  beaconId: 'b1',
  authorId: authorId,
  author: Profile(id: authorId, displayName: 'Poll author'),
  body: 'Which day works?',
  createdAt: DateTime.utc(2026),
  linkedPollingId: 'poll-482',
  pollDataJson: _pollJson,
);

const _logicalSize = Size(390, 900);

Widget _harness(Widget child) => MultiBlocProvider(
  providers: [
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: const MediaQueryData(size: _logicalSize),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: SizedBox(width: _logicalSize.width, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(
      _FakePlatformRepository(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('poll posted by the viewer shows results before they vote', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        RoomMessageTile(
          message: _pollMessage(authorId: 'viewer'),
          myProfile: const Profile(id: 'viewer', displayName: 'Me'),
          onToggleReaction: (_, _) async {},
          onVotePoll: (_, _, {score}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RoomPollCard), findsOneWidget);
    expect(
      tester.widget<RoomPollCard>(find.byType(RoomPollCard)).isAuthor,
      isTrue,
    );
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
  });

  testWidgets('poll posted by someone else hides results until the viewer '
      'votes', (tester) async {
    await tester.pumpWidget(
      _harness(
        RoomMessageTile(
          message: _pollMessage(authorId: 'u1'),
          myProfile: const Profile(id: 'viewer', displayName: 'Me'),
          onToggleReaction: (_, _) async {},
          onVotePoll: (_, _, {score}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RoomPollCard), findsOneWidget);
    expect(
      tester.widget<RoomPollCard>(find.byType(RoomPollCard)).isAuthor,
      isFalse,
    );
    expect(find.textContaining('%'), findsNothing);
  });
}
