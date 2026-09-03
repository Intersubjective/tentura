import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_receipt_card.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_setup_sheet.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/test_ids.dart';

AttentionReceipt _inviteReceipt({
  String presentationPayloadJson = '{"inviteOrigin":"new_account"}',
  String title = 'Carol joined via your invitation',
  String body = 'Carol is now on Tentura.',
  DateTime? seenAt,
  bool hasSubject = true,
}) => AttentionReceipt(
  id: 'receipt-invite-1',
  category: 'connections',
  kind: 'inviteAccepted',
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/profile/view/invitee-1',
  createdAt: DateTime(2026, 8, 4, 14, 30),
  collapsedCount: 1,
  presentationKey: 'invite_accepted',
  presentationPayloadJson: presentationPayloadJson,
  actorUserId: hasSubject ? 'invitee-1' : null,
  targetEntityId: hasSubject ? 'invitee-1' : null,
  seenAt: seenAt,
);

final class _FakeSetupCase implements InviteAcceptedSetupPort {
  Profile profile = const Profile(id: 'invitee-1', displayName: 'Carol');
  InviteSeedPromptState prompt = const InviteSeedPromptState(
    inviterUserId: 'inviter-1',
    inviteeUserId: 'invitee-1',
    state: PromptStateValue.pending,
  );
  Completer<Profile>? profileCompleter;
  Exception? profileError;
  Exception? promptError;
  Exception? renameError;
  Exception? answerError;
  Exception? skipError;

  int fetchProfileCalls = 0;
  int fetchPromptCalls = 0;
  int renameCalls = 0;
  int answerCalls = 0;
  int skipCalls = 0;
  String? renamedTo;
  List<String>? answeredSlugs;

  @override
  Future<Profile> fetchProfile(String subjectId) async {
    fetchProfileCalls++;
    final completer = profileCompleter;
    if (completer != null) return completer.future;
    if (profileError case final error?) throw error;
    return profile;
  }

  @override
  Future<InviteSeedPromptState> fetchPrompt(String subjectId) async {
    fetchPromptCalls++;
    if (promptError case final error?) throw error;
    return prompt;
  }

  @override
  Future<void> rename({
    required String subjectId,
    required String privateName,
  }) async {
    renameCalls++;
    renamedTo = privateName;
    if (renameError case final error?) throw error;
    profile = profile.copyWith(contactName: privateName);
  }

  @override
  Future<void> answer({
    required String subjectId,
    required List<String> slugs,
  }) async {
    answerCalls++;
    answeredSlugs = List<String>.from(slugs);
    if (answerError case final error?) throw error;
  }

  @override
  Future<void> skip(String subjectId) async {
    skipCalls++;
    if (skipError case final error?) throw error;
  }
}

