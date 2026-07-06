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
}
