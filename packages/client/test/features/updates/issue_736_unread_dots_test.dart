import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/phone_surface.dart';
import 'support/mark_unread_server_fake.dart';
import 'support/noop_invite_setup_port.dart';

/// A dot means the row contributes to Unread, on either filter.
void main() {
  testWidgets('All and Unread show the same counted rows with dots', (
    tester,
  ) async {
    final server = MarkUnreadServerFake([
      markUnreadTestReceipt(
        'r1',
        minute: 4,
        seen: false,
      ).copyWith(presentationKey: 'trust_given_changed_up'),
      markUnreadTestReceipt('r2', minute: 3, seen: false),
      markUnreadTestReceipt(
        'r3',
        minute: 2,
        seen: false,
      ).copyWith(presentationKey: 'invite_accepted'),
      markUnreadTestReceipt('r4', minute: 1, cleared: true),
    ]);
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      server,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-unread-dots-736'),
    );
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activityStream,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('updates-unread-dots-736-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    addTearDown(() async {
      await cubit.close();
      await attention.dispose();
      await sync.port.dispose();
      await accounts.close();
    });
    accounts.emit('viewer');
    await _drain();

    await tester.pumpWidget(
      _wrap(BlocProvider.value(value: cubit, child: const UpdatesFeedPane())),
    );
    await tester.pump();
    await tester.pump();
    await _drain();
    await tester.pumpAndSettle();

    await cubit.markRead('r1');
    await cubit.markRead('r3');
    await tester.pumpAndSettle();
    expect(
      cubit.state.items
          .where((r) => r.id == 'r1' || r.id == 'r3')
          .every((r) => r.isSeen && !r.isCleared),
      isTrue,
    );

    // Cleared rows remain visible on All but do not contribute a dot.
    expect(cubit.state.view, AttentionView.all);
    expect(
      find.bySemanticsIdentifier(TestIds.updatesReceipt('r4')),
      findsOneWidget,
    );
    final allDots = find.byKey(UpdatesFeedTile.unreadDotKey).evaluate().length;

    await tester.tap(find.byKey(const ValueKey<String>('updates-unread')));
    await _drain();
    await tester.pumpAndSettle();
    await _drain();
    await tester.pumpAndSettle();

    expect(cubit.state.view, AttentionView.unread);
    expect(cubit.state.summary.unreadTotal, 3);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('updates-unread')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    for (final id in ['r1', 'r2', 'r3']) {
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(TestIds.updatesReceipt(id)),
          matching: find.byKey(UpdatesFeedTile.unreadDotKey),
        ),
        findsOneWidget,
        reason: '$id is on Unread, so it carries the dot',
      );
    }
    expect(
      find.byKey(UpdatesFeedTile.unreadDotKey),
      findsNWidgets(cubit.state.summary.unreadTotal),
    );

    expect(
      allDots,
      cubit.state.summary.unreadTotal,
      reason: 'All dots must equal the count, including seen optional rows',
    );
  });

  for (final phone in [true, false]) {
    for (final (label, key, obligation) in [
      ('forward receipt', 'relay_received', false),
      ('author help offer', 'help_offer_submitted', true),
      ('assignee plan obligation', 'plan_step_due', true),
      ('trust change', 'trust_given_changed_up', false),
      ('accepted invite', 'invite_accepted', false),
    ]) {
      testWidgets(
        'seen $label keeps its counted dot and normal title on both filters as a RU tile at ${phone ? 'phone' : 'desktop'}',
        (tester) async {
          if (phone) {
            await usePhoneSurface(tester);
          } else {
            await tester.binding.setSurfaceSize(const Size(1280, 900));
            addTearDown(() => tester.binding.setSurfaceSize(null));
          }
          final receipt = markUnreadTestReceipt('seen', minute: 1).copyWith(
            presentationKey: key,
            requiresAction: obligation,
            presentationPayloadJson: key == 'plan_step_due'
                ? '{"eventType":"planStepDue","excerpt":"Подготовить лестницу"}'
                : '{}',
            title: 'Алиса',
            body: key == 'plan_step_due'
                ? 'Подготовить лестницу'
                : 'Новое событие',
          );
          final visible = <String, Object>{};
          for (final unread in [false, true]) {
            await tester.pumpWidget(
              _wrap(
                UpdatesFeedTile(
                  receipt: receipt,
                  onTap: () {},
                  onMarkSeen: () {},
                  onMarkUnseen: () {},
                  unreadView: unread,
                ),
              ),
            );
            await tester.pumpAndSettle();
            visible[unread ? 'Unread' : 'All'] = {
              'dots': find
                  .byKey(UpdatesFeedTile.unreadDotKey)
                  .evaluate()
                  .length,
              'bold titles': _boldTitle.evaluate().length,
            };
            final l10n = L10n.of(tester.element(find.byType(UpdatesFeedTile)))!;
            if (key == 'trust_given_changed_up') {
              expect(
                find.text(l10n.attentionEventTrustGivenUp),
                findsOneWidget,
              );
            } else if (key == 'plan_step_due') {
              expect(find.text('Подготовить лестницу'), findsOneWidget);
              final tile = tester.widget<UpdatesFeedTile>(
                find.byType(UpdatesFeedTile),
              );
              expect(tile.receipt.isLiveObligation, isTrue);
              expect(tile.receipt.isSeen, isTrue);
            } else {
              expect(
                find.textContaining('Алиса', findRichText: true),
                findsWidgets,
              );
            }
            expect(find.byType(UpdatesFeedTile), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          expect(visible, {
            'All': {'dots': 1, 'bold titles': 0},
            'Unread': {'dots': 1, 'bold titles': 0},
          });
        },
      );
    }
  }

  testWidgets('an unread row has the bold title', (tester) async {
    await tester.pumpWidget(
      _wrap(
        UpdatesFeedTile(
          receipt: markUnreadTestReceipt('r1', minute: 1, seen: false),
          onTap: () {},
          onMarkSeen: () {},
          onMarkUnseen: () {},
          unreadView: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_boldTitle, findsOneWidget);
  });

  testWidgets(
    'on Unread a read, uncleared row keeps its read look and menu',
    (tester) async {
      final receipt = markUnreadTestReceipt('r1', minute: 1);
      await tester.pumpWidget(
        _wrap(
          UpdatesFeedTile(
            receipt: receipt,
            onTap: () {},
            onMarkSeen: () {},
            onMarkUnseen: () {},
            unreadView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10n.of(
        tester.element(find.byType(UpdatesFeedTile)),
      )!;

      expect(find.byKey(UpdatesFeedTile.unreadDotKey), findsOneWidget);
      // The title stays at the read weight (an unread title is w600).
      expect(_boldTitle, findsNothing);

      await tester.tap(find.byTooltip(l10n.updatesRowMenuTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.updatesMarkUnseen), findsOneWidget);
      expect(find.text(l10n.attentionEventDismiss), findsOneWidget);
      expect(find.text(l10n.updatesMarkSeen), findsNothing);
    },
  );
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

/// The row title written with [Text.rich] at the unread weight.
final _boldTitle = find.byWidgetPredicate(
  (w) => w is Text && w.textSpan?.style?.fontWeight == FontWeight.w600,
);

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Widget _wrap(Widget child) => MediaQuery(
  data: MediaQueryData.fromView(
    WidgetsBinding.instance.platformDispatcher.views.first,
  ),
  child: TenturaResponsiveScope(
    child: MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('ru'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  ),
);
