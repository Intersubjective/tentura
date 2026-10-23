import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/features/post_view/ui/widget/post_action.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #609: the Post mute line printed a US date (10/5/2026) for Russian users.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  final now = DateTime(2026, 10, 3, 12);
  final until = DateTime(2026, 10, 5, 18, 40);

  test('ru mute line shows dd.MM.yyyy', () {
    final line = postMuteLine(
      lookupL10n(const Locale('ru')),
      mutedForever: false,
      mutedUntil: until,
      now: now,
    );
    expect(line, contains('05.10.2026 18:40'));
    expect(line, isNot(contains('10/5/2026')));
  });

  test('en mute line keeps M/d/yyyy', () {
    final line = postMuteLine(
      lookupL10n(const Locale('en')),
      mutedForever: false,
      mutedUntil: until,
      now: now,
    );
    expect(line, contains('10/5/2026 18:40'));
  });

  test('same day shows the time only (guard)', () {
    expect(
      postMuteUntilTime(DateTime(2026, 10, 3, 18, 40), now, locale: 'ru'),
      '18:40',
    );
  });
}
