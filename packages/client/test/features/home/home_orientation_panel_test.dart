import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/components/tentura_command_button.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/home/ui/widget/home_orientation_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

Future<void> _pumpPanel(
  WidgetTester tester, {
  required ThemeData theme,
  int inboxNeedsMeCount = 0,
  VoidCallback? onCreateBeacon,
  VoidCallback? onOpenInbox,
  VoidCallback? onOpenConstellation,
  void Function(HomeTab)? onOpenTab,
  VoidCallback? onDismiss,
  Size surfaceSize = const Size(800, 1200),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: MediaQueryData(size: surfaceSize),
        child: Scaffold(
          // HomeOrientationPanel is mainAxisSize.min and not self-scrolling
          // by design (plan §5.1 — the real host is a SliverToBoxAdapter
          // inside a CustomScrollView). The test surface's actual render
          // view stays at its default size regardless of the MediaQuery
          // override above, so without a scroll wrapper the panel's natural
          // content height overflows the real window in every test here.
          body: SingleChildScrollView(
            child: HomeOrientationPanel(
              inboxNeedsMeCount: inboxNeedsMeCount,
              onCreateBeacon: onCreateBeacon ?? () {},
              onOpenInbox: onOpenInbox ?? () {},
              onOpenConstellation: onOpenConstellation ?? () {},
              onOpenTab: onOpenTab ?? (_) {},
              onDismiss: onDismiss ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('HomeOrientationPanel', () {
    testWidgets('inbox primary CTA ladder when needs-me count is positive', (
      tester,
    ) async {
      var inboxTapped = false;
      var createTapped = false;

      await _pumpPanel(
        tester,
        theme: TenturaTheme.light(),
        inboxNeedsMeCount: 2,
        onOpenInbox: () => inboxTapped = true,
        onCreateBeacon: () => createTapped = true,
      );

      expect(find.text('View Inbox (2)'), findsOneWidget);
      expect(find.text('Create request'), findsOneWidget);
      expect(find.byType(TenturaCommandButton), findsOneWidget);

      await tester.ensureVisible(find.text('View Inbox (2)'));
      await tester.tap(find.text('View Inbox (2)'));
      await tester.pumpAndSettle();
      expect(inboxTapped, isTrue);
      expect(createTapped, isFalse);

      await tester.ensureVisible(find.text('Create request'));
      await tester.tap(find.text('Create request'));
      await tester.pumpAndSettle();
      expect(createTapped, isTrue);
    });

    testWidgets('create primary CTA ladder when needs-me count is zero', (
      tester,
    ) async {
      var createTapped = false;
      var constellationTapped = false;

      await _pumpPanel(
        tester,
        theme: TenturaTheme.light(),
        inboxNeedsMeCount: 0,
        onCreateBeacon: () => createTapped = true,
        onOpenConstellation: () => constellationTapped = true,
      );

      expect(find.text('Create request'), findsOneWidget);
      expect(find.text('Find ways to help'), findsOneWidget);
      expect(find.byType(TenturaCommandButton), findsOneWidget);

      await tester.ensureVisible(find.text('Create request'));
      await tester.tap(find.text('Create request'));
      await tester.pumpAndSettle();
      expect(createTapped, isTrue);
      expect(constellationTapped, isFalse);

      await tester.ensureVisible(find.text('Find ways to help'));
      await tester.tap(find.text('Find ways to help'));
      await tester.pumpAndSettle();
      expect(constellationTapped, isTrue);
    });

    testWidgets('Got it fires onDismiss', (tester) async {
      var dismissed = false;

      await _pumpPanel(
        tester,
        theme: TenturaTheme.light(),
        onDismiss: () => dismissed = true,
      );

      await tester.ensureVisible(
        find.byKey(TestIds.key(TestIds.orientationDismiss)),
      );
      await tester.tap(find.byKey(TestIds.key(TestIds.orientationDismiss)));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('renders without exception in light and dark themes', (
      tester,
    ) async {
      for (final theme in [TenturaTheme.light(), TenturaTheme.dark()]) {
        await _pumpPanel(
          tester,
          theme: theme,
          inboxNeedsMeCount: 1,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
