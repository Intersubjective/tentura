// #373: in the request's Facts sheet, ⋯ → "Jump to message" was greyed out
// for a fact pinned with "also post to General": showBeaconFactActions passed
// no jump handler. It now opens General at the fact's message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_fact_actions.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_navigation_scope.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart' show pumpUntil;

const _beaconId = 'b-fact-jump';

/// Lets a sheet route finish its open or close animation.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

final _beacon = Beacon(
  id: _beaconId,
  title: 'Facts beacon',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: const Profile(id: 'Uauthor', displayName: 'Author'),
);

BeaconFactCard _fact({String? sourceMessageId}) => BeaconFactCard(
  id: 'fact-jump-1',
  beaconId: _beaconId,
  factText: 'Gate code is 4821',
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Uauthor',
  pinnedByTitle: 'Author',
  createdAt: DateTime.utc(2026, 7),
  status: BeaconFactCardStatusBits.active,
  sourceMessageId: sourceMessageId,
);

void main() {
  Future<BeaconViewCubit> loadedCubit(
    WidgetTester tester,
    BeaconFactCard fact,
  ) async {
    final cubit = (await tester.runAsync(() async {
      final c = BeaconViewCubit(
        id: _beaconId,
        myProfile: const Profile(id: 'Uauthor', displayName: 'Author'),
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: TrackingBeaconRepository()
            ..fetchByIdHandler = (_) async => _beacon,
          factCardsRepo: FakeBeaconViewFactCardRepository(cards: [fact]),
        ),
        effects: FakeUiEffectPort(),
      );
      await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
      return c;
    }))!;
    addTearDown(cubit.close);
    return cubit;
  }

  /// The page, under the request's navigation scope; "facts" opens a stand-in
  /// for the Facts sheet, and its button opens the fact's actions.
  Future<List<String?>> pumpPage(
    WidgetTester tester, {
    required BeaconViewCubit cubit,
    required BeaconFactCard fact,
    bool withScope = true,
  }) async {
    final opened = <String?>[];
    final host = ThreadHostCubit(
      beaconId: _beaconId,
      roomCubitFactory:
          ({
            required beaconId,
            threadItemId,
            initialUnreadAnchorAt,
            capabilities = const RoomCapabilities.request(),
          }) => throw UnimplementedError(),
    );
    // Closing awaits the host's switch chain, which only resumes on a pump in
    // the fake-async zone (same as room_capabilities_widget_test).
    addTearDown(() async {
      final closing = host.close();
      await tester.pump();
      await closing;
    });
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget page = Builder(
      builder: (pageContext) => TextButton(
        onPressed: () => showTenturaAdaptiveSheet<void>(
          context: pageContext,
          builder: (_) => TextButton(
            onPressed: () =>
                showBeaconFactActions(pageContext, cubit: cubit, fact: fact),
            child: const Text('manage'),
          ),
        ),
        child: const Text('facts'),
      ),
    );
    if (withScope) {
      page = BeaconRoomNavigationScope(
        isRoomPresented: false,
        roomLease: BeaconRoomLease(host: host),
        openGeneralAnchor: ({messageId, coordinationItemId}) async =>
            opened.add(messageId),
        child: page,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(child: Scaffold(body: page)),
      ),
    );
    await tester.tap(find.text('facts'));
    await _settle(tester);
    await tester.tap(find.text('manage'));
    await _settle(tester);
    return opened;
  }

  ListTile jumpTile(WidgetTester tester, L10n l10n) => tester.widget<ListTile>(
    find.widgetWithText(ListTile, l10n.beaconRoomFactCardActionJumpToSource),
  );

  testWidgets('"Jump to message" opens General at the source message', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final fact = _fact(sourceMessageId: 'm-source');
    final cubit = await loadedCubit(tester, fact);
    final opened = await pumpPage(tester, cubit: cubit, fact: fact);

    expect(jumpTile(tester, l10n).enabled, isTrue);
    await tester.tap(find.text(l10n.beaconRoomFactCardActionJumpToSource));
    await _settle(tester);

    expect(opened, ['m-source']);
    // Both sheets are gone, so the chat is in view.
    expect(find.text('manage'), findsNothing);
    expect(find.text(l10n.beaconRoomFactCardActionJumpToSource), findsNothing);
  });

  testWidgets('without a source message the item stays disabled', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final fact = _fact();
    final cubit = await loadedCubit(tester, fact);
    await pumpPage(tester, cubit: cubit, fact: fact);

    expect(jumpTile(tester, l10n).enabled, isFalse);
  });

  testWidgets('outside a request page the item stays disabled', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final fact = _fact(sourceMessageId: 'm-source');
    final cubit = await loadedCubit(tester, fact);
    await pumpPage(tester, cubit: cubit, fact: fact, withScope: false);

    expect(jumpTile(tester, l10n).enabled, isFalse);
  });
}
