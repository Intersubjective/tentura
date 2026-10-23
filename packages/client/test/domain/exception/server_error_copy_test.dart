// #683: an error bar showed the server's raw key ("beaconNotOpen", when an
// offer raced the close) or its technical English ("Room or item thread
// access required"). For a known server code the person reads plain words
// in their language; the server's text stays for "Copy details" and logs.
@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_error_copy.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';

class _UnusedRootRouter extends Mock implements RootRouter {}

/// The server's help-offer / coordination error names, in wire order
/// (code = 1500 + index).
List<String> _serverCoordinationCodeNames() {
  final source = File(
    '../server/lib/domain/exception_codes.dart',
  ).readAsStringSync();
  final body = RegExp(
    r'enum HelpOfferCoordinationExceptionCode \{([^}]*)\}',
  ).firstMatch(source)!.group(1)!;
  return [
    for (final line in body.split('\n'))
      if (RegExp(r'^\s*(\w+),').firstMatch(line) case final m?) m.group(1)!,
  ];
}

/// Words that belong to code, not to people (terminology.mdc).
final _internalWords = RegExp(
  r'beacon|lobby|\broom\b|thread|item|coordination|exception|\bid\b',
  caseSensitive: false,
);

/// An identifier-looking token such as `beaconNotOpen`.
final _camelCase = RegExp(r'\b[a-z]+[A-Z]\w*\b');

final _cyrillic = RegExp('[а-яё]', caseSensitive: false);

void main() {
  test('every server help-offer code has plain copy', () {
    final names = _serverCoordinationCodeNames();
    expect(names, contains('beaconNotOpen'));
    for (var i = 0; i < names.length; i++) {
      expect(
        serverErrorCopyFor('${1500 + i}'),
        isNotNull,
        reason: '${names[i]} (${1500 + i}) has no plain copy',
      );
    }
  });

  test('the copy is plain words in both languages', () {
    for (final MapEntry(key: code, value: copy) in kServerErrorCopy.entries) {
      for (final text in [copy.en, copy.ru]) {
        expect(text.trim(), isNotEmpty, reason: code);
        expect(_camelCase.hasMatch(text), isFalse, reason: '$code: $text');
        expect(_internalWords.hasMatch(text), isFalse, reason: '$code: $text');
        expect(text.toLowerCase(), isNot(contains('лобби')), reason: code);
      }
      expect(_cyrillic.hasMatch(copy.ru), isTrue, reason: code);
      expect(_cyrillic.hasMatch(copy.en), isFalse, reason: code);
    }
  });

  group('RemoteApiException', () {
    const raced = RemoteApiException('beaconNotOpen', code: '1500');
    const removed = RemoteApiException(
      'Room or item thread access required',
      code: '1102',
    );

    test('a known code reads as plain copy, never the server text', () {
      for (final e in [raced, removed]) {
        expect(e.hasPlainCopy, isTrue);
        expect(e.toL10n('en'), serverErrorCopyFor(e.code)!.en);
        expect(e.toL10n('ru'), serverErrorCopyFor(e.code)!.ru);
        expect(e.toL10n('en'), isNot(contains(e.message)));
        expect(e.toL10n('ru'), isNot(contains(e.message)));
      }
    });

    test('logs and matching keep the server text', () {
      expect(raced.toString(), 'beaconNotOpen');
      expect(raced.message, 'beaconNotOpen');
    });

    test('an unknown code keeps the server message', () {
      const other = RemoteApiException('Title is taken', code: '1999');
      expect(other.hasPlainCopy, isFalse);
      expect(other.toL10n('en'), 'Title is taken');
    });
  });

  group('error bar', () {
    setUp(() {
      GetIt.I
        ..registerSingleton<RootRouter>(_UnusedRootRouter())
        ..registerSingleton<Logger>(Logger('test'));
    });

    tearDown(GetIt.I.reset);

    for (final locale in ['en', 'ru']) {
      testWidgets('shows no raw key for a known code ($locale)', (
        tester,
      ) async {
        const error = RemoteApiException('beaconNotOpen', code: '1500');
        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => dispatchUiEffect(
                      context,
                      const ShowError(error),
                      localeName: locale,
                    ),
                    child: const Text('Show'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final expected = locale == 'en'
            ? serverErrorCopyFor('1500')!.en
            : serverErrorCopyFor('1500')!.ru;
        expect(find.text(expected, findRichText: true), findsOneWidget);
        expect(
          find.textContaining('beaconNotOpen', findRichText: true),
          findsNothing,
        );
      });
    }
  });
}
