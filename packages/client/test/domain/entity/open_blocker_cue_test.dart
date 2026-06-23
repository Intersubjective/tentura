import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/open_blocker_cue.dart';

final _fixedTime = DateTime.utc(2026, 6, 1);

void main() {
  group('resolveResponsibleUserId', () {
    test('uses target person when provided', () {
      expect(
        OpenBlockerCue.resolveResponsibleUserId(
          creatorId: 'creator',
          targetPersonId: 'target',
        ),
        'target',
      );
    });

    test('falls back to creator when target is empty', () {
      expect(
        OpenBlockerCue.resolveResponsibleUserId(
          creatorId: 'creator',
          targetPersonId: '',
        ),
        'creator',
      );
      expect(
        OpenBlockerCue.resolveResponsibleUserId(
          creatorId: 'creator',
          targetPersonId: '   ',
        ),
        'creator',
      );
    });
  });

  group('isResponsible', () {
    test('matches responsible user id', () {
      final cue = OpenBlockerCue(
        creatorId: 'creator',
        raisedAt: _fixedTime,
        responsibleUserId: 'user-a',
      );
      expect(cue.isResponsible('user-a'), isTrue);
      expect(cue.isResponsible('user-b'), isFalse);
    });
  });
}
