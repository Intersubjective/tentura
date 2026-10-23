import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

// #617 (from #456): a link inside a room message was a text span only, so
// Tab never reached it and Enter could not open it.

class _FakePlatformRepository implements PlatformRepositoryPort {
  final launched = <Uri>[];

  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async => launched.add(uri);
}

const _viewer = Profile(id: 'viewer', displayName: 'Me');

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

RoomMessage _message(String body) => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: _viewer.id,
  author: _viewer,
  body: body,
  createdAt: DateTime.utc(2026),
);

const _logicalSize = Size(360, 600);

void main() {
  late _FakePlatformRepository platform;
  late int actionsOpened;

  setUp(() async {
    await GetIt.I.reset();
    platform = _FakePlatformRepository();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);
    actionsOpened = 0;
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> pumpTile(WidgetTester tester, String body) async {
    await tester.pumpWidget(
      MultiBlocProvider(
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
                body: SizedBox(
                  width: _logicalSize.width,
                  child: RoomMessageTile(
                    message: _message(body),
                    myProfile: _viewer,
                    onActionsPressed: (_) => actionsOpened++,
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

  /// Puts keyboard focus on the message bubble, as a Tab onto it does.
  Future<void> focusBubble(WidgetTester tester) async {
    final bubble = find.byWidgetPredicate(
      (w) => w is Focus && w.focusNode?.debugLabel == 'RoomMessageBubble',
    );
    expect(bubble, findsOneWidget);
    tester.widget<Focus>(bubble).focusNode!.requestFocus();
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// The style of the span drawing [url] in the message text.
  TextStyle? linkStyle(WidgetTester tester, String url) {
    TextStyle? found;
    for (final rich in tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(RoomMessageTile),
        matching: find.byType(RichText),
      ),
    )) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == url) {
          found = span.style;
          return false;
        }
        return true;
      });
      if (found != null) break;
    }
    expect(found, isNotNull, reason: 'no span draws $url');
    return found;
  }

  testWidgets('Tab from the bubble reaches the link and Enter opens it', (
    tester,
  ) async {
    await pumpTile(tester, 'See https://example.com for details');
    await focusBubble(tester);

    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.enter);

    expect(platform.launched, [Uri.parse('https://example.com')]);
    expect(actionsOpened, 0, reason: 'Enter on a link opens the link only');
  });

  testWidgets('each link in a message is its own Tab stop, in text order', (
    tester,
  ) async {
    await pumpTile(tester, 'One https://a.example two https://b.example.');
    await focusBubble(tester);

    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.enter);

    expect(platform.launched, [Uri.parse('https://b.example')]);
    expect(actionsOpened, 0);
  });

  testWidgets('the link with keyboard focus is drawn highlighted', (
    tester,
  ) async {
    const url = 'https://example.com';
    await pumpTile(tester, 'See $url for details');
    await focusBubble(tester);

    expect(linkStyle(tester, url)?.backgroundColor, isNull);

    await press(tester, LogicalKeyboardKey.tab);

    expect(linkStyle(tester, url)?.backgroundColor, isNotNull);
  });

  testWidgets('Enter on the bubble itself still opens its actions', (
    tester,
  ) async {
    await pumpTile(tester, 'See https://example.com for details');
    await focusBubble(tester);

    await press(tester, LogicalKeyboardKey.enter);

    expect(actionsOpened, 1);
    expect(platform.launched, isEmpty);
  });
}
