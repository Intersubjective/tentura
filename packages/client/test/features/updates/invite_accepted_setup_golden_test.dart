import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_receipt_card.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_setup_sheet.dart';
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
}

AttentionReceipt _receipt() => AttentionReceipt(
  id: 'receipt-golden',
  category: 'connections',
  kind: 'inviteAccepted',
  priority: 'normal',
  title: 'Carol · @carol',
  body: 'Created an account via your invitation. You are now connected.',
  actionUrl: '/profile/view/invitee-1',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  collapsedCount: 1,
  presentationKey: 'invite_accepted',
  presentationPayloadJson: '{"inviteOrigin":"new_account"}',
  actorUserId: 'invitee-1',
  targetEntityId: 'invitee-1',
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required ThemeData theme,
}) async {
  const size = Size(390, 220);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('card-golden'),
                child: InviteAcceptedReceiptCard(
                  receipt: _receipt(),
                  setupCase: _GoldenSetupCase(),
                  onTap: () {},
                  onMarkSeen: () async {},
                  onMarkUnseen: () {},
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

Future<void> _pumpModal(
  WidgetTester tester, {
  required ThemeData theme,
}) async {
  const size = Size(390, 844);
  final setupCase = _GoldenSetupCase();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => InviteAcceptedSetupSheet.show(
                  context: context,
                  subjectId: 'invitee-1',
                  profile: _GoldenSetupCase.profile,
                  prompt: _GoldenSetupCase.prompt,
                  setupCase: setupCase,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final variant in <(String, ThemeData)>[
    ('light', TenturaTheme.light()),
    ('dark', TenturaTheme.dark()),
  ]) {
    testWidgets('compact invite receipt ${variant.$1}', (tester) async {
      await _pumpCard(tester, theme: variant.$2);
      await expectLater(
        find.byKey(const Key('card-golden')),
        matchesGoldenFile(
          'goldens/invite_accepted_compact_card_${variant.$1}.png',
        ),
      );
    });

    testWidgets('invite setup modal ${variant.$1}', (tester) async {
      await _pumpModal(tester, theme: variant.$2);
      await expectLater(
        find.byType(BottomSheet),
        matchesGoldenFile(
          'goldens/invite_accepted_setup_modal_${variant.$1}.png',
        ),
      );
    });
  }
}
