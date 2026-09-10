import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_triage_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

class _HarnessRouter extends Mock implements StackRouter {
  int pushCount = 0;
  PageRouteInfo? lastPush;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    lastPush = route;
    return null;
  }
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initial);

  @override
  void setSort(InboxSort sort) => emit(state.copyWith(sort: sort));

  @override
  void clearPendingMovedNudge() {
    emit(state.copyWith(pendingMovedNudge: null));
  }

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  Future<void> setWatching(String beaconId) async {}

  @override
  Future<void> stopWatching(String beaconId) async {}

  @override
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}
}

InboxItem _item(String id, String title, {String authorId = 'auth'}) {
  final at = DateTime.utc(2026, 6, 20);
  final beacon = Beacon(
    id: id,
    title: title,
    author: Profile(id: authorId, displayName: 'Author $authorId'),
    createdAt: at,
    updatedAt: at,
  );
  return InboxItem(
    beaconId: beacon.id,
    latestForwardAt: at,
    beacon: beacon,
  );
}

Future<_HarnessRouter> _pumpRow(
  WidgetTester tester, {
  required List<InboxItem> items,
  double textScale = 1,
}) async {
  final router = _HarnessRouter();
  final cubit = _TestInboxCubit(
    InboxState(
      items: items,
      status: const StateIsSuccess(),
      projectionLoaded: true,
    ),
  );
  unawaited(cubit.close());

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: BlocProvider<InboxCubit>.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 640),
              textScaler: TextScaler.linear(textScale),
            ),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(8),
                  child: const InboxTriageRow(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  testWidgets('row absent when no pending triage', (tester) async {
    await _pumpRow(tester, items: []);
    expect(find.byKey(TestIds.key(TestIds.activityTriageRow)), findsNothing);
  });

  testWidgets('single pending shows request title on one line', (tester) async {
    await _pumpRow(tester, items: [_item('b1', 'Solo request')]);
    expect(find.text('Solo request'), findsOneWidget);
    expect(find.textContaining('requests need your response'), findsNothing);
  });

  testWidgets('two or more pending shows plural summary', (tester) async {
    await _pumpRow(
      tester,
      items: [
        _item('b1', 'One', authorId: 'a1'),
        _item('b2', 'Two', authorId: 'a2'),
      ],
    );
    expect(find.text('2 requests need your response'), findsOneWidget);
  });

  testWidgets('tap opens triage route at every count', (tester) async {
    for (final items in [
      [_item('b1', 'Only')],
      [_item('b1', 'One', authorId: 'a1'), _item('b2', 'Two', authorId: 'a2')],
    ]) {
      final router = await _pumpRow(tester, items: items);
      expect(router.pushCount, 0);
      await tester.tap(find.byKey(TestIds.key(TestIds.activityTriageRow)));
      await tester.pump();
      expect(router.pushCount, 1);
      expect(router.lastPush, isA<InboxTriageRoute>());
      router.pushCount = 0;
      router.lastPush = null;
    }
  });

  testWidgets('text scale 1.3 keeps row single-line and bounded', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      items: [_item('b1', 'A very long request title that should ellipsize')],
      textScale: 1.3,
    );
    final rowBox = tester.getRect(
      find.byKey(TestIds.key(TestIds.activityTriageRow)),
    );
    final context = tester.element(
      find.byKey(TestIds.key(TestIds.activityTriageRow)),
    );
    final tt = context.tt;
    expect(rowBox.height, tt.buttonHeight + tt.tightGap);
    final text = tester.widget<Text>(find.textContaining('very long'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
