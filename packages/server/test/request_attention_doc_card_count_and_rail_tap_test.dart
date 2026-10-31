@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// `docs/features/request-attention.md` is the contract for what lights up and
/// what a tap does. A card's unread count and the My desk rail tap are part of
/// that contract, so each must be stated in a paragraph of its own.
void main() {
  group('Request attention contract documents the My desk card behaviours', () {
    final paragraphs = File('../../docs/features/request-attention.md')
        .readAsStringSync()
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll(RegExp(r'\s+'), ' '));

    bool anyParagraph(bool Function(String p) test) => paragraphs.any(test);

    test('a card unread count skips system lines, like its preview', () {
      expect(
        anyParagraph(
          (p) =>
              RegExp(
                "card'?s? unread count",
                caseSensitive: false,
              ).hasMatch(p) &&
              p.contains('system lines'),
        ),
        isTrue,
        reason:
            'no paragraph of request-attention.md says a card unread count '
            'skips system lines.',
      );
    });

    test('tapping My desk while on it scrolls to the first Request needing '
        'attention', () {
      expect(
        anyParagraph(
          (p) =>
              RegExp(r'\btap(s|ping)?\b', caseSensitive: false).hasMatch(p) &&
              p.contains('My desk') &&
              RegExp('scrolls? to the first Request').hasMatch(p) &&
              p.contains('needs attention'),
        ),
        isTrue,
        reason:
            'no paragraph of request-attention.md says tapping My desk while '
            'on it scrolls to the first Request that needs attention.',
      );
    });
  });
}
