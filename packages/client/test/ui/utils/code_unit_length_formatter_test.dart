import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/utils/code_unit_length_formatter.dart';

void main() {
  const formatter = CodeUnitLengthLimitingTextInputFormatter(6);

  TextEditingValue type(String old, String text) => formatter.formatEditUpdate(
    TextEditingValue(text: old),
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );

  test('text within the cap passes unchanged', () {
    expect(type('', 'abcdef').text, 'abcdef');
  });

  test('caps by UTF-16 code units, so the validators accept the result', () {
    // Four emoji are four characters but eight code units.
    final value = type('', '😀😀😀😀');
    expect(value.text, '😀😀😀');
    expect(value.text.length, lessThanOrEqualTo(6));
    expect(value.selection, const TextSelection.collapsed(offset: 6));
  });

  test('never splits an emoji or a grapheme cluster', () {
    expect(type('', 'abcde😀').text, 'abcde');
    // A family emoji is one character of 8 code units: it does not fit at all.
    expect(type('', 'a👨‍👩‍👧').text, 'a');
    expect(
      type('', 'e\u0301e\u0301e\u0301e\u0301').text,
      'e\u0301e\u0301e\u0301',
    );
  });

  test('an over-long existing value can still be shortened', () {
    final value = formatter.formatEditUpdate(
      const TextEditingValue(text: 'abcdefgh'),
      const TextEditingValue(text: 'abcdefg'),
    );
    expect(value.text, 'abcdefg');
  });

  test('truncate', () {
    expect(CodeUnitLengthLimitingTextInputFormatter.truncate('ab😀', 3), 'ab');
    expect(
      CodeUnitLengthLimitingTextInputFormatter.truncate('ab😀', 4),
      'ab😀',
    );
  });

  test('leaves a composing (IME) value alone until it commits', () {
    // Three phonetic letters on top of 5 units: over the cap while composing.
    const composing = TextEditingValue(
      text: 'abcdenih',
      selection: TextSelection.collapsed(offset: 8),
      composing: TextRange(start: 5, end: 8),
    );
    final during = formatter.formatEditUpdate(
      const TextEditingValue(text: 'abcde'),
      composing,
    );
    expect(during, composing);
    // It commits to one ideograph that fits.
    expect(type('abcde', 'abcde你').text, 'abcde你');
    // A commit that is still too long is capped once composition ends.
    expect(type('abcde', 'abcde你好').text, 'abcde你');
  });

  test('does not delete an accepted emoji when a modifier would not fit', () {
    final value = type('abcd👍', 'abcd👍🏽');
    expect(value.text, 'abcd👍');
  });

  test('a mid-text insertion is trimmed, the existing tail is kept', () {
    final value = formatter.formatEditUpdate(
      const TextEditingValue(
        text: 'abcde',
        selection: TextSelection.collapsed(offset: 2),
      ),
      const TextEditingValue(
        text: 'abXYZcde',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(value.text, 'abXcde');
    expect(value.selection, const TextSelection.collapsed(offset: 3));
  });

  test(
    'an over-cap edit that inserts nothing that fits keeps the old value',
    () {
      expect(type('abcdef', 'abcdefg').text, 'abcdef');
    },
  );

  test('extending a joined emoji at the cap leaves no dangling joiner', () {
    // 👨‍👩 is 5 code units; ZWJ + 👧 inserts 3 with 1 unit of room. Cutting
    // the insertion alone would keep only the invisible ZWJ.
    expect(type('👨\u200D👩', '👨\u200D👩\u200D👧').text, '👨\u200D👩');
  });
}
