import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_setup_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/test_ids.dart';

final class _FakeSetupCase implements InviteAcceptedSetupPort {
  final List<Exception?> renameOutcomes = [];
  final List<Exception?> answerOutcomes = [];
  final List<Exception?> skipOutcomes = [];

  int renameCalls = 0;
  int answerCalls = 0;
  int skipCalls = 0;
  final List<String> renamedNames = [];
  final List<List<String>> answers = [];

  Exception? _take(List<Exception?> outcomes) =>
      outcomes.isEmpty ? null : outcomes.removeAt(0);

  @override
  Future<void> rename({
    required String subjectId,
    required String privateName,
  }) async {
    renameCalls++;
    renamedNames.add(privateName);
    if (_take(renameOutcomes) case final error?) throw error;
  }

  @override
  Future<void> answer({
    required String subjectId,
    required List<String> slugs,
  }) async {
    answerCalls++;
    answers.add(List<String>.from(slugs));
    if (_take(answerOutcomes) case final error?) throw error;
  }

  @override
  Future<void> skip(String subjectId) async {
    skipCalls++;
    if (_take(skipOutcomes) case final error?) throw error;
  }

  @override
  Future<Profile> fetchProfile(String subjectId) => throw UnimplementedError();

  @override
  Future<InviteSeedPromptState> fetchPrompt(String subjectId) =>
      throw UnimplementedError();
}

