// #470: a LocalizableActionMessage raised through the UI-effect bus was shown
// with a hard-coded 8 s duration and an action (so `persist` defaulted to
// true): the nudge bar never went away on its own. It must be gone within 6 s.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_create/ui/message/beacon_create_message.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';

/// [dispatchUiEffect] resolves the router up front; ShowMessage never uses it.
class _UnusedRootRouter extends Mock implements RootRouter {}

void main() {
  setUp(() {
    GetIt.I.registerSingleton<RootRouter>(_UnusedRootRouter());
  });

  tearDown(GetIt.I.reset);

  testWidgets('action message from the effect bus auto-dismisses within 6 s', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => dispatchUiEffect(
                  context,
                  ShowMessage(BeaconCreatedMessage(onPressed: () {})),
                  localeName: 'en',
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    // The dispatcher defers action messages to a post-frame callback.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      find.text('Request created successfully!', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('View Request'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });
}
