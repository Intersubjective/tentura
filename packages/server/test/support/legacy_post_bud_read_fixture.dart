import 'package:postgres/postgres.dart';

import 'pg_test_public_keys.dart';

/// A previously budded Request with legacy observer rows for two Post members.
/// Only one of them was sent the Request.
abstract final class LegacyPostBudReadFixture {
  static const child = 'Bhasurabud01';
  static const uninvited = 'Uhasurabud01';
  static const invited = 'Uhasurabud02';
  static const post = 'Bhasurabud02';
  static const author = 'Uhasurabud03';

  static Future<void> seed(Connection writer) async {
    for (final (i, id) in [author, uninvited, invited].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': pgTestPublicKey('hasura-bud', i + 1)},
      );
    }
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   forward_policy, published_at)
VALUES ('$post', '$author', '', '', 0, 1, false, 1, now())
''');
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable,
   parent_beacon_id, published_at)
VALUES ('$child', '$author', 'Request', '', 0, false, '$post', now())
''');
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$post', '$author', '$uninvited'),
       ('$post', '$author', '$invited'),
       ('$child', '$author', '$invited')
''');
    await writer.execute('''
INSERT INTO public.beacon_bud_observer (beacon_id, user_id)
VALUES ('$child', '$uninvited'), ('$child', '$invited')
''');
  }
}
