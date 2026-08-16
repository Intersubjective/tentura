import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/profile_view/ui/widget/edit_seed_suggestion_section.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/test_ids.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _expandLogisticsGroup(WidgetTester tester) async {
  final tile = find.text('Logistics');
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _selectTransportChip(WidgetTester tester) async {
  await _expandLogisticsGroup(tester);
  final transport = find.text('Transport');
  await tester.ensureVisible(transport);
  await tester.pumpAndSettle();
  await tester.tap(transport);
  await tester.pump();
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  _FakeCapabilityRepository({required this.promptState, this.throwOnFetch = false});

  InviteSeedPromptState promptState;
  bool throwOnFetch;

  String? lastSeedSubjectId;
  List<String>? lastSeedSlugs;

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();

  @override
  Future<InviteSeedPromptState> fetchInviteSeedPromptState(
    String subjectId,
  ) async {
    if (throwOnFetch) throw StateError('not inviter');
    return promptState;
  }

  @override
  Future<void> seedRoutingAttestation({
    required String subjectId,
    required List<String> slugs,
  }) async {
    lastSeedSubjectId = subjectId;
    lastSeedSlugs = List<String>.from(slugs);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final l10n = L10nEn();
  const inviteeProfile = Profile(id: 'invitee-1', displayName: 'Carol');

  late _FakeCapabilityRepository capabilityRepo;

  InviteSeedPromptState promptState(
    PromptStateValue state, {
    List<String> slugs = const [],
  }) => InviteSeedPromptState(
    inviterUserId: 'inviter-1',
    inviteeUserId: inviteeProfile.id,
    state: state,
    slugs: slugs,
  );

  setUp(() {
    capabilityRepo = _FakeCapabilityRepository(
      promptState: promptState(PromptStateValue.answered),
    );
    GetIt.I.registerSingleton<CapabilityRepositoryPort>(capabilityRepo);
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<CapabilityRepositoryPort>()) {
      await GetIt.I.unregister<CapabilityRepositoryPort>();
    }
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    PromptStateValue state = PromptStateValue.answered,
    List<String> slugs = const [],
    bool throwOnFetch = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    capabilityRepo.throwOnFetch = throwOnFetch;
    capabilityRepo.promptState = promptState(state, slugs: slugs);

    await tester.pumpWidget(
      _wrap(EditSeedSuggestionSection(profile: inviteeProfile)),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('non-inviter fetch failure renders nothing', (tester) async {
    await pumpSection(tester, throwOnFetch: true);

    expect(find.byType(CapabilityChipSet), findsNothing);
    expect(find.text(l10n.profileSeedSuggestionSave), findsNothing);
  });

  testWidgets('pending state renders nothing', (tester) async {
    await pumpSection(tester, state: PromptStateValue.pending);

    expect(find.byType(CapabilityChipSet), findsNothing);
    expect(find.text(l10n.profileSeedSuggestionSave), findsNothing);
    expect(find.text(l10n.inviteSeedPromptQuestion('Carol')), findsNothing);
  });

  testWidgets(
    'answered with saved slugs hydrates selected chips without tapping',
    (tester) async {
      await pumpSection(
        tester,
        state: PromptStateValue.answered,
        slugs: const ['transport'],
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.profileSeedSuggestionEditPrompt('Carol')),
        findsOneWidget,
      );
      expect(find.text(l10n.profileSeedSuggestionWithdraw), findsOneWidget);

      // Accordion mode keeps collapsed groups' chips out of the tree.
      // Expand Logistics only — do not tap Transport — then read selected.
      await _expandLogisticsGroup(tester);

      final transportChip = find.byKey(
        TestIds.key(TestIds.capabilityChip('transport')),
      );
      expect(transportChip, findsOneWidget);
      expect(tester.widget<FilterChip>(transportChip).selected, isTrue);
    },
  );

  testWidgets('answered with empty slugs shows edit copy without withdraw', (
    tester,
  ) async {
    await pumpSection(tester, state: PromptStateValue.answered);

    expect(
      find.text(l10n.profileSeedSuggestionEditPrompt('Carol')),
      findsOneWidget,
    );
    expect(find.text(l10n.profileSeedSuggestionWithdraw), findsNothing);
    expect(find.byType(CapabilityChipSet), findsOneWidget);
  });

  testWidgets('answered state shows editable picker and save calls seed', (
    tester,
  ) async {
    await pumpSection(tester, state: PromptStateValue.answered);

    expect(
      find.text(l10n.profileSeedSuggestionEditPrompt('Carol')),
      findsOneWidget,
    );
    expect(find.byType(CapabilityChipSet), findsOneWidget);
    expect(find.text(l10n.profileSeedSuggestionWithdraw), findsNothing);

    await _selectTransportChip(tester);
    expect(find.text(l10n.profileSeedSuggestionWithdraw), findsOneWidget);
    final save = find.text(l10n.profileSeedSuggestionSave);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();

    expect(capabilityRepo.lastSeedSubjectId, 'invitee-1');
    expect(capabilityRepo.lastSeedSlugs, ['transport']);
  });

  testWidgets('withdraw calls seedRoutingAttestation with empty slugs', (
    tester,
  ) async {
    await pumpSection(
      tester,
      state: PromptStateValue.answered,
      slugs: const ['transport'],
    );
    await tester.pumpAndSettle();

    final withdraw = find.text(l10n.profileSeedSuggestionWithdraw);
    await tester.ensureVisible(withdraw);
    await tester.tap(withdraw);
    await tester.pump();

    expect(capabilityRepo.lastSeedSubjectId, 'invitee-1');
    expect(capabilityRepo.lastSeedSlugs, isEmpty);
    expect(find.text(l10n.profileSeedSuggestionWithdraw), findsNothing);
    expect(
      find.text(l10n.profileSeedSuggestionEditPrompt('Carol')),
      findsOneWidget,
    );
  });

  testWidgets('skipped with slugs shows edit copy and withdraw', (tester) async {
    await pumpSection(
      tester,
      state: PromptStateValue.skipped,
      slugs: const ['transport'],
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.profileSeedSuggestionEditPrompt('Carol')),
      findsOneWidget,
    );
    expect(find.text(l10n.profileSeedSuggestionWithdraw), findsOneWidget);
  });

  testWidgets('skipped state shows add prompt without withdraw', (tester) async {
    await pumpSection(tester, state: PromptStateValue.skipped);

    expect(
      find.text(l10n.profileSeedSuggestionAddPrompt('Carol')),
      findsOneWidget,
    );
    expect(find.text(l10n.profileSeedSuggestionWithdraw), findsNothing);
    expect(find.byType(CapabilityChipSet), findsOneWidget);
  });
}
