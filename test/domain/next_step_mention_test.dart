import 'package:test/test.dart';

import 'package:tentura_root/domain/next_step_mention.dart';

void main() {
  group('nextStepMentionsPerson (#516)', () {
    test('first name as a word, any case', () {
      expect(
        nextStepMentionsPerson('Omar: dolly', displayName: 'Omar Dinner'),
        isTrue,
      );
      expect(
        nextStepMentionsPerson('van with omar at 9', displayName: 'Omar D'),
        isTrue,
      );
    });

    test('full name and @handle', () {
      expect(
        nextStepMentionsPerson(
          'Ask Nina Mover about keys',
          displayName: 'Nina Mover',
        ),
        isTrue,
      );
      expect(
        nextStepMentionsPerson(
          '@nina_m brings boxes',
          displayName: 'Someone',
          handle: 'nina_m',
        ),
        isTrue,
      );
    });

    test('a handle counts only as an @mention', () {
      expect(
        nextStepMentionsPerson(
          'Nina: van 9:45',
          displayName: 'Omar',
          handle: 'van',
        ),
        isFalse,
      );
    });

    test('Cyrillic names', () {
      expect(
        nextStepMentionsPerson('Ольга везёт коробки', displayName: 'Ольга П.'),
        isTrue,
      );
      expect(
        nextStepMentionsPerson('Ольгин фургон', displayName: 'Ольга'),
        isFalse,
      );
    });

    test('a name inside another word does not count', () {
      expect(
        nextStepMentionsPerson('Omarion drives', displayName: 'Omar'),
        isFalse,
      );
      expect(
        nextStepMentionsPerson('pack the bananas', displayName: 'Ana'),
        isFalse,
      );
    });

    test('one-letter first words and empty input never match', () {
      expect(
        nextStepMentionsPerson('A van at 9', displayName: 'A Smith'),
        isFalse,
      );
      expect(nextStepMentionsPerson('', displayName: 'Omar'), isFalse);
      expect(nextStepMentionsPerson('Omar', displayName: ''), isFalse);
    });

    test('regex characters in a name are literal', () {
      expect(
        nextStepMentionsPerson('call J.R. now', displayName: 'J.R. Ewing'),
        isTrue,
      );
      expect(
        nextStepMentionsPerson('call JxR now', displayName: 'J.R.'),
        isFalse,
      );
    });
  });
}
