import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/boot_dependencies.dart';
import 'package:tentura/app/boot_failure_app.dart';
import 'package:tentura/data/database/reopening_query_executor.dart';

void main() {
  group('bootDependencies (#674)', () {
    test('a failed setup is reported instead of escaping', () async {
      final reported = <Object>[];
      final error = LocalDatabaseOpenException(
        attempts: 6,
        cause: Exception('SqliteException(1): while opening the database'),
        causeStackTrace: StackTrace.current,
      );
      var afterRan = false;

      final ok = await bootDependencies(
        configure: () async => throw error,
        afterConfigure: () => afterRan = true,
        report: (e, _) => reported.add(e),
      );

      expect(ok, isFalse);
      expect(reported, [error]);
      expect(afterRan, isFalse);
    });

    test('a setup that never finishes times out', () async {
      final reported = <Object>[];

      final ok = await bootDependencies(
        configure: () => Completer<Object?>().future,
        timeout: const Duration(milliseconds: 10),
        report: (e, _) => reported.add(e),
      );

      expect(ok, isFalse);
      expect(reported.single, isA<TimeoutException>());
    });

    test('a failure after setup is reported too', () async {
      final reported = <Object>[];

      final ok = await bootDependencies(
        configure: () async => null,
        afterConfigure: () => throw StateError('FcmCubit'),
        report: (e, _) => reported.add(e),
      );

      expect(ok, isFalse);
      expect(reported.single, isA<StateError>());
    });

    test('a working setup boots', () async {
      var afterRan = false;

      final ok = await bootDependencies(
        configure: () async => null,
        afterConfigure: () => afterRan = true,
        report: (e, _) => fail('unexpected $e'),
      );

      expect(ok, isTrue);
      expect(afterRan, isTrue);
    });
  });

  group('BootFailureApp', () {
    testWidgets('web: explains and offers Reload', (tester) async {
      var reloads = 0;
      await tester.pumpWidget(
        BootFailureApp(onReload: () => reloads++, isWeb: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tentura couldn’t start'), findsOneWidget);
      expect(find.textContaining('Reloading the page'), findsOneWidget);

      await tester.tap(find.byKey(BootFailureApp.reloadKey));
      expect(reloads, 1);
    });

    testWidgets('native: no Reload button', (tester) async {
      await tester.pumpWidget(
        BootFailureApp(onReload: () => fail('no reload on native')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tentura couldn’t start'), findsOneWidget);
      expect(find.textContaining('Close the app'), findsOneWidget);
      expect(find.byKey(BootFailureApp.reloadKey), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
