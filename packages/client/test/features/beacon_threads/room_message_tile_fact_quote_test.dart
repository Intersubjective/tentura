import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

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

const _logicalSize = Size(360, 600);

Widget _harness(Widget child) {
  return MultiBlocProvider(
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
}

RoomMessage _messageWithQuotedFact() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: 'Check the pinned fact above',
  createdAt: DateTime.utc(2026),
  quotedFact: const QuotedFact(
    factCardId: 'fact-1',
    seq: 1,
    currentSeq: 1,
    status: BeaconFactCardStatusBits.active,
    factText: 'The venue moved to 221B Baker Street',
    pinnedById: 'peer-1',
    pinnedByTitle: 'Peer One',
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

  testWidgets(
    'a message carrying a QuotedFact renders RoomMessageFactQuote',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          RoomMessageTile(
            message: _messageWithQuotedFact(),
            myProfile: const Profile(id: 'viewer', displayName: 'Me'),
            onToggleReaction: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoomMessageFactQuote), findsOneWidget);
    },
  );

  testWidgets(
    'a message without a QuotedFact renders no RoomMessageFactQuote',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          RoomMessageTile(
            message: RoomMessage(
              id: 'm2',
              beaconId: 'b1',
              authorId: 'u1',
              author: const Profile(id: 'u1', displayName: 'Author'),
              body: 'A plain message',
              createdAt: DateTime.utc(2026),
            ),
            myProfile: const Profile(id: 'viewer', displayName: 'Me'),
            onToggleReaction: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoomMessageFactQuote), findsNothing);
    },
  );
}
