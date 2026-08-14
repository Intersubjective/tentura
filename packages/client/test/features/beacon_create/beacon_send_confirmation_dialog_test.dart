import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required ForwardDeliveryOutcome outcome,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                BeaconSendConfirmationDialog.show(context, outcome: outcome);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows delivered N of M using outcome denominator', (tester) async {
    await pumpDialog(
      tester,
      outcome: const ForwardDeliveryOutcome(
        requestedRecipientIds: ['U-a', 'U-b', 'U-c'],
        deliveredRecipientIds: ['U-a'],
        availabilitySkippedRecipientIds: ['U-b', 'U-c'],
      ),
    );

    final expected = const ForwardDeliveredOfMessage(
      deliveredCount: 1,
      requestedCount: 3,
    ).toEn;

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('failed outcome shows publish-only failure copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) {
            final l10n = L10n.of(context)!;
            return ElevatedButton(
              onPressed: () {
                BeaconSendConfirmationDialog.show(
                  context,
                  outcome: const ForwardDeliveryOutcome(
                    requestedRecipientIds: ['U-a'],
                    deliveredRecipientIds: [],
                    availabilitySkippedRecipientIds: [],
                    failed: true,
                  ),
                );
              },
              child: Text(l10n.beaconSendConfirmationFailed),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Delivered to 1 of'), findsNothing);
  });
}
