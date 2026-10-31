// #862 phone + RU: read-only lock still unfocuses the Questions composer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/phone_surface.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit, RoomBodyHarnessProfileCubit;

class _FakeImageRepository extends Fake implements ImageRepository {}

class _FakeClipboardImageRepository extends Fake
    implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      const ClipboardImageReadResult.notFound();
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String? _readOnlyHint;

  void lockReadOnly() => setState(
    () => _readOnlyHint = lookupL10n(
      const Locale('ru'),
    ).beaconLobbyReadOnlyCantHelp,
  );

  @override
  Widget build(BuildContext context) {
    return BasicChatBody(
      messages: const [],
      myProfile: const Profile(id: 'me', displayName: 'Me'),
      participants: const [],
      isLoading: false,
      imageRepository: _FakeImageRepository(),
      clipboardImageRepository: _FakeClipboardImageRepository(),
      enableComposerAttachments: false,
      enableParticipantMentions: false,
      composerReadOnlyHint: _readOnlyHint,
      onSend: (_, _) async => true,
      onToggleReaction: (_, _) async {},
    );
  }
}

void main() {
  testWidgets('RU phone: read-only unfocuses composer without overflow', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final harnessKey = GlobalKey<_HarnessState>();
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
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(body: _Harness(key: harnessKey)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fieldFinder = find.byKey(TestIds.key(TestIds.roomMessageInput));
    await tester.tap(fieldFinder);
    await tester.pumpAndSettle();

    harnessKey.currentState!.lockReadOnly();
    await tester.pumpAndSettle();

    final l10n = lookupL10n(const Locale('ru'));
    expect(find.text(l10n.beaconLobbyReadOnlyCantHelp), findsOneWidget);
    expect(tester.widget<TextField>(fieldFinder).focusNode!.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });
}
