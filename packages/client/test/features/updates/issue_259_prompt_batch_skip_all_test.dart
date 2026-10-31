// #259: «Skip all (N)» in the batch sheet for pending «Set up connection»
// prompts (ichorid 2026-10-31T16:16Z). No time-based expiry: one deliberate,
// confirmed gesture skips every pending prompt in order, applies each settled
// prompt through the cubit, reports only what it achieved, and closes the
// sheet when nothing is pending.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/prompt_batch_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _EmptyRepository extends AttentionRepositoryFake {
  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

/// Records every skip in order; failOnce subjects fail on their first skip.
final class _SkipSetup implements InviteAcceptedSetupPort {
  _SkipSetup({Set<String> failOnce = const {}, this.failAlways = false})
    : _failOnce = {...failOnce};

  final Set<String> _failOnce;
  final bool failAlways;
  final skipCalls = <String>[];

  @override
  Future<void> skip(String subjectId) async {
    skipCalls.add(subjectId);
    if (failAlways || _failOnce.remove(subjectId)) {
      throw StateError('skip refused for $subjectId');
    }
  }

  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async => {};

  @override
  Future<Profile> fetchProfile(String subjectId) async =>
      Profile(id: subjectId, displayName: 'Person $subjectId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app font (Inter), as in beacon_surface_tabs_360_labels_test: the test
/// font's 1 em glyphs are far wider than any real label, so fit is measured
/// with the font the app ships.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

const _subjects = ['s1', 's2', 's3', 's4'];

AttentionReceipt _receipt(String subjectId, int index) => AttentionReceipt(
  id: 'r-$subjectId',
  category: 'connections',
  kind: 'inviteAccepted',
  priority: 'normal',
  title: 'Joined $subjectId',
  body: 'Body',
  actionUrl: '/profile/view/$subjectId',
  createdAt: DateTime.now().subtract(Duration(hours: 1 + index)),
  collapsedCount: 1,
  presentationKey: 'invite_accepted',
  presentationPayloadJson: '{"inviteOrigin":"new_account"}',
  surface: AttentionSurface.activity,
  actorUserId: subjectId,
  targetEntityId: subjectId,
);

InviteSeedPromptState _pending(String subjectId) => InviteSeedPromptState(
  inviterUserId: 'viewer',
  inviteeUserId: subjectId,
  state: PromptStateValue.pending,
);

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _openKey = Key('open-batch');

/// Mounts a host that opens [PromptBatchSheet] for the four pending prompts,
/// and opens it. Returns the cubit the sheet settles prompts through.
Future<UpdatesFeedCubit> _openSheet(
  WidgetTester tester, {
  required _SkipSetup setup,
  Locale locale = const Locale('en'),
}) async {
  await usePhoneSurface(tester);
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    _EmptyRepository(),
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('issue-259'),
  );
  accounts.emit('viewer');
  await _drain();

  if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
    GetIt.I.unregister<InviteAcceptedSetupPort>();
  }
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(setup);

  final cubit = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: setup,
    realtime: sync.case_,
    logger: Logger('issue-259-cubit'),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await _drain(24);
  for (final id in _subjects) {
    cubit.applyKnownPrompt(id, _pending(id));
  }
  addTearDown(() async {
    await cubit.close();
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
  });

  final receipts = [
    for (var i = 0; i < _subjects.length; i++) _receipt(_subjects[i], i),
  ];
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: kPhoneSurface),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: _openKey,
                  onPressed: () => unawaited(
                    PromptBatchSheet.show(
                      context: context,
                      cubit: cubit,
                      receipts: receipts,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(_openKey));
  await _settle(tester);
  expect(find.byType(PromptBatchSheet), findsOneWidget);
  return cubit;
}

Finder _skipAll(L10n l10n, int count) =>
    find.widgetWithText(TenturaTextAction, l10n.promptBatchSkipAll(count));

Future<void> _confirmSkipAll(WidgetTester tester, L10n l10n, int count) async {
  await tester.tap(_skipAll(l10n, count));
  await _settle(tester);
  expect(find.text(l10n.promptBatchSkipAllConfirmTitle(count)), findsOneWidget);
  expect(find.text(l10n.promptBatchSkipAllConfirmBody), findsOneWidget);
  await tester.tap(find.text(l10n.promptBatchSkipAllConfirm));
  await _settle(tester);
}

void _expectAllSkipped(UpdatesFeedCubit cubit, Iterable<String> ids) {
  for (final id in ids) {
    final projection = cubit.state.promptProjectionFor(id);
    expect(projection.isKnownSettled, isTrue, reason: id);
    expect(projection.isKnownPending, isFalse, reason: id);
  }
}

