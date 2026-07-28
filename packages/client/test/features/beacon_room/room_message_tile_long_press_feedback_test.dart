import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
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

RoomMessage _plainMessage() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: 'Hello there',
  createdAt: DateTime.utc(2026),
);

const _logicalSize = Size(360, 600);

Widget _harness(Widget child, {bool disableAnimations = false}) {
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
        data: MediaQueryData(
          size: _logicalSize,
          disableAnimations: disableAnimations,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(width: _logicalSize.width, child: child),
          ),
        ),
      ),
    ),
  );
}

Finder get _scaleFinder =>
    find.byKey(TestIds.key(TestIds.roomMessageBubblePressScale));

double _bubbleScale(WidgetTester tester) =>
    tester.widget<Transform>(_scaleFinder).transform.getMaxScaleOnAxis();

Widget _messageTile({required void Function(RoomMessage) onActionsPressed}) {
  return RoomMessageTile(
    message: _plainMessage(),
    myProfile: const Profile(id: 'viewer', displayName: 'Me'),
    onToggleReaction: (_, _) async {},
    onActionsPressed: onActionsPressed,
  );
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(
      _FakePlatformRepository(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('bubble grows during long-press hold and opens actions once',
      (tester) async {
    var actionsCount = 0;

    await tester.pumpWidget(
      _harness(_messageTile(onActionsPressed: (_) => actionsCount++)),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(_scaleFinder);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));
    expect(_bubbleScale(tester), greaterThan(1.0));

    await tester.pump(const Duration(milliseconds: 260));
    expect(actionsCount, 1);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_bubbleScale(tester), closeTo(1.0, 0.001));
  });

  testWidgets('pointer cancel resets scale without opening actions',
      (tester) async {
    var actionsCount = 0;

    await tester.pumpWidget(
      _harness(_messageTile(onActionsPressed: (_) => actionsCount++)),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(_scaleFinder),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));
    expect(_bubbleScale(tester), greaterThan(1.0));

    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(_bubbleScale(tester), closeTo(1.0, 0.001));
    expect(actionsCount, 0);
  });

  testWidgets('early release resets scale without opening actions',
      (tester) async {
    var actionsCount = 0;

    await tester.pumpWidget(
      _harness(_messageTile(onActionsPressed: (_) => actionsCount++)),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(_scaleFinder),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_bubbleScale(tester), closeTo(1.0, 0.001));
    expect(actionsCount, 0);
  });

  testWidgets('no visible growth before lead-in interval', (tester) async {
    await tester.pumpWidget(
      _harness(_messageTile(onActionsPressed: (_) {})),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(_scaleFinder),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 80));
    expect(_bubbleScale(tester), closeTo(1.0, 0.001));

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion skips grow but still opens actions', (tester) async {
    var actionsCount = 0;

    await tester.pumpWidget(
      _harness(
        _messageTile(onActionsPressed: (_) => actionsCount++),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(_scaleFinder),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));
    expect(_bubbleScale(tester), closeTo(1.0, 0.001));

    await tester.pump(const Duration(milliseconds: 260));
    expect(actionsCount, 1);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
