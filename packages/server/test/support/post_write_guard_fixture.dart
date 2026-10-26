import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'pg_test_public_keys.dart';

const guardAuthor = 'Upostguardauthor';
const guardMember = 'Upostguardmember';
const guardOther = 'Upostguardother';
const guardPost = 'Bpostguardpost';
const guardMessage = 'Rpostguardbase';
const guardPollMessage = 'Rpostguardpoll';
const guardBatonMessage = 'Rpostguardbaton';
const guardPoll = 'Ppostguardpoll';
const guardVariant = 'Vpostguardone';
const guardBaton = 'Tpostguardbase';

Matcher get postArchived => isA<ServerException>()
    .having((e) => e.code, 'SQLSTATE', '23514')
    .having((e) => e.message, 'message', 'post_archived');

/// Every row is created while the Post is writable. Tests then change only its
/// lifecycle, so a rejection cannot be caused by an invalid fixture.
Future<void> seedPostWriteGuard(Connection writer, {int kind = 1}) async {
  await writer.execute('TRUNCATE public."user" CASCADE');
  for (final (index, id) in [guardAuthor, guardMember, guardOther].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('postguard', index + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$guardPost', '$guardAuthor', '', '', 0, $kind, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fpostguardmember', '$guardPost', '$guardAuthor', '$guardMember'),
       ('Fpostguardother', '$guardPost', '$guardAuthor', '$guardOther')
''');
  await writer.execute('''
INSERT INTO public.polling (id, author_id, question)
VALUES ('$guardPoll', '$guardAuthor', 'Which?')
''');
  await writer.execute('''
INSERT INTO public.polling_variant (id, polling_id, description)
VALUES ('$guardVariant', '$guardPoll', 'One')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body, linked_polling_id)
VALUES ('$guardMessage', '$guardPost', '$guardAuthor', 'Original', NULL),
       ('$guardPollMessage', '$guardPost', '$guardAuthor', '', '$guardPoll'),
       ('$guardBatonMessage', '$guardPost', '$guardAuthor', 'Take it', NULL)
''');
  await writer.execute('''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id)
VALUES ('$guardBaton', '$guardBatonMessage', '$guardPost', '$guardAuthor')
''');
}

Future<void> archiveGuardPost(Connection writer, String state) async {
  switch (state) {
    case 'expired':
      await writer.execute('''
UPDATE public.beacon SET expires_at = now() - interval '1 second'
WHERE id = '$guardPost'
''');
    case 'closed':
      await writer.execute(
        "UPDATE public.beacon SET status = 6 WHERE id = '$guardPost'",
      );
    case 'deleted':
      await writer.execute(
        "UPDATE public.beacon SET status = 2 WHERE id = '$guardPost'",
      );
    default:
      throw ArgumentError.value(state);
  }
}

final class PostWriteProbe {
  const PostWriteProbe(
    this.table,
    this.insert,
    this.update,
    this.read,
    this.original,
    this.changed,
  );

  final String table;
  final String insert;
  final String update;
  final String read;
  final Object original;
  final Object changed;
}

const postWriteProbes = [
  PostWriteProbe(
    'beacon_room_message',
    "INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) VALUES ('Rpostguardwrite', '$guardPost', '$guardMember', 'Before')",
    "UPDATE public.beacon_room_message SET body = 'After' WHERE id = 'Rpostguardwrite'",
    "SELECT body FROM public.beacon_room_message WHERE id = 'Rpostguardwrite'",
    'Before',
    'After',
  ),
  PostWriteProbe(
    'beacon_room_message_reaction',
    "INSERT INTO public.beacon_room_message_reaction (id, message_id, user_id, emoji) VALUES ('Epostguardwrite', '$guardMessage', '$guardMember', '👍')",
    "UPDATE public.beacon_room_message_reaction SET emoji = '❤️' WHERE id = 'Epostguardwrite'",
    "SELECT emoji FROM public.beacon_room_message_reaction WHERE id = 'Epostguardwrite'",
    '👍',
    '❤️',
  ),
  PostWriteProbe(
    'beacon_room_message_attachment',
    "INSERT INTO public.beacon_room_message_attachment (id, message_id, kind, file_url, file_name) VALUES ('Apostguardwrite', '$guardMessage', 1, 'https://example.test/file', 'Before')",
    "UPDATE public.beacon_room_message_attachment SET file_name = 'After' WHERE id = 'Apostguardwrite'",
    "SELECT file_name FROM public.beacon_room_message_attachment WHERE id = 'Apostguardwrite'",
    'Before',
    'After',
  ),
  PostWriteProbe(
    'polling_act',
    "INSERT INTO public.polling_act (author_id, polling_id, polling_variant_id, score) VALUES ('$guardMember', '$guardPoll', '$guardVariant', 1)",
    "UPDATE public.polling_act SET score = 2 WHERE author_id = '$guardMember' AND polling_variant_id = '$guardVariant'",
    "SELECT score::int FROM public.polling_act WHERE author_id = '$guardMember' AND polling_variant_id = '$guardVariant'",
    1,
    2,
  ),
  PostWriteProbe(
    'beacon_room_baton',
    "INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id) VALUES ('Tpostguardwrite', '$guardMessage', '$guardPost', '$guardAuthor')",
    "UPDATE public.beacon_room_baton SET status = 2 WHERE id = 'Tpostguardwrite'",
    "SELECT status::int FROM public.beacon_room_baton WHERE id = 'Tpostguardwrite'",
    0,
    2,
  ),
  PostWriteProbe(
    'beacon_room_baton_candidate',
    "INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier) VALUES ('$guardBaton', '$guardMember', 1)",
    "UPDATE public.beacon_room_baton_candidate SET response = 1, responded_at = now() WHERE baton_id = '$guardBaton' AND user_id = '$guardMember'",
    "SELECT response::int FROM public.beacon_room_baton_candidate WHERE baton_id = '$guardBaton' AND user_id = '$guardMember'",
    0,
    1,
  ),
  PostWriteProbe(
    'vote_beacon',
    "INSERT INTO public.vote_beacon (subject, object, amount) VALUES ('$guardMember', '$guardPost', 1)",
    "UPDATE public.vote_beacon SET amount = 2 WHERE subject = '$guardMember' AND object = '$guardPost'",
    "SELECT amount FROM public.vote_beacon WHERE subject = '$guardMember' AND object = '$guardPost'",
    1,
    2,
  ),
  PostWriteProbe(
    'polling_variant',
    "INSERT INTO public.polling_variant (id, polling_id, description) VALUES ('Vpostguardwrite', '$guardPoll', 'Before')",
    "UPDATE public.polling_variant SET description = 'After' WHERE id = 'Vpostguardwrite'",
    "SELECT description FROM public.polling_variant WHERE id = 'Vpostguardwrite'",
    'Before',
    'After',
  ),
];
