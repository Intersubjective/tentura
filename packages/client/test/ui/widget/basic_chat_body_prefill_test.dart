import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

class _FakeImageRepository extends Fake implements ImageRepository {}

class _FakeClipboardImageRepository extends Fake
    implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      const ClipboardImageReadResult.notFound();
}

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

/// Composer prefill from another surface (plan «Не успеваю», #220).
void main() {
  Future<void> pumpBody(
    WidgetTester tester, {
    String? prefill,
    int prefillSeq = 0,
    VoidCallback? onApplied,
  }) => tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
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
              enableParticipantMentions: false,
              onSend: (body, uploads) async => true,
              composerPrefill: prefill,
              composerPrefillSeq: prefillSeq,
              onComposerPrefillApplied: onApplied,
            ),
          ),
        ),
      ),
    ),
  );

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('prefill goes into the field once per seq', (tester) async {
    var applied = 0;
    const quote = "› Step 3: Build frame — can't make it: ";
    await pumpBody(tester);
    expect(fieldText(tester), isEmpty);

    await pumpBody(
      tester,
      prefill: quote,
      prefillSeq: 1,
      onApplied: () => applied++,
    );
    await tester.pump();
    expect(fieldText(tester), quote);
    expect(applied, 1);

    // The person edits; the same seq never overwrites their text.
    await tester.enterText(find.byType(TextField), '${quote}traffic');
    await pumpBody(
      tester,
      prefill: quote,
      prefillSeq: 1,
      onApplied: () => applied++,
    );
    await tester.pump();
    expect(fieldText(tester), '${quote}traffic');
    expect(applied, 1);
  });
}