void main() {
  final l10n = L10nEn();
  late _FakeSetupCase setupCase;
  late int profileTaps;
  late int markSeenCalls;

  setUp(() {
    setupCase = _FakeSetupCase();
    profileTaps = 0;
    markSeenCalls = 0;
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    AttentionReceipt? receipt,
    Size size = const Size(390, 844),
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: InviteAcceptedReceiptCard(
                receipt: receipt ?? _inviteReceipt(),
                setupCase: setupCase,
                onTap: () => profileTaps++,
                onMarkSeen: () async => markSeenCalls++,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> openSetup(WidgetTester tester) async {
    await tester.tap(find.text(l10n.inviteAcceptedSetupAddDetails));
    await tester.pumpAndSettle();
    expect(find.byType(InviteAcceptedSetupSheet), findsOneWidget);
  }

  void selectCapability(WidgetTester tester) {
    tester.widget<CapabilityChipSet>(find.byType(CapabilityChipSet)).onChanged({
      'transport',
    });
  }

  group('origin and prompt projection', () {
    testWidgets('existing-account origin loads only profile', (tester) async {
      await pumpCard(
        tester,
        receipt: _inviteReceipt(
          presentationPayloadJson: '{"inviteOrigin":"existing_account"}',
        ),
      );

      expect(setupCase.fetchProfileCalls, 1);
      expect(setupCase.fetchPromptCalls, 0);
      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsNothing);
      expect(find.text(l10n.inviteAcceptedSetupRetry), findsNothing);
    });

    testWidgets('unknown origin never requests prompt state', (tester) async {
      await pumpCard(
        tester,
        receipt: _inviteReceipt(
          presentationPayloadJson: '{"inviteOrigin":"future_origin"}',
        ),
      );

      expect(setupCase.fetchProfileCalls, 1);
      expect(setupCase.fetchPromptCalls, 0);
      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsNothing);
    });

    testWidgets('missing subject renders ordinary card without retry', (
      tester,
    ) async {
      await pumpCard(
        tester,
        receipt: _inviteReceipt(hasSubject: false),
      );

      expect(setupCase.fetchProfileCalls, 0);
      expect(setupCase.fetchPromptCalls, 0);
      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsNothing);
      expect(find.text(l10n.inviteAcceptedSetupRetry), findsNothing);
    });

    testWidgets('pending prompt shows Add details without inline selector', (
      tester,
    ) async {
      await pumpCard(tester);

      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsOneWidget);
      expect(find.byType(CapabilityChipSet), findsNothing);
      expect(find.byType(UpdatesFeedTile), findsOneWidget);
    });

    for (final state in [PromptStateValue.answered, PromptStateValue.skipped]) {
      testWidgets('$state renders an ordinary card', (tester) async {
        setupCase.prompt = setupCase.prompt.copyWith(state: state);
        await pumpCard(tester);

        expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsNothing);
        expect(find.text(l10n.inviteAcceptedSetupRetry), findsNothing);
        expect(find.byType(CapabilityChipSet), findsNothing);
      });
    }

    testWidgets('genuine prompt error exposes compact retry', (tester) async {
      setupCase.promptError = Exception('offline');
      await pumpCard(tester);

      expect(find.text(l10n.inviteAcceptedSetupRetry), findsOneWidget);
      expect(find.text(l10n.inviteSeedPromptLoadError), findsNothing);

      setupCase.promptError = null;
      await tester.tap(find.text(l10n.inviteAcceptedSetupRetry));
      await tester.pumpAndSettle();

      expect(setupCase.fetchPromptCalls, 2);
      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsOneWidget);
    });

    testWidgets('profile failure keeps fallback receipt copy without retry', (
      tester,
    ) async {
      setupCase.profileError = Exception('missing profile');
      setupCase.prompt = setupCase.prompt.copyWith(
        state: PromptStateValue.answered,
      );
      await pumpCard(tester);

      expect(find.text('Carol joined via your invitation'), findsOneWidget);
      expect(find.text('Carol is now on Tentura.'), findsOneWidget);
      expect(find.text(l10n.inviteAcceptedSetupRetry), findsNothing);
    });

    testWidgets('loading keeps receipt copy until profile arrives', (
      tester,
    ) async {
      final completer = Completer<Profile>();
      setupCase.profileCompleter = completer;
      setupCase.prompt = setupCase.prompt.copyWith(
        state: PromptStateValue.answered,
      );
      await pumpCard(tester, settle: false);

      expect(find.text('Carol joined via your invitation'), findsOneWidget);
      completer.complete(
        const Profile(id: 'invitee-1', displayName: 'Carol'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Carol'), findsOneWidget);
    });
  });

  group('tap separation and adaptive host', () {
    testWidgets('setup action does not trigger profile navigation', (
      tester,
    ) async {
      await pumpCard(tester);
      await openSetup(tester);

      expect(profileTaps, 0);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupClose)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(UpdatesFeedTile));
      expect(profileTaps, 1);
    });

    testWidgets('compact window uses bottom sheet', (tester) async {
      await pumpCard(tester);
      await openSetup(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('regular window uses constrained dialog', (tester) async {
      await pumpCard(tester, size: const Size(700, 900));
      await openSetup(tester);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('modal outcomes', () {
    testWidgets('Save refreshes private title and marks seen once', (
      tester,
    ) async {
      setupCase.profile = const Profile(
        id: 'invitee-1',
        displayName: 'Carol',
      );
      await pumpCard(tester);
      await openSetup(tester);
      selectCapability(tester);
      await tester.pump();
      final changeName = find.byKey(
        TestIds.key(TestIds.inviteAcceptedSetupChangePrivateName),
      );
      await tester.ensureVisible(changeName);
      await tester.pumpAndSettle();
      await tester.tap(changeName);
      await tester.pumpAndSettle();
      final privateName = find.byKey(
        TestIds.key(TestIds.inviteAcceptedSetupPrivateName),
      );
      await tester.ensureVisible(privateName);
      await tester.pumpAndSettle();
      await tester.enterText(privateName, 'Mum');
      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupSave)),
      );
      await tester.pumpAndSettle();

      expect(setupCase.renameCalls, 1);
      expect(setupCase.answerCalls, 1);
      expect(setupCase.answeredSlugs, ['transport']);
      expect(markSeenCalls, 1);
      expect(find.text('Mum'), findsOneWidget);
      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsNothing);
    });

    testWidgets('Skip settles prompt and marks seen once', (tester) async {
      await pumpCard(tester);
      await openSetup(tester);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupSkip)),
      );
      await tester.pumpAndSettle();

      expect(setupCase.skipCalls, 1);
      expect(setupCase.answerCalls, 0);
      expect(setupCase.renameCalls, 0);
      expect(markSeenCalls, 1);
      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsNothing);
    });

    testWidgets('dismissal and failed mutation do not mark seen', (
      tester,
    ) async {
      setupCase.answerError = Exception('offline');
      await pumpCard(tester);
      await openSetup(tester);
      selectCapability(tester);
      await tester.pump();
      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupSave)),
      );
      await tester.pumpAndSettle();
      expect(markSeenCalls, 0);

      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupClose)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.inviteAcceptedSetupDiscardConfirm));
      await tester.pumpAndSettle();

      expect(markSeenCalls, 0);
      expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsOneWidget);
    });

    testWidgets(
      'dismiss after partial rename refreshes title but stays unread',
      (
        tester,
      ) async {
        setupCase.answerError = Exception('offline');
        await pumpCard(tester);
        await openSetup(tester);
        selectCapability(tester);
        await tester.pump();
        final changeName = find.byKey(
          TestIds.key(TestIds.inviteAcceptedSetupChangePrivateName),
        );
        await tester.ensureVisible(changeName);
        await tester.pumpAndSettle();
        await tester.tap(changeName);
        await tester.pumpAndSettle();
        final privateName = find.byKey(
          TestIds.key(TestIds.inviteAcceptedSetupPrivateName),
        );
        await tester.ensureVisible(privateName);
        await tester.pumpAndSettle();
        await tester.enterText(privateName, 'Mum');
        await tester.tap(
          find.byKey(TestIds.key(TestIds.inviteAcceptedSetupSave)),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(TestIds.key(TestIds.inviteAcceptedSetupClose)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.inviteAcceptedSetupDiscardConfirm));
        await tester.pumpAndSettle();

        expect(markSeenCalls, 0);
        expect(find.text('Mum'), findsOneWidget);
        expect(find.text(l10n.inviteAcceptedSetupAddDetails), findsOneWidget);
      },
    );
  });
}
