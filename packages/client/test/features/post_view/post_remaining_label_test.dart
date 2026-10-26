import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  group('Post remaining lifetime label in Russian', () {
    final l10n = L10nRu();
    for (final entry in <Duration, String>{
      const Duration(hours: 72): 'осталось 3 д',
      const Duration(hours: 47, minutes: 59): 'осталось 1 д',
      const Duration(hours: 24): 'осталось 1 д',
      const Duration(hours: 23, minutes: 59): 'осталось 23 ч',
      const Duration(hours: 1): 'осталось 1 ч',
      const Duration(minutes: 59): 'осталось 59 мин',
      const Duration(minutes: 1): 'осталось 1 мин',
      const Duration(seconds: 10): 'осталось 1 мин',
      Duration.zero: 'осталось 1 мин',
    }.entries) {
      test('${entry.key} is formatted as ${entry.value}', () {
        expect(postRemainingLabel(l10n, entry.key), entry.value);
      });
    }
  });
}
