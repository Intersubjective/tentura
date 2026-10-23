// #613 (from #409): the showSnackBar fallback dereferenced
// `snackbarKey.currentState!`, so a bar raised from a context with no
// ScaffoldMessenger above it while the app-level messenger was not mounted
// (start-up, teardown, a detached overlay) threw instead of being dropped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  testWidgets('no messenger anywhere: no crash, nothing shown, warns', (
    tester,
  ) async {
    final logger = Logger('test-613');
    GetIt.I.registerSingleton<Logger>(logger);
    addTearDown(GetIt.I.reset);
    final records = <LogRecord>[];
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    addTearDown(() => Logger.root.level = previousLevel);
    final sub = logger.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    late BuildContext bare;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            bare = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(snackbarKey.currentState, isNull);

    Object? controller = 'unset';
    expect(
      () => controller = showSnackBar(bare, text: 'Saved'),
      returnsNormally,
    );
    expect(controller, isNull);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      records.where(
        (r) => r.level == Level.WARNING && r.message.contains('Saved'),
      ),
      isNotEmpty,
    );
  });

  testWidgets('no messenger and no Logger registered: still no crash', (
    tester,
  ) async {
    late BuildContext bare;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            bare = context;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(() => showSnackBar(bare, text: 'Saved'), returnsNormally);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to the app-level messenger (guard)', (
    tester,
  ) async {
    // Context sits above the MaterialApp, so maybeOf finds nothing; the bar
    // must still reach the messenger mounted under snackbarKey.
    late BuildContext outer;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          outer = context;
          return MaterialApp(
            scaffoldMessengerKey: snackbarKey,
            home: const Scaffold(body: SizedBox()),
          );
        },
      ),
    );
    expect(ScaffoldMessenger.maybeOf(outer), isNull);

    final controller = showSnackBar(outer, text: 'Fallback bar');
    expect(controller, isNotNull);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // The bar renders its message as RichText, which find.text skips unless
    // asked to look at it.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Fallback bar', findRichText: true), findsOneWidget);
  });
}
