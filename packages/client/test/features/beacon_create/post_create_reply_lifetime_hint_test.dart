import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  group('postCreateReplyLifetimeHint copy', () {
    test('EN hint uses segment labels for 6 h, 24 h, and 3 d', () {
      final l10n = lookupL10n(const Locale('en'));
      expect(
        l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime6h),
        'Everyone you send it to can reply under it. It lives up to 6 hours.',
      );
      expect(
        l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime24h),
        'Everyone you send it to can reply under it. It lives up to 24 hours.',
      );
      expect(
        l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime3d),
        'Everyone you send it to can reply under it. It lives up to 3 days.',
      );
    });

    test('RU hint uses segment labels for 6 h, 24 h, and 3 d', () {
      final l10n = lookupL10n(const Locale('ru'));
      expect(
        l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime6h),
        'Все, кому вы отправите, смогут ответить под постом. '
        'Срок жизни: 6 часов.',
      );
      expect(
        l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime24h),
        'Все, кому вы отправите, смогут ответить под постом. '
        'Срок жизни: 24 часа.',
      );
      expect(
        l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime3d),
        'Все, кому вы отправите, смогут ответить под постом. '
        'Срок жизни: 3 дня.',
      );
    });
  });

  group('Post card lifetime chip remaining copy (RU)', () {
    final l10n = lookupL10n(const Locale('ru'));

    test('visible chip prefixes hourglass', () {
      expect(
        postRemainingVisibleLabel(l10n, const Duration(days: 3)),
        startsWith('⏳ '),
      );
    });

    test('day counts on the chip', () {
      const counts = [1, 2, 3, 4, 5, 11, 21];
      for (final count in counts) {
        final label = postRemainingLabel(l10n, Duration(days: count));
        expect(label, 'осталось $count д');
      }
    });
  });
}
