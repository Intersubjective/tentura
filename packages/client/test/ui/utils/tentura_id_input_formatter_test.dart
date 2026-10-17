import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/utils/tentura_id_input_formatter.dart';

void main() {
  const empty = TextEditingValue();
  const inviteFormatter = InviteCodeInputFormatter();
  const entityFormatter = EntityIdInputFormatter();

  TextEditingValue paste(String text) => inviteFormatter.formatEditUpdate(
        empty,
        TextEditingValue(text: text),
      );

  group('InviteCodeInputFormatter', () {
    test('ctrl-v full invite URL becomes bare code', () {
      expect(
        paste('https://dev.tentura.io/invite/I806d29daebbe').text,
        'I806d29daebbe',
      );
    });

    test('allows progressive typing', () {
      var value = empty;
      for (final ch in 'I806d29daebbe'.split('')) {
        value = inviteFormatter.formatEditUpdate(
          value,
          TextEditingValue(
            text: value.text + ch,
            selection: TextSelection.collapsed(offset: value.text.length + 1),
          ),
        );
      }
      expect(value.text, 'I806d29daebbe');
    });

    test('strips trailing dash from pasted fragment', () {
      expect(
        paste('https://dev.tentura.io/invite/I806d29daebbe-').text,
        'I806d29daebbe',
      );
    });
  });

  group('EntityIdInputFormatter', () {
    test('ctrl-v invite URL becomes bare code', () {
      final value = entityFormatter.formatEditUpdate(
        empty,
        const TextEditingValue(
          text: 'https://dev.tentura.io/invite/I806d29daebbe',
        ),
      );
      expect(value.text, 'I806d29daebbe');
    });

    test('allows manual profile id entry', () {
      final value = entityFormatter.formatEditUpdate(
        empty,
        const TextEditingValue(text: 'Uabc123def456'),
      );
      expect(value.text, 'Uabc123def456');
    });
  });

  // #460: the handle field dropped uppercase letters and spaces as they were
  // typed ("Tab" became "ab"), with no hint why.
  group('UserHandleInputFormatter', () {
    const handleFormatter = UserHandleInputFormatter();

    TextEditingValue type(String text) {
      var value = empty;
      for (final ch in text.split('')) {
        value = handleFormatter.formatEditUpdate(
          value,
          TextEditingValue(
            text: value.text + ch,
            selection: TextSelection.collapsed(offset: value.text.length + 1),
          ),
        );
      }
      return value;
    }

    test('lower-cases letters instead of dropping them', () {
      expect(type('Tab').text, 'tab');
    });

    test('turns spaces into underscores', () {
      expect(type('Ann Lee').text, 'ann_lee');
    });

    test('still drops other characters', () {
      expect(type('ann.lee!').text, 'annlee');
    });

    test('keeps the caret where the edit happened', () {
      final value = handleFormatter.formatEditUpdate(
        const TextEditingValue(
          text: 'anlee',
          selection: TextSelection.collapsed(offset: 2),
        ),
        const TextEditingValue(
          text: 'anN lee',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(value.text, 'ann_lee');
      expect(value.selection, const TextSelection.collapsed(offset: 4));
    });
  });
}
