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
      // The emoji's two code units straddle the cut (the limit less the
      // room for the ellipsis); there is no word boundary to cut at.
      final line = '${'a' * (kBeaconTitleMaxLength - 2)}👍 tail';
      final title = MessagePrefillCase.fromText(line).title;
      expect(title, '${'a' * (kBeaconTitleMaxLength - 2)}…');
      expect(title.length, lessThanOrEqualTo(kBeaconTitleMaxLength));
    });

    test('a long first line is cut at a word, the whole text kept', () {
      // #729: the Post text from the QA run (85 code units).
      const body =
          'GQ1024: planning a weekend community garden cleanup — '
          "who's in? Need tools + a truck.";
      final prefill = MessagePrefillCase.fromText(body);
      expect(
        prefill.title,
        "GQ1024: planning a weekend community garden cleanup — who's…",
      );
      expect(prefill.title.length, lessThanOrEqualTo(kBeaconTitleMaxLength));
      expect(prefill.description, body);
    });

    test('a long first line keeps the following lines in the description', () {
      final line = List.filled(20, 'word').join(' ');
      final prefill = MessagePrefillCase.fromText('$line\nSaturday.');
      expect(prefill.title, endsWith('word…'));
      expect(prefill.title.length, lessThanOrEqualTo(kBeaconTitleMaxLength));
      expect(prefill.description, '$line\nSaturday.');
    });

    test('a cut right at a word end keeps that word', () {
      // The limit less one falls exactly before a space.
      final line = '${'a' * (kBeaconTitleMaxLength - 1)} more words';
      expect(
        MessagePrefillCase.fromText(line).title,
        '${'a' * (kBeaconTitleMaxLength - 1)}…',
      );
    });

    test('a title that fits is kept whole', () {
      final line = '${'a' * (kBeaconTitleMaxLength - 2)}👍';
      expect(MessagePrefillCase.fromText(line).title, line);
    });
  });
}
