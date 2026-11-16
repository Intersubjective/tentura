import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';

// The push/email sentence for an expiring Post and the client's row text use
// the same hour count (rounded up) and the same words; the client's words are
// read from its ARB files, so a drift on either side fails here.

final _now = DateTime.utc(2026, 11, 16, 9);

const _identity = NotificationIdentity(
  entityKind: NotificationEntityKind.post,
  label: 'Free apples',
  tombstone: false,
  readable: true,
  actorName: null,
  actorHidden: false,
  relatedLabel: null,
  expired: false,
);

String _sentence(String locale, Duration left) =>
    const NotificationCopyRenderer()
        .render(
          presentationKey: 'post_expiring_soon',
          kind: null,
          facts: {'expiresAt': _now.add(left).toIso8601String()},
          identity: _identity,
          locale: locale,
          tzOffsetMinutes: 0,
          now: _now,
        )
        .sentence;

String _clientText(String locale, int hours) {
  final arb =
      jsonDecode(File('../client/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;
  return (arb['updatesPostExpiresInBody']! as String).replaceAll(
    '{hours}',
    '$hours',
  );
}

void main() {
  group('expiring Post countdown', () {
    for (final locale in const ['en', 'ru']) {
      for (final (minutes, hours) in const [(90, 2), (30, 1), (180, 3)]) {
        test('$locale: $minutes minutes left is $hours h in push and client '
            'row text', () {
          expect(
            _sentence(locale, Duration(minutes: minutes)),
            _clientText(locale, hours),
          );
        });
      }
    }
  });
}
