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

  // #878: Sentry TENTURA-CLIENT-5J was a bare "TimeoutException after
  // 0:01:00: Future not completed" — nothing said which startup step hung.
  group('boot step attribution (#878)', () {
    test('a boot timeout names the step that hung', () async {
      final reported = <Object>[];

      final ok = await bootDependencies(
        configure: () => bootStep(
          'get_it_init',
          () async {
            await bootStep('blurhash_shader', () async {});
            return bootStep('firebase_init', () => Completer<Object?>().future);
          },
        ),
        timeout: const Duration(milliseconds: 10),
        report: (e, _) => reported.add(e),
      );

      expect(ok, isFalse);
      final error = reported.single;
      expect(error, isA<TimeoutException>());
      expect(error, isA<BootTimeoutException>());
      error as BootTimeoutException;
      expect(error.pendingSteps, ['get_it_init', 'firebase_init']);
      expect(error.toString(), contains('firebase_init'));
      expect(error.toString(), isNot(contains('blurhash_shader')));
      expect(bootFailureTags(error), {
        'boot_failure': 'true',
        'boot_step': 'firebase_init',
      });
    });

    test('a step outside startup runs as is', () async {
      expect(await bootStep('firebase_init', () async => 42), 42);
    });

    test('a non-timeout failure carries no step tag', () {
      expect(bootFailureTags(StateError('x')), {'boot_failure': 'true'});
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
