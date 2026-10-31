// #862: disabling the room composer while it still has focus must not flip
// TextField.enabled on web (see webSafeTextFieldEnabled).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/platform/web_safe_text_field_enabled.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../features/beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit, RoomBodyHarnessProfileCubit;

class _FakeImageRepository extends Fake implements ImageRepository {}

class _FakeClipboardImageRepository extends Fake
    implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      const ClipboardImageReadResult.notFound();
}

void main() {
  setUp(() => debugWebTextInputConfigHold = true);
  tearDown(() => debugWebTextInputConfigHold = false);

  testWidgets('composer stays enabled while focused during a slow send', (
    tester,
  ) async {
    final sendDone = Completer<bool>();
    await tester.binding.setSurfaceSize(const Size(700, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(
            value: RoomBodyHarnessProfileCubit(
              const Profile(id: 'me', displayName: 'Me'),
            ),
          ),
          BlocProvider<PresenceCubit>.value(
            value: RoomBodyHarnessPresenceCubit(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: BasicChatBody(
                messages: const [],
                myProfile: const Profile(id: 'me', displayName: 'Me'),
                participants: const [],
                isLoading: false,
                imageRepository: _FakeImageRepository(),
                clipboardImageRepository: _FakeClipboardImageRepository(),
                enableComposerAttachments: false,
                enableParticipantMentions: false,
                onSend: (_, _) => sendDone.future,
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fieldFinder = find.byKey(TestIds.key(TestIds.roomMessageInput));
    await tester.enterText(fieldFinder, 'hello');
    await tester.tap(fieldFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fieldFinder).focusNode!.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(tester.widget<TextField>(fieldFinder).enabled, isTrue);
    expect(tester.takeException(), isNull);

    sendDone.complete(true);
    await tester.pumpAndSettle();
  });
}
