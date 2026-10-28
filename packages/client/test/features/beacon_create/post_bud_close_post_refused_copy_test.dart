// A bud that asks to close a Post the budder did not start is refused by the
// server with a typed code (1351). The user must read a plain, localized
// sentence about it - not a raw exception name and not the same text in both
// languages.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';

class _UnusedRootRouter extends Mock implements RootRouter {}

/// What the server's PostCloseForbiddenException travels as.
const _postCloseForbiddenCode = 1351;

/// The copy is not fixed word for word; it must say that the author of the
/// post is the one who can close it, in each language.
bool _saysOnlyAuthorCanClose(String text, {required bool ru}) => ru
    ? RegExp('автор', caseSensitive: false).hasMatch(text) &&
          RegExp('пост', caseSensitive: false).hasMatch(text) &&
          RegExp('закр', caseSensitive: false).hasMatch(text)
    : RegExp('author', caseSensitive: false).hasMatch(text) &&
          RegExp('post', caseSensitive: false).hasMatch(text) &&
          RegExp('clos', caseSensitive: false).hasMatch(text);

Future<Object> _budRefusedByServer(WidgetTester tester) async {
  final failure = await tester.runAsync<Object?>(() async {
    Object? caught;
    await withRemoteWire(
      const {},
      <WireSent>[],
      (remote) async {
        try {
          await PostBudRepository(remote).budFromPost(
            postId: 'Bpost00000001',
            sourceMessageId: 'Mmsg00000001',
            clientCommandId: 'cmd-1',
            title: 'Fix the fence',
            closePost: true,
          );
        } catch (error) {
          caught = error;
        }
      },
      errors: {'PostBudFromPost': wireCodeError(_postCloseForbiddenCode)},
    );
    return caught;
  });
  expect(failure, isNotNull, reason: 'the refused bud must surface an error');
  return failure!;
}

/// The words of the snackbar the user sees for [error] in [locale].
Future<String> _shownMessage(
  WidgetTester tester,
  Object error,
  String locale,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                dispatchUiEffect(context, ShowError(error), localeName: locale),
            child: const Text('Show error'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show error'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  final snack = find.byType(SnackBar);
  expect(snack, findsOneWidget);
  return tester
      .widgetList<RichText>(
        find.descendant(of: snack, matching: find.byType(RichText)),
      )
      .map((t) => t.text.toPlainText())
      .join(' ')
      .trim();
}

void main() {
  group('bud refused because only the Post author may close the Post', () {
    setUp(() {
      GetIt.I
        ..registerSingleton<RootRouter>(_UnusedRootRouter())
        ..registerSingleton<Logger>(Logger('PostCloseRefusedCopyTest'));
    });
    tearDown(GetIt.I.reset);

    testWidgets('the repository surfaces a typed localizable refusal', (
      tester,
    ) async {
      final error = await _budRefusedByServer(tester);

      // Like code 1332 (PostNotOpenException): the shared code mapper must
      // turn 1351 into its own dedicated exception, not another hierarchy
      // type. Matched by name so the test compiles before the class exists.
      expect(
        error.runtimeType.toString(),
        'PostCloseForbiddenException',
        reason: 'wire code 1351 must map to PostCloseForbiddenException',
      );
      expect(error, isA<BeaconHierarchyException>());
      expect(error, isA<Localizable>());
    });

    for (final locale in ['en', 'ru']) {
      testWidgets('the snackbar says only the author can close the post '
          'in $locale', (tester) async {
        final error = await _budRefusedByServer(tester);
        final shown = await _shownMessage(tester, error, locale);

        expect(
          _saysOnlyAuthorCanClose(shown, ru: locale == 'ru'),
          isTrue,
          reason: 'shown: $shown',
        );
        expect(shown, isNot(contains('Exception')));
        if (locale == 'en') {
          expect(shown, isNot(matches(RegExp('[А-Яа-я]'))));
        }
      });
    }

    // Run from packages/client: the ARB files are read by relative path.
    test('both ARB files carry the refusal copy under one shared key', () {
      final en =
          jsonDecode(File('l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      final ru =
          jsonDecode(File('l10n/app_ru.arb').readAsStringSync())
              as Map<String, dynamic>;

      final enKeys = en.entries
          .where(
            (e) =>
                !e.key.startsWith('@') &&
                e.value is String &&
                _saysOnlyAuthorCanClose(e.value as String, ru: false),
          )
          .map((e) => e.key);
      expect(enKeys, isNotEmpty, reason: 'app_en.arb lacks the copy');
      expect(
        enKeys.any(
          (k) =>
              ru[k] is String &&
              _saysOnlyAuthorCanClose(ru[k] as String, ru: true),
        ),
        isTrue,
        reason: 'app_ru.arb must carry the Russian copy under the same key',
      );
    });
  });
}
