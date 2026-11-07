import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/home/ui/widget/home_rail_account_footer.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'web: first tap on home account (rail at wide width) opens the menu',
    (tester) async {
      expect(kIsWeb, isTrue, reason: 'Run with flutter drive on Chrome');

      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('1079-account-menu'),
      );
      await logout(tester);
      await loginAs(tester, fixture.authorEmail);
      await goToPath(tester, kPathConversations);
      await pumpSettleBounded(tester);

      final semantics = tester.ensureSemantics();

      final l10n = lookupL10n(const Locale('en'));
      // Default integration browser is 1600×1024 — [WindowClass.expanded], so
      // the account lives in the rail foot, not the compact top bar.
      await tapAndSettle(
        tester,
        find.byKey(HomeRailAccountFooter.footerKey),
      );
      await pumpSettleBounded(tester);

      expect(find.text(l10n.accountMenuViewProfile), findsOneWidget);
      expect(find.text(l10n.labelSettings), findsOneWidget);

      semantics.dispose();
    },
  );
}
