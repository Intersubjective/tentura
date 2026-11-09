// Run with: flutter test --platform chrome <this file>
//
// The startup error screen for "another Tentura tab holds the local
// database": the error is the one the real web opener reports at boot while a
// separate holder keeps the database's cross-tab lock (real navigator.locks),
// not a hand-built exception.
@TestOn('browser')
@Timeout(Duration(seconds: 150))
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/boot_dependencies.dart';
import 'package:tentura/app/boot_failure_app.dart';
import 'package:tentura/data/database/database.dart' show Database;
import 'package:tentura/data/database/open_local_database_web.dart';
import 'package:tentura/data/database/reopening_query_executor.dart';
import 'package:tentura/design_system/components/tentura_empty_state.dart';
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

const _name = 'boot_screen_held_lock_db';

/// Holds the database's cross-tab lock from another request, forever — what
/// a frozen background tab does.
Future<void> _holdLockForever() async {
  final granted = Completer<void>();
  globalContext
      .getProperty<JSObject>('navigator'.toJS)
      .getProperty<JSObject>('locks'.toJS)
      .callMethod(
        'request'.toJS,
        'tentura:local-db:$_name'.toJS,
        ((JSAny? _) {
          granted.complete();
          return Completer<void>().future.toJS;
        }).toJS,
      );
  await granted.future;
}

/// The error boot reports when the auth_accounts step meets the held lock.
/// Same pieces as the production DI database getter, with short lock bounds.
Future<Object> _bootErrorWithHeldLock() async {
  await _holdLockForever();
  final reported = <Object>[];
  final ok = await bootDependencies(
    configure: () => bootStep('auth_accounts', () async {
      final logger = Logger('BootScreenHeldLockTest');
      final executor = DatabaseConnection(
        ReopeningQueryExecutor(
          localDatabaseOpener(
            _name,
            restoreAccounts: AuthLocalRepository.restoreSeedAccounts,
            lockWait: const Duration(milliseconds: 200),
            lockAttempts: 2,
          ),
          retryDelays: const [],
        ),
      );
      final database = Database(const Env(), logger, executor);
      return AuthLocalRepository(
        logger,
        database,
        LocalSecureStorage(),
      ).getAccountsAll();
    }),
    report: (error, _) => reported.add(error),
  ).timeout(const Duration(seconds: 20));
  expect(ok, isFalse);
  final error = reported.single;
  expect(
    error is LocalDatabaseLockHeldException ||
        (error is LocalDatabaseOpenException &&
            error.cause is LocalDatabaseLockHeldException),
    isTrue,
    reason: "boot must report the opener's lock-held error: $error",
  );
  return error;
}

String? _textOf(WidgetTester tester, Key key) {
  final found = find.byKey(key);
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

final _cyrillic = RegExp('[А-Яа-яЁё]');

List<String> _visibleTexts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    if (text.data != null) text.data!,
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Object lockError;

  setUpAll(() async {
    lockError = await _bootErrorWithHeldLock();
  });

  group('startup error screen when another tab holds the local database', () {
    testWidgets('web: tells the user to close other Tentura tabs', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        BootFailureApp(error: lockError, onReload: () {}, isWeb: true),
      );
      await tester.pumpAndSettle();

      final generic = L10nEn();
      expect(
        _textOf(tester, TenturaEmptyState.bodyKey)?.toLowerCase(),
        contains('close other tentura tabs'),
      );
      expect(
        _textOf(tester, TenturaEmptyState.titleKey),
        generic.bootLockHeldTitle,
      );
      expect(
        _textOf(tester, TenturaEmptyState.bodyKey),
        generic.bootLockHeldBody,
      );
      expect(find.text(generic.bootLockHeldReload), findsOneWidget);
      expect(find.text(generic.bootFailureTitle), findsNothing);
      expect(find.text(generic.bootFailureBodyWeb), findsNothing);
    });

    testWidgets('web: the action button retries exactly once per tap', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        BootFailureApp(
          error: lockError,
          onReload: () => retries++,
          isWeb: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(BootFailureApp.reloadKey), findsOneWidget);
      await tester.tap(find.byKey(BootFailureApp.reloadKey));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('native: the lock screen without an action button', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        BootFailureApp(error: lockError, onReload: () {}, isWeb: true),
      );
      await tester.pumpAndSettle();
      final lockTitle = _textOf(tester, TenturaEmptyState.titleKey);
      expect(lockTitle, isNotNull);
      expect(lockTitle, isNot(L10nEn().bootFailureTitle));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        BootFailureApp(
          error: lockError,
          onReload: () => fail('no reload on native'),
          isWeb: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(BootFailureApp.reloadKey), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text(lockTitle!), findsOneWidget);
      expect(lockTitle, L10nEn().bootLockHeldTitle);
      expect(find.byKey(TenturaEmptyState.bodyKey), findsOneWidget);
      expect(find.text(L10nEn().bootFailureTitle), findsNothing);
      expect(find.text(L10nEn().bootFailureBodyNative), findsNothing);
    });

    testWidgets(
      'Russian phone (375x667): title, body and button are Russian and fit',
      (tester) async {
        tester.view
          ..physicalSize = const Size(375, 667)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.localesTestValue = const [Locale('ru')];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);

        await tester.pumpWidget(
          BootFailureApp(error: lockError, onReload: () {}, isWeb: true),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final generic = L10nRu();
        expect(find.text(generic.bootFailureTitle), findsNothing);
        expect(find.text(generic.bootFailureBodyWeb), findsNothing);

        expect(
          _textOf(tester, TenturaEmptyState.titleKey),
          generic.bootLockHeldTitle,
        );
        expect(
          _textOf(tester, TenturaEmptyState.bodyKey),
          generic.bootLockHeldBody,
        );
        final texts = _visibleTexts(tester);
        // Title, body and the action label.
        expect(texts.length, greaterThanOrEqualTo(3), reason: '$texts');
        for (final text in texts) {
          expect(text, contains(_cyrillic), reason: 'not Russian: "$text"');
        }
        final button = find.descendant(
          of: find.byKey(BootFailureApp.reloadKey),
          matching: find.byType(Text),
        );
        expect(tester.widget<Text>(button).data, generic.bootLockHeldReload);
        expect(tester.widget<Text>(button).data, contains(_cyrillic));

        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.byType(RichText),
        )) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: 'cut off: "${paragraph.text.toPlainText()}"',
          );
          final box = paragraph.localToGlobal(Offset.zero) & paragraph.size;
          expect(
            Offset.zero & const Size(375, 667),
            predicate<Rect>((screen) => screen.intersect(box) == box),
            reason: 'off screen: "${paragraph.text.toPlainText()}"',
          );
        }
      },
    );
  });
}
