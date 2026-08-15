import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_receipt_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

AttentionReceipt _inviteReceipt({
  String actorUserId = 'invitee-1',
  String? targetEntityId = 'invitee-1',
  String title = 'Carol joined via your invitation',
  String body = 'Carol is now on Tentura.',
  String presentationPayloadJson = '{}',
}) {
  return AttentionReceipt(
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
    actorUserId: actorUserId,
    targetEntityId: targetEntityId,
    seenAt: DateTime.utc(2026, 8, 4),
  );
}

Widget _wrap(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _disposeCard(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  _FakeCapabilityRepository({
    required this.promptState,
    this.answerDelay = Duration.zero,
    this.skipDelay = Duration.zero,
  });

  InviteSeedPromptState promptState;
  final Duration answerDelay;
  final Duration skipDelay;

  String? lastAnswerSubjectId;
  List<String>? lastAnswerSlugs;
  String? lastSkipSubjectId;

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<InviteSeedPromptState> fetchInviteSeedPromptState(
    String subjectId,
  ) async => promptState;

  @override
  Future<void> inviteSeedPromptAnswer({
    required String subjectId,
    required List<String> slugs,
  }) async {
    lastAnswerSubjectId = subjectId;
    lastAnswerSlugs = List<String>.from(slugs);
    if (answerDelay > Duration.zero) {
      await Future<void>.delayed(answerDelay);
    }
    promptState = promptState.copyWith(state: PromptStateValue.answered);
  }

  @override
  Future<void> inviteSeedPromptSkip(String subjectId) async {
    lastSkipSubjectId = subjectId;
    if (skipDelay > Duration.zero) {
      await Future<void>.delayed(skipDelay);
    }
    promptState = promptState.copyWith(state: PromptStateValue.skipped);
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeProfileRepository implements ProfileRepositoryPort {
  _FakeProfileRepository(
    this.profile, {
    this.error,
    this.delay = Duration.zero,
  });

  Profile profile;
  Object? error;
  Duration delay;

  @override
  Future<Profile> fetchById(String id) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (error != null) throw error!;
    return profile;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

void main() {
  final l10n = L10nEn();

  late _FakeCapabilityRepository capabilityRepo;
  late _FakeProfileRepository profileRepo;

  InviteSeedPromptState pendingState() => const InviteSeedPromptState(
    inviterUserId: 'inviter-1',
    inviteeUserId: 'invitee-1',
    state: PromptStateValue.pending,
  );

  setUp(() {
    capabilityRepo = _FakeCapabilityRepository(promptState: pendingState());
    profileRepo = _FakeProfileRepository(
      const Profile(id: 'invitee-1', displayName: 'Carol'),
    );
    GetIt.I.registerSingleton<CapabilityRepositoryPort>(capabilityRepo);
    GetIt.I.registerSingleton<ProfileRepositoryPort>(profileRepo);
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<CapabilityRepositoryPort>()) {
      await GetIt.I.unregister<CapabilityRepositoryPort>();
    }
    if (GetIt.I.isRegistered<ProfileRepositoryPort>()) {
      await GetIt.I.unregister<ProfileRepositoryPort>();
    }
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    PromptStateValue state = PromptStateValue.pending,
    AttentionReceipt? receipt,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    capabilityRepo.promptState = capabilityRepo.promptState.copyWith(
      state: state,
    );
    await tester.pumpWidget(
      _wrap(
        InviteAcceptedReceiptCard(
          receipt: receipt ?? _inviteReceipt(),
          onTap: () {},
          onMarkSeen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('pending state renders chip picker with name-substituted copy', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(
      find.text(l10n.inviteSeedPromptQuestion('Carol')),
      findsOneWidget,
    );
    expect(find.text(l10n.inviteSeedPromptSubmit), findsOneWidget);
    expect(find.text(l10n.inviteSeedPromptSkip), findsOneWidget);
    expect(find.byType(CapabilityChipSet), findsOneWidget);
    await _disposeCard(tester);
  });

  testWidgets('answered state does not render chip picker', (tester) async {
    await pumpCard(tester, state: PromptStateValue.answered);

    expect(find.text(l10n.inviteSeedPromptQuestion('Carol')), findsNothing);
    expect(find.text(l10n.inviteSeedPromptSubmit), findsNothing);
    expect(find.text('Carol'), findsOneWidget);
    await _disposeCard(tester);
  });

  testWidgets('skipped state does not render chip picker', (tester) async {
    await pumpCard(tester, state: PromptStateValue.skipped);

    expect(find.text(l10n.inviteSeedPromptQuestion('Carol')), findsNothing);
    expect(find.text(l10n.inviteSeedPromptSkip), findsNothing);
    expect(find.text('Carol'), findsOneWidget);
    await _disposeCard(tester);
  });

  testWidgets('submitting selection calls answer and hides picker', (
    tester,
  ) async {
    await pumpCard(tester);

    await _selectTransportChip(tester);
    final submit = find.text(l10n.inviteSeedPromptSubmit);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(capabilityRepo.lastAnswerSubjectId, 'invitee-1');
    expect(capabilityRepo.lastAnswerSlugs, ['transport']);
    expect(find.text(l10n.inviteSeedPromptQuestion('Carol')), findsNothing);
    await _disposeCard(tester);
  });

  testWidgets('skip calls inviteSeedPromptSkip and hides picker', (
    tester,
  ) async {
    await pumpCard(tester);

    final skip = find.text(l10n.inviteSeedPromptSkip);
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pump();

    expect(capabilityRepo.lastSkipSubjectId, 'invitee-1');
    expect(find.text(l10n.inviteSeedPromptQuestion('Carol')), findsNothing);
    await _disposeCard(tester);
  });

  testWidgets('nickname title, canonical line, and origin body after load', (
    tester,
  ) async {
    profileRepo.profile = const Profile(
      id: 'invitee-1',
      contactName: 'Mom',
      displayName: 'Alice',
      handle: 'alice',
    );
    await pumpCard(
      tester,
      state: PromptStateValue.answered,
      receipt: _inviteReceipt(
        title: 'Alice · @alice',
        body: 'Created an account via your invitation. You are now connected.',
        presentationPayloadJson: '{"inviteOrigin":"new_account"}',
      ),
    );

    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('Alice · @alice'), findsOneWidget);
    expect(
      find.text(l10n.updatesInviteAcceptedBodyNewAccount),
      findsOneWidget,
    );
    await _disposeCard(tester);
  });

  testWidgets('loading keeps server title until profile is ready', (
    tester,
  ) async {
    profileRepo.delay = const Duration(milliseconds: 50);
    await pumpCard(
      tester,
      state: PromptStateValue.answered,
      receipt: _inviteReceipt(title: 'Alice · @alice'),
    );

    expect(find.text('Alice · @alice'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Carol'), findsOneWidget);
    await _disposeCard(tester);
  });

  testWidgets('profile fetch error keeps server title and body', (
    tester,
  ) async {
    profileRepo.error = Exception('missing');
    await pumpCard(
      tester,
      state: PromptStateValue.answered,
      receipt: _inviteReceipt(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Carol joined via your invitation'), findsOneWidget);
    expect(find.text('Carol is now on Tentura.'), findsOneWidget);
    await _disposeCard(tester);
  });
}
