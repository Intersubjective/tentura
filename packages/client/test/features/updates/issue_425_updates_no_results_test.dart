import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../block/support/controllable_block_case.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/noop_invite_setup_port.dart';

// #425 — a search in Updates that matches nothing must say so, instead of
// showing the empty-inbox copy ("All caught up…").

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

/// Always returns an empty page, whatever the search.
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

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Widget _wrap(Widget child, {Locale? locale}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(800, 800)),
    child: TenturaResponsiveScope(
      child: MaterialApp(
        theme: TenturaTheme.light(),
        locale: locale,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> _pumpPane(
  WidgetTester tester, {
  String? search,
  Locale? locale,
}) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    _EmptyRepository(),
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('updates-no-results'),
  );
  accounts.emit('viewer');
  await _drain();

  final cubit = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('updates-no-results'),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  addTearDown(() {
    unawaited(cubit.close());
    unawaited(attention.dispose());
    unawaited(sync.port.dispose());
    unawaited(accounts.close());
  });
  await _drain();
  if (search != null) {
    cubit.setSearch(search);
    await _drain();
  }

  await tester.pumpWidget(
    _wrap(
      BlocProvider.value(
        value: cubit,
        child: const UpdatesFeedPane(),
      ),
      locale: locale,
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('search with no matches shows a no-results state', (
    tester,
  ) async {
    await _pumpPane(tester, search: 'zzqx');

    expect(find.text('No results for “zzqx”'), findsOneWidget);
    expect(
      find.text('All caught up. New updates will appear here.'),
      findsNothing,
    );
  });

  testWidgets('no-results state is localized in Russian', (tester) async {
    await _pumpPane(tester, search: 'zzqx', locale: const Locale('ru'));

    expect(find.text('Ничего не найдено по запросу «zzqx»'), findsOneWidget);
    expect(
      find.text('Всё прочитано. Новые обновления появятся здесь.'),
      findsNothing,
    );
  });

  testWidgets('empty feed without a search keeps the caught-up copy', (
    tester,
  ) async {
    await _pumpPane(tester);

    expect(
      find.text('All caught up. New updates will appear here.'),
      findsOneWidget,
    );
    expect(find.textContaining('No results for'), findsNothing);
  });
}
