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
    expect(type('', 'e\u0301e\u0301e\u0301e\u0301').text, 'e\u0301e\u0301e\u0301');
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
    expect(CodeUnitLengthLimitingTextInputFormatter.truncate('ab😀', 4), 'ab😀');
  });
}
