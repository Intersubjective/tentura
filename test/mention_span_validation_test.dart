import 'package:test/test.dart';
import 'package:tentura_root/domain/mention_span_validation.dart';

void main() {
  Set<String> tokens(String userId) => switch (userId) {
    'bob' => {'@Bob Smith'},
    _ => const {},
  };

  group('validateExplicitMentionSpans', () {
    test('keeps a valid proposal', () {
      final spans = validateExplicitMentionSpans(
        body: 'Hi @Bob Smith',
        proposals: const [(userId: 'bob', offset: 3, length: 10)],
        acceptableTokensForUserId: tokens,
      );
      expect(spans, [(userId: 'bob', offset: 3, length: 10)]);
    });

    test('drops malformed, overlapping, unmatched, and unknown proposals', () {
      final spans = validateExplicitMentionSpans(
        body: 'Hi @Bob Smith',
        proposals: const [
          (userId: 'bob', offset: -1, length: 10),
          (userId: 'bob', offset: 3, length: 0),
          (userId: 'bob', offset: 3, length: 50),
          (userId: 'nobody', offset: 3, length: 10),
          (userId: 'bob', offset: 3, length: 10),
          (userId: 'bob', offset: 5, length: 5),
        ],
        acceptableTokensForUserId: tokens,
      );
      expect(spans, [(userId: 'bob', offset: 3, length: 10)]);
    });
  });

  test('shifts historical spans without requiring a current display token', () {
    expect(
      shiftMentionSpansThroughTextEdit(
        oldBody: 'Hi @Bob Smith',
        newBody: 'Hello Hi @Bob Smith',
        spans: const [(userId: 'bob', offset: 3, length: 10)],
      ),
      [(userId: 'bob', offset: 9, length: 10)],
    );
  });

  test('never transfers a span to an identical unlinked token', () {
    expect(
      shiftMentionSpansThroughTextEdit(
        oldBody: '@Sam @Sam',
        newBody: '@Sam',
        spans: const [(userId: 'first', offset: 0, length: 4)],
      ),
      isEmpty,
    );
  });

  test('keeps distinct identical spans through an unrelated suffix edit', () {
    expect(
      shiftMentionSpansThroughTextEdit(
        oldBody: '@Sam @Sam end',
        newBody: '@Sam @Sam changed',
        spans: const [
          (userId: 'first', offset: 0, length: 4),
          (userId: 'second', offset: 5, length: 4),
        ],
      ),
      const [
        (userId: 'first', offset: 0, length: 4),
        (userId: 'second', offset: 5, length: 4),
      ],
    );
  });

  test('keeps spans adjacent to an unambiguous replacement edit', () {
    expect(
      shiftMentionSpansThroughTextEdit(
        oldBody: '@Sam!',
        newBody: '@Sam?',
        spans: const [(userId: 'sam', offset: 0, length: 4)],
      ),
      const [(userId: 'sam', offset: 0, length: 4)],
    );
    expect(
      shiftMentionSpansThroughTextEdit(
        oldBody: '!@Sam',
        newBody: '?@Sam',
        spans: const [(userId: 'sam', offset: 1, length: 4)],
      ),
      const [(userId: 'sam', offset: 1, length: 4)],
    );
  });
}
