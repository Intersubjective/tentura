import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'web: first tap on home avatar opens the account menu (semantics on)',
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
      addTearDown(semantics.dispose);

      final l10n = lookupL10n(const Locale('en'));
      await tapAndSettle(
        tester,
        find.byKey(HomeAccountAvatarButton.buttonKey),
      );
      await pumpSettleBounded(tester);

      expect(find.text(l10n.accountMenuViewProfile), findsOneWidget);
      expect(find.text(l10n.labelSettings), findsOneWidget);
    },
  );
}