void main() {
  final l10n = L10nEn();
  const prompt = InviteSeedPromptState(
    inviterUserId: 'inviter-1',
    inviteeUserId: 'invitee-1',
    state: PromptStateValue.pending,
  );
  late _FakeSetupCase setupCase;
  InviteAcceptedSetupResult? result;

  setUp(() {
    setupCase = _FakeSetupCase();
    result = null;
  });

  Future<void> pumpAndOpen(
    WidgetTester tester, {
    Profile profile = const Profile(
      id: 'invitee-1',
      displayName: 'Carol',
    ),
    Size size = const Size(390, 844),
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
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await InviteAcceptedSetupSheet.show(
                      context: context,
                      subjectId: 'invitee-1',
                      profile: profile,
                      prompt: prompt,
                      setupCase: setupCase,
                    );
                  },
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

  void selectCapability(WidgetTester tester, [String slug = 'transport']) {
    tester.widget<CapabilityChipSet>(find.byType(CapabilityChipSet)).onChanged({
      slug,
    });
  }

  Future<void> enableAndEnterPrivateName(
    WidgetTester tester,
    String name,
  ) async {
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
    await tester.enterText(privateName, name);
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(
      find.byKey(TestIds.key(TestIds.inviteAcceptedSetupSave)),
    );
    await tester.pumpAndSettle();
  }

  group('selection and private name', () {
    testWidgets('selector is capped at three and Save validates empty choice', (
      tester,
    ) async {
      await pumpAndOpen(tester);

      expect(
        tester
            .widget<CapabilityChipSet>(find.byType(CapabilityChipSet))
            .maxSelection,
        3,
      );
      tester
          .widget<CapabilityChipSet>(find.byType(CapabilityChipSet))
          .onChanged({'transport', 'storage', 'pickup_delivery'});
      await tester.pumpAndSettle();
      final fourthChip = find.byKey(
        TestIds.key(TestIds.capabilityChip('tools')),
      );
      if (fourthChip.evaluate().isEmpty) {
        await tester.tap(find.text(l10n.capabilityGroupLogistics));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<FilterChip>(fourthChip).onSelected, isNull);

      tester
          .widget<CapabilityChipSet>(find.byType(CapabilityChipSet))
          .onChanged({});
      await tester.pump();
      await tapSave(tester);

      expect(
        find.text(l10n.inviteAcceptedSetupSelectCapabilityError),
        findsOneWidget,
      );
      expect(setupCase.answerCalls, 0);
      expect(find.byType(InviteAcceptedSetupSheet), findsOneWidget);
    });

    testWidgets('private name starts from current private name', (
      tester,
    ) async {
      await pumpAndOpen(
        tester,
        profile: const Profile(
          id: 'invitee-1',
          displayName: 'Carol',
          contactName: 'Caz',
        ),
      );
      final changeName = find.byKey(
        TestIds.key(TestIds.inviteAcceptedSetupChangePrivateName),
      );
      await tester.ensureVisible(changeName);
      await tester.pumpAndSettle();
      await tester.tap(changeName);
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupPrivateName)),
      );
      expect(field.controller?.text, 'Caz');
    });

    testWidgets('private name falls back to public name', (tester) async {
      await pumpAndOpen(tester);
      final changeName = find.byKey(
        TestIds.key(TestIds.inviteAcceptedSetupChangePrivateName),
      );
      await tester.ensureVisible(changeName);
      await tester.pumpAndSettle();
      await tester.tap(changeName);
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupPrivateName)),
      );
      expect(field.controller?.text, 'Carol');
    });

    testWidgets('Skip discards capability and private-name edits', (
      tester,
    ) async {
      await pumpAndOpen(tester);
      selectCapability(tester);
      await tester.pump();
      await enableAndEnterPrivateName(tester, 'Mum');

      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupSkip)),
      );
      await tester.pumpAndSettle();

      expect(setupCase.skipCalls, 1);
      expect(setupCase.renameCalls, 0);
      expect(setupCase.answerCalls, 0);
      expect(result?.action, InviteAcceptedSetupAction.skipped);
      expect(result?.profile.contactName, isEmpty);
    });
  });

  group('partial failure contract', () {
    testWidgets('rename failure prevents capability submission', (
      tester,
    ) async {
      setupCase.renameOutcomes.add(Exception('rename failed'));
      await pumpAndOpen(tester);
      selectCapability(tester);
      await tester.pump();
      await enableAndEnterPrivateName(tester, 'Mum');
      await tapSave(tester);

      expect(setupCase.renameCalls, 1);
      expect(setupCase.answerCalls, 0);
      expect(find.text(l10n.inviteAcceptedSetupRenameError), findsOneWidget);
      expect(find.byType(InviteAcceptedSetupSheet), findsOneWidget);
    });

    testWidgets('capability retry does not repeat a successful rename', (
      tester,
    ) async {
      setupCase.answerOutcomes.add(Exception('answer failed'));
      await pumpAndOpen(tester);
      selectCapability(tester);
      await tester.pump();
      await enableAndEnterPrivateName(tester, 'Mum');
      await tapSave(tester);

      expect(setupCase.renameCalls, 1);
      expect(setupCase.answerCalls, 1);
      expect(
        find.text(l10n.inviteAcceptedSetupPartialSuccessError),
        findsOneWidget,
      );

      await tapSave(tester);

      expect(setupCase.renameCalls, 1);
      expect(setupCase.answerCalls, 2);
      expect(result?.action, InviteAcceptedSetupAction.saved);
      expect(result?.profile.contactName, 'Mum');
    });

    testWidgets('editing name again after partial success renames on retry', (
      tester,
    ) async {
      setupCase.answerOutcomes.add(Exception('answer failed'));
      await pumpAndOpen(tester);
      selectCapability(tester);
      await tester.pump();
      await enableAndEnterPrivateName(tester, 'Mum');
      await tapSave(tester);

      await tester.enterText(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupPrivateName)),
        'Mama',
      );
      await tapSave(tester);

      expect(setupCase.renameCalls, 2);
      expect(setupCase.renamedNames, ['Mum', 'Mama']);
      expect(setupCase.answerCalls, 2);
      expect(result?.profile.contactName, 'Mama');
    });

    testWidgets('Skip after partial success keeps persisted private name', (
      tester,
    ) async {
      setupCase.answerOutcomes.add(Exception('answer failed'));
      await pumpAndOpen(tester);
      selectCapability(tester);
      await tester.pump();
      await enableAndEnterPrivateName(tester, 'Mum');
      await tapSave(tester);

      await tester.enterText(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupPrivateName)),
        'Unsaved edit',
      );
      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupSkip)),
      );
      await tester.pumpAndSettle();

      expect(setupCase.renameCalls, 1);
      expect(setupCase.skipCalls, 1);
      expect(result?.action, InviteAcceptedSetupAction.skipped);
      expect(result?.profile.contactName, 'Mum');
    });
  });

  group('dismiss guard', () {
    Future<void> makeDirty(WidgetTester tester) async {
      selectCapability(tester);
      await tester.pump();
    }

    Future<void> expectDiscardAndConfirm(WidgetTester tester) async {
      expect(
        find.text(l10n.inviteAcceptedSetupDiscardTitle),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.inviteAcceptedSetupDiscardConfirm));
      await tester.pumpAndSettle();
      expect(find.byType(InviteAcceptedSetupSheet), findsNothing);
      expect(setupCase.answerCalls, 0);
      expect(setupCase.skipCalls, 0);
      expect(result, isNull);
    }

    testWidgets('barrier tap confirms discard and leaves prompt untouched', (
      tester,
    ) async {
      await pumpAndOpen(tester);
      await makeDirty(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await expectDiscardAndConfirm(tester);
    });

    testWidgets('system back confirms discard and leaves prompt untouched', (
      tester,
    ) async {
      await pumpAndOpen(tester);
      await makeDirty(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await expectDiscardAndConfirm(tester);
    });

    testWidgets('drag dismissal confirms discard and leaves prompt untouched', (
      tester,
    ) async {
      await pumpAndOpen(tester);
      await makeDirty(tester);
      await tester.drag(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupDragHandle)),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await expectDiscardAndConfirm(tester);
    });

    testWidgets('explicit close confirms discard and can keep editing', (
      tester,
    ) async {
      await pumpAndOpen(tester);
      await makeDirty(tester);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.inviteAcceptedSetupClose)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.inviteAcceptedSetupDiscardTitle),
        findsOneWidget,
      );
      await tester.tap(
        find.text(l10n.inviteAcceptedSetupDiscardKeepEditing),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InviteAcceptedSetupSheet), findsOneWidget);
      expect(result, isNull);
    });
  });
}
