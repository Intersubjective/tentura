// #605 (from #406): after joining a Post through an invite, the bar
// "Alice shared a post with you. [Open post]" was drawn over the room's
// message composer, the first thing the person wants to use. The composer
// is the room's body-bottom action, so a notice bar must sit above it —
// also when the bar was shown before the room (and its composer) came in.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../snack_bar_clearance_support.dart';

const _notice = 'Alice shared a post with you.';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

final _bodyKey = GlobalKey(debugLabel: 'post page');

/// false: the post page is still loading (no room yet).
final _roomLoaded = ValueNotifier<bool>(true);

Future<void> _pump(WidgetTester tester, {bool roomLoaded = true}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(GetIt.I.reset);
  }
  _roomLoaded.value = roomLoaded;
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: snackbarKey,
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            key: _bodyKey,
            body: ValueListenableBuilder<bool>(
              valueListenable: _roomLoaded,
              builder: (context, loaded, _) => loaded
                  ? BasicChatBody(
                      messages: const [],
                      myProfile: const Profile(id: 'me', displayName: 'Me'),
                      participants: const [],
                      isLoading: false,
                      imageRepository: ImageRepository(),
                      clipboardImageRepository: ClipboardImageRepository(),
                      enableComposerAttachments: false,
                      enableParticipantMentions: false,
                      onSend: (_, _) async => true,
                      onToggleReaction: (_, _) async {},
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settleBar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  // A move waits for the composer's height to settle, then the bar animates
  // in.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 750));
}

Future<void> _showInviteBar(WidgetTester tester) async {
  showSnackBar(
    tester.element(find.byKey(_bodyKey)),
    text: _notice,
    action: SnackBarAction(label: 'Open post', onPressed: () {}),
  );
  await _settleBar(tester);
}

void main() {
  testWidgets('the invite bar sits above the room composer', (tester) async {
    await _pump(tester);
    expect(find.byType(TextField), findsOneWidget);

    await _showInviteBar(tester);

    expectSnackBarClearsButton(
      tester,
      message: _notice,
      button: find.byType(TextField),
    );
  });

  testWidgets('a bar shown while the post loads moves above the composer '
      'once the room comes in', (tester) async {
    await _pump(tester, roomLoaded: false);
    await _showInviteBar(tester);
    expect(find.byType(TextField), findsNothing);

    _roomLoaded.value = true;
    await _settleBar(tester);

    expectSnackBarClearsButton(
      tester,
      message: _notice,
      button: find.byType(TextField),
    );
  });
}
