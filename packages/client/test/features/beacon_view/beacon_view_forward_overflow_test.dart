import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

BeaconViewState _state({
  BeaconStatus status = BeaconStatus.open,
  String viewerId = 'uViewer',
  String authorId = 'uAuthor',
}) {
  final t = DateTime.utc(2026, 6, 20);
  return BeaconViewState(
    beacon: Beacon(
      id: 'b1',
      title: 'T',
      author: Profile(id: authorId, displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
      status: status,
    ),
    myProfile: Profile(id: viewerId, displayName: 'Viewer'),
    beaconContextLoaded: true,
  );
}

void main() {
  group('beaconViewAllowsForwardAction', () {
    test('true for open-family when content loaded', () {
      expect(
        beaconViewAllowsForwardAction(
          state: _state(),
          showBeaconContent: true,
          showInitialLoading: false,
        ),
        isTrue,
      );
      expect(
        beaconViewAllowsForwardAction(
          state: _state(status: BeaconStatus.enoughHelp),
          showBeaconContent: true,
          showInitialLoading: false,
        ),
        isTrue,
      );
    });

    test('false when loading, no content, or closed family', () {
      expect(
        beaconViewAllowsForwardAction(
          state: _state(),
          showBeaconContent: false,
          showInitialLoading: false,
        ),
        isFalse,
      );
      expect(
        beaconViewAllowsForwardAction(
          state: _state(),
          showBeaconContent: true,
          showInitialLoading: true,
        ),
        isFalse,
      );
      expect(
        beaconViewAllowsForwardAction(
          state: _state(status: BeaconStatus.closed),
          showBeaconContent: true,
          showInitialLoading: false,
        ),
        isFalse,
      );
      expect(
        beaconViewAllowsForwardAction(
          state: _state(status: BeaconStatus.reviewOpen),
          showBeaconContent: true,
          showInitialLoading: false,
        ),
        isFalse,
      );
    });
  });

  testWidgets('overflow menu exposes Forward with test id', (tester) async {
    final t = DateTime.utc(2026, 6, 20);
  await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            appBar: AppBar(
              actions: [
                BeaconOverflowMenu(
                  beacon: Beacon(
                    id: 'b1',
                    title: 'T',
                    author: const Profile(id: 'a', displayName: 'A'),
                    createdAt: t,
                    updatedAt: t,
                    status: BeaconStatus.open,
                  ),
                  onForward: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Forward'), findsOneWidget);
    expect(find.byKey(TestIds.key(TestIds.beaconForward)), findsOneWidget);
  });

  group('beaconHudYouLine author idle', () {
    testWidgets('prefers Forward copy over status-overflow when allowsForward', (
      tester,
    ) async {
      late L10n l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              l10n = L10n.of(context)!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line = beaconHudYouLine(
        l10n,
        _state(viewerId: 'uAuthor', authorId: 'uAuthor'),
      );
      expect(line, l10n.beaconHudYouForward);
      expect(line, isNot(l10n.beaconHudYouChangeStatusInOverflow));
    });
  });
}
