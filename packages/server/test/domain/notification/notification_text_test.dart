// Pure text helpers shared by every notification channel
// (docs/plans/notification-identity-spec.md §4.3–4.4).
@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/notification/notification_text.dart';

void main() {
  const family = '👨\u200D👩\u200D👧';

  group('server pubspec', () {
    test('lists characters as a direct dependency', () {
      final text = File('pubspec.yaml').readAsStringSync();
      final deps = RegExp(
        r'^dependencies:\n((?:[ \t].*\n|\n)*)',
        multiLine: true,
      ).firstMatch(text)!.group(1)!;
      expect(
        RegExp(r'^\s{2}characters:', multiLine: true).hasMatch(deps),
        isTrue,
      );
    });
  });

  group('NotificationText.normalize', () {
    test('strips bidi controls and zero-width characters', () {
      expect(NotificationText.normalize('Ann\u202Ea\u200B'), 'Anna');
      expect(
        NotificationText.normalize('a\u200Eb\u200Fc\u2066d\u2069e'),
        'abcde',
      );
    });

    test('strips every bidi control at both ends of each range', () {
      for (final cp in [
        0x202A,
        0x202B,
        0x202C,
        0x202D,
        0x202E,
        0x2066,
        0x2067,
        0x2068,
        0x2069,
        0x200E,
        0x200F,
      ]) {
        expect(
          NotificationText.normalize('a${String.fromCharCode(cp)}b'),
          'ab',
          reason: cp.toRadixString(16),
        );
      }
    });

    test('strips bare zero-width space and joiners outside emoji', () {
      expect(NotificationText.normalize('a\u200Bb'), 'ab');
      expect(NotificationText.normalize('a\u200Db'), 'ab');
    });

    test('strips C0 control characters', () {
      expect(NotificationText.normalize('x\u0007y'), 'xy');
    });

    test('strips C1 control characters', () {
      expect(NotificationText.normalize('x\u0085y\u009Fz'), 'xyz');
    });

    test('keeps ZWJ emoji sequences byte for byte', () {
      expect(NotificationText.normalize(family), family);
      expect(NotificationText.normalize('hi $family!'), 'hi $family!');
    });

    test('collapses whitespace runs and trims', () {
      expect(
        NotificationText.normalize('  Fix\r\n\tthe   roof \n'),
        'Fix the roof',
      );
    });
  });

  group('NotificationText.truncate', () {
    test('exact limit is unchanged', () {
      expect(NotificationText.truncate('abcdefghij', 10), 'abcdefghij');
    });

    test('limit + 1 drops exactly enough to fit the ellipsis', () {
      expect(NotificationText.truncate('abcdefghijk', 10), 'abcdefghi…');
    });

    test('cuts at a space in the last 30% of the limit', () {
      // Space at index 17 (>= 14): cut there, not hard at 19.
      expect(
        NotificationText.truncate('abcdefghijklmnopq rstuvwxyz', 20),
        'abcdefghijklmnopq…',
      );
    });

    test('uses a space at exactly 70% of the limit', () {
      // limit 20: index 14 qualifies.
      expect(
        NotificationText.truncate('abcdefghijklmn opqrstuvwxyz', 20),
        'abcdefghijklmn…',
      );
    });

    test('ignores a space just before the 70% window', () {
      // index 13 does not qualify: hard cut at 19.
      expect(
        NotificationText.truncate('abcdefghijklm nopqrstuvwxyz', 20),
        'abcdefghijklm nopqr…',
      );
    });

    test('drops trailing whitespace before the ellipsis', () {
      expect(
        NotificationText.truncate('abcdefghijklmnop  qrstuvwxyz', 20),
        'abcdefghijklmnop…',
      );
    });

    test('ignores a space outside the window and cuts hard', () {
      expect(
        NotificationText.truncate('Fix the roof before winter', 20),
        'Fix the roof before…',
      );
    });

    test('cuts hard when no space is in the window', () {
      const word = 'abcdefghijklmnopqrstuvwxyzabcd';
      expect(NotificationText.truncate(word, 20), '${word.substring(0, 19)}…');
    });

    test('keeps or drops whole ZWJ emoji', () {
      const input = 'ab$family$family$family';
      expect(NotificationText.truncate(input, 4), 'ab$family…');
      expect(NotificationText.truncate(input, 3), 'ab…');
      expect(NotificationText.truncate(input, 2), 'a…');
    });

    test('keeps or drops whole surrogate-pair emoji', () {
      expect(NotificationText.truncate('😀😀😀😀😀😀', 4), '😀😀😀…');
      expect(NotificationText.truncate('😀😀😀😀😀😀', 2), '😀…');
    });

    test('keeps or drops whole base + combining mark', () {
      const e = 'e\u0301';
      expect(NotificationText.truncate(e * 8, 4), '${e * 3}…');
      expect(NotificationText.truncate(e * 8, 2), '$e…');
    });
  });

  group('NotificationText.quote', () {
    test('wraps in guillemets for en and ru', () {
      expect(NotificationText.quote('Fix the roof', 'en'), '«Fix the roof»');
      expect(
        NotificationText.quote('Починить крышу', 'ru'),
        '«Починить крышу»',
      );
    });

    test('truncates the label before quoting', () {
      final r = NotificationText.quote(
        'Fix the roof before winter comes',
        'en',
        limit: 20,
      );
      expect(r, startsWith('«'));
      expect(r, endsWith('…»'));
      expect('…'.allMatches(r).length, 1);
      // «, 20-grapheme label (ellipsis included), » -> 22 at most.
      expect(r.characters.length, lessThanOrEqualTo(22));
      expect(r.length, greaterThan(12));
      expect(r.indexOf('…'), lessThan(r.indexOf('»')));
    });
  });

  group('NotificationText.plural', () {
    String ru(int n) =>
        NotificationText.plural(n, 'ru', one: 'день', few: 'дня', many: 'дней');
    String en(int n, [String l = 'en']) =>
        NotificationText.plural(n, l, one: 'day', few: 'few', many: 'days');

    test('ru follows CLDR', () {
      expect(
        {
          for (final n in [1, 21]) n: ru(n),
        }.values.toSet(),
        {'день'},
      );
      expect(
        {
          for (final n in [2, 22, 24]) n: ru(n),
        }.values.toSet(),
        {'дня'},
      );
      expect(
        {
          for (final n in [0, 5, 11, 12, 14, 25, 111]) n: ru(n),
        }.values.toSet(),
        {'дней'},
      );
    });

    test('en: one only for 1', () {
      expect(en(1), 'day');
      for (final n in [0, 2, 11, 21, 22]) {
        expect(en(n), 'days', reason: '$n');
      }
    });

    test('locale prefix selects the rule set', () {
      expect(
        NotificationText.plural(
          21,
          'ru-RU',
          one: 'день',
          few: 'дня',
          many: 'дней',
        ),
        'день',
      );
      expect(en(21, 'de'), 'days');
      expect(en(21, ''), 'days');
    });
  });

  group('NotificationText.formatDate', () {
    String f(String iso, int off, String loc, int year) =>
        NotificationText.formatDate(
          DateTime.parse(iso),
          loc,
          tzOffsetMinutes: off,
          now: DateTime.utc(year, 6),
        );

    test('shifts by the offset', () {
      expect(f('2026-11-21T15:00:00Z', 180, 'en', 2026), '21 Nov, 18:00');
      expect(f('2026-11-21T15:00:00Z', 180, 'ru', 2026), '21 ноября, 18:00');
    });

    test('crosses midnight forward and backward', () {
      expect(f('2026-11-20T22:30:00Z', 180, 'en', 2026), '21 Nov, 01:30');
      expect(f('2026-11-20T22:30:00Z', 180, 'ru', 2026), '21 ноября, 01:30');
      expect(f('2026-11-21T02:00:00Z', -300, 'en', 2026), '20 Nov, 21:00');
      expect(f('2026-11-21T02:00:00Z', -300, 'ru', 2026), '20 ноября, 21:00');
    });

    test('adds the year only when it differs from the current year', () {
      expect(f('2026-12-31T22:30:00Z', 180, 'en', 2026), '1 Jan 2027, 01:30');
      expect(
        f('2026-12-31T22:30:00Z', 180, 'ru', 2026),
        '1 января 2027, 01:30',
      );
      expect(f('2026-12-31T22:30:00Z', 180, 'en', 2027), '1 Jan, 01:30');
      expect(f('2026-12-31T22:30:00Z', 180, 'ru', 2027), '1 января, 01:30');
    });
  });

  group('NotificationText.formatDate months', () {
    const en = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const ru = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    test('every month has its EN short and RU genitive name', () {
      for (var m = 1; m <= 12; m++) {
        final at = DateTime.utc(2026, m, 15, 12);
        final now = DateTime.utc(2026, 6);
        expect(
          NotificationText.formatDate(at, 'en', tzOffsetMinutes: 0, now: now),
          '15 ${en[m - 1]}, 12:00',
        );
        expect(
          NotificationText.formatDate(at, 'ru', tzOffsetMinutes: 0, now: now),
          '15 ${ru[m - 1]}, 12:00',
        );
      }
    });
  });

  group('NotificationText.formatDate current year', () {
    test('uses the offset-shifted year of now', () {
      // now is 2026 in UTC but already 2027 locally (+180).
      expect(
        NotificationText.formatDate(
          DateTime.utc(2027, 1, 10, 12),
          'en',
          tzOffsetMinutes: 180,
          now: DateTime.utc(2026, 12, 31, 23),
        ),
        '10 Jan, 15:00',
      );
      // now is 2027 in UTC but still 2026 locally (-300).
      expect(
        NotificationText.formatDate(
          DateTime.utc(2026, 6, 1, 12),
          'en',
          tzOffsetMinutes: -300,
          now: DateTime.utc(2027, 1, 1, 0, 30),
        ),
        '1 Jun, 07:00',
      );
    });

    test('never prints ISO', () {
      final iso = RegExp(r'\d{4}-\d{2}-\d{2}|\dT\d|\dZ');
      for (final loc in ['en', 'ru']) {
        final r = NotificationText.formatDate(
          DateTime.utc(2026, 11, 21, 15),
          loc,
          tzOffsetMinutes: 180,
          now: DateTime.utc(2026, 6),
        );
        expect(r, isNotEmpty);
        expect(iso.hasMatch(r), isFalse, reason: r);
      }
    });
  });

  group('NotificationText.statusLabel', () {
    const keys = {
      'open': 'beaconLifecycleOpen',
      'closed': 'beaconLifecycleClosed',
      'deleted': 'beaconLifecycleDeleted',
      'draft': 'beaconLifecycleDraft',
      'cancelled': 'beaconLifecycleCancelled',
      'reviewOpen': 'beaconLifecycleReviewOpen',
    };

    test('server words equal the client ARB words', () {
      for (final loc in ['en', 'ru']) {
        final arb =
            jsonDecode(File('../client/l10n/app_$loc.arb').readAsStringSync())
                as Map<String, dynamic>;
        keys.forEach((status, key) {
          expect(arb[key], isNotNull, reason: key);
          expect(
            NotificationText.statusLabel(status, loc),
            arb[key],
            reason: '$status/$loc',
          );
        });
      }
    });

    test('has the expected words', () {
      expect(NotificationText.statusLabel('reviewOpen', 'en'), 'Final check');
      expect(NotificationText.statusLabel('deleted', 'ru'), 'Удалён');
    });
  });
}
