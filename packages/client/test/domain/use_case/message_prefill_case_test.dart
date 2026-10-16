import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/use_case/message_prefill_case.dart';

void main() {
  group('MessagePrefillCase.fromText', () {
    test('first line becomes the title, the rest the description', () {
      final prefill = MessagePrefillCase.fromText(' Title \n body ');
      expect(prefill.title, 'Title');
      expect(prefill.description, 'body');
    });

    test('cutting a long title never splits an emoji', () {
      // The emoji's two code units straddle the title limit.
      final line = '${'a' * (kBeaconTitleMaxLength - 1)}👍 tail';
      final title = MessagePrefillCase.fromText(line).title;
      expect(title, 'a' * (kBeaconTitleMaxLength - 1));
      expect(title.length, lessThanOrEqualTo(kBeaconTitleMaxLength));
    });

    test('a title that fits is kept whole', () {
      final line = '${'a' * (kBeaconTitleMaxLength - 2)}👍';
      expect(MessagePrefillCase.fromText(line).title, line);
    });
  });
}
