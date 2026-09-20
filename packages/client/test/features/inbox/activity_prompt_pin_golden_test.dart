// CHANGES IN U16c-2: these four goldens used to be the `prompt` cases of
// `activity_offer_card_golden_test.dart`. `ActivityOfferCard` is retired, but
// what they assert — how the Activity prompt pin renders inside
// `ActivityOfferBoundedShell` — is not: the shell and
// `InviteAcceptedReceiptCard` both survive the retirement, and the stream
// builds them directly now. The PNGs are the same bytes under a new name, so
// a byte-identical pass is itself the evidence that removing the wrapper
// changed no pixel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_receipt_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final class _GoldenSetupCase implements InviteAcceptedSetupPort {
  static const profile = Profile(
    id: 'invitee-1',
    displayName: 'Carol',
    handle: 'carol',
  );

  static const prompt = InviteSeedPromptState(
    inviterUserId: 'inviter-1',
    inviteeUserId: 'invitee-1',
    state: PromptStateValue.pending,
  );

  @override
  Future<Profile> fetchProfile(String subjectId) async => profile;

  @override
  Future<InviteSeedPromptState> fetchPrompt(String subjectId) async => prompt;

  @override
  Future<void> answer({
    required String subjectId,
    required List<String> slugs,
  }) async {}

  @override
  Future<void> rename({
    required String subjectId,
    required String privateName,
  }) async {}

  @override
  Future<void> skip(String subjectId) async {}

  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async =>
      {};
}

AttentionReceipt _promptReceipt() => AttentionReceipt(
  id: 'receipt-prompt-1',
  category: 'connections',
  kind: 'inviteAccepted',
  priority: 'normal',
  title: 'Carol · @carol',
  body: 'Joined via your invitation. You are now connected.',
  actionUrl: '/profile/view/invitee-1',
  createdAt: DateTime.utc(2026, 6, 20, 11, 0),
  collapsedCount: 1,
  presentationKey: 'invite_accepted',
  presentationPayloadJson: '{"inviteOrigin":"new_account"}',
  surface: AttentionSurface.activity,
  actorUserId: 'invitee-1',
  targetEntityId: 'invitee-1',
);

Future<void> _pumpPromptGolden(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required Brightness brightness,
  required String goldenName,
  TextScaler? textScaler,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: brightness == Brightness.light
          ? TenturaTheme.light()
          : TenturaTheme.dark(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler ?? TextScaler.noScaling,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: size.width,
                  child: InviteAcceptedReceiptCard(
                    receipt: _promptReceipt(),
                    promptProjection: const PromptProjection.known(
                      _GoldenSetupCase.prompt,
                    ),
                    setupCase: _GoldenSetupCase(),
                    onTap: () {},
                    onMarkSeen: () async {},
                    onMarkUnseen: () {},
                    activityOfferBoundedShell: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$goldenName'),
  );
}

void main() {
  const size = Size(360, 220);

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'light' : 'dark';
    for (final locale in const [Locale('en'), Locale('ru')]) {
      final lang = locale.languageCode;
      testWidgets('activity prompt pin $theme $lang', (tester) async {
        await _pumpPromptGolden(
          tester,
          size: size,
          locale: locale,
          brightness: brightness,
          goldenName: 'activity_prompt_pin_${theme}_$lang.png',
        );
      },
        tags: 'golden',
      );
    }
  }
}
