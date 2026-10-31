// #862: read-only locks must unfocus before disabling the composer so Flutter
// web never calls TextInput.updateConfig on a torn-down strategy.

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

import '../../features/beacon_threads/support/room_body_harness.dart'
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

  @override
  void initState() {
    super.initState();
    _readOnlyHint = null;
  }

  void lockReadOnly() => setState(() => _readOnlyHint = 'locked');

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
  testWidgets('composer loses focus before read-only disables the field', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: _Harness(key: harnessKey),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fieldFinder = find.byKey(TestIds.key(TestIds.roomMessageInput));
    await tester.tap(fieldFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fieldFinder).focusNode!.hasFocus, isTrue);

    harnessKey.currentState!.lockReadOnly();
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(fieldFinder).focusNode!.hasFocus, isFalse);
    expect(tester.widget<TextField>(fieldFinder).enabled, isFalse);
  });
}