/// Laid out whole: one line, nothing ellipsised or clipped.
void _expectWholeLine(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.size.width + 0.5),
      reason: '«$text» is clipped',
    );
  }
}

void main() {
  setUpAll(_loadInter);

  for (final locale in const [Locale('en'), Locale('ru')]) {
    final l10n = lookupL10n(locale);
    final tag = locale.languageCode.toUpperCase();

    testWidgets('#259 $tag 375×667: «Skip all (4)» fits next to the title', (
      tester,
    ) async {
      await _openSheet(tester, setup: _SkipSetup(), locale: locale);
      expect(_skipAll(l10n, 4), findsOneWidget);
      _expectWholeLine(tester, l10n.promptBatchSkipAll(4));
      _expectWholeLine(tester, l10n.inviteAcceptedSetupTitle);
      // Next to the title: the same row.
      final titleRect = tester.getRect(
        find.text(l10n.inviteAcceptedSetupTitle),
      );
      final actionRect = tester.getRect(_skipAll(l10n, 4));
      expect(actionRect.center.dy, closeTo(titleRect.center.dy, 16));
      expect(tester.takeException(), isNull);
    });

    testWidgets('#259 $tag: confirm skips all four in order, then closes', (
      tester,
    ) async {
      final setup = _SkipSetup();
      final cubit = await _openSheet(tester, setup: setup, locale: locale);

      await _confirmSkipAll(tester, l10n, 4);

      expect(setup.skipCalls, _subjects);
      _expectAllSkipped(cubit, _subjects);
      expect(find.byType(PromptBatchSheet), findsNothing);
      expect(
        find.text(l10n.promptBatchSkipAllDone(4), findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '#259 $tag: partial failure says N of M; Retry skips the rest',
      (
        tester,
      ) async {
        final setup = _SkipSetup(failOnce: {'s2', 's4'});
        final cubit = await _openSheet(tester, setup: setup, locale: locale);

        await _confirmSkipAll(tester, l10n, 4);

        expect(setup.skipCalls, _subjects);
        _expectAllSkipped(cubit, ['s1', 's3']);
        expect(cubit.state.promptProjectionFor('s2').isKnownPending, isTrue);
        expect(cubit.state.promptProjectionFor('s4').isKnownPending, isTrue);
        expect(find.byType(PromptBatchSheet), findsOneWidget);
        expect(find.text(l10n.promptBatchSkipAllPartial(2, 4)), findsOneWidget);
        expect(
          find.text(l10n.promptBatchSkipAllDone(4), findRichText: true),
          findsNothing,
        );
        // The action now counts only what is still pending.
        expect(_skipAll(l10n, 2), findsOneWidget);
        expect(tester.takeException(), isNull);

        setup.skipCalls.clear();
        await tester.tap(
          find.widgetWithText(TenturaTextAction, l10n.promptBatchSkipAllRetry),
        );
        await _settle(tester);

        expect(setup.skipCalls, ['s2', 's4']);
        _expectAllSkipped(cubit, _subjects);
        expect(find.byType(PromptBatchSheet), findsNothing);
        expect(
          find.text(l10n.promptBatchSkipAllDone(2), findRichText: true),
          findsOneWidget,
        );
      },
    );

    testWidgets('#259 $tag: total failure is an error, no count claimed', (
      tester,
    ) async {
      final setup = _SkipSetup(failAlways: true);
      final cubit = await _openSheet(tester, setup: setup, locale: locale);

      await _confirmSkipAll(tester, l10n, 4);

      expect(setup.skipCalls, _subjects);
      for (final id in _subjects) {
        expect(cubit.state.promptProjectionFor(id).isKnownPending, isTrue);
      }
      expect(find.byType(PromptBatchSheet), findsOneWidget);
      expect(find.text(l10n.inviteAcceptedSetupSkipError), findsOneWidget);
      expect(find.text(l10n.promptBatchSkipAllPartial(0, 4)), findsNothing);
      expect(
        find.text(l10n.promptBatchSkipAllDone(4), findRichText: true),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('#259 $tag: cancel skips nothing', (tester) async {
      final setup = _SkipSetup();
      final cubit = await _openSheet(tester, setup: setup, locale: locale);

      await tester.tap(_skipAll(l10n, 4));
      await _settle(tester);
      await tester.tap(find.text(l10n.buttonCancel));
      await _settle(tester);

      expect(setup.skipCalls, isEmpty);
      for (final id in _subjects) {
        expect(cubit.state.promptProjectionFor(id).isKnownPending, isTrue);
      }
      expect(find.byType(PromptBatchSheet), findsOneWidget);
      expect(_skipAll(l10n, 4), findsOneWidget);
    });
  }
}
