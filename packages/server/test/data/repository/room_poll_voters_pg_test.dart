@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_POLL_VOTERS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_poll_voters',
  );
  final skipReason = await pgSkipReason(target);
  late DisposablePgWriterSession session;
  late TenturaDb db;
  late BeaconRoomRepository room;

  const authorId = 'Upollauthor';
  const voterId = 'Upollvoter';
  const observerId = 'Upollobserver';
  const beaconId = 'Bpollvoters';

  setUpAll(() async {
    if (skipReason != null) return;
    session = await setUpDisposablePgWriter(target: target);
    db = TenturaDb(target.databaseEnv);
    room = BeaconRoomRepository(db);
  });

  tearDownAll(() async {
    if (skipReason != null) return;
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  Future<Map<String, dynamic>> readPoll(String pollId, String viewerId) async {
    final rows = await room.listMessagesEnriched(
      beaconId: beaconId,
      viewerUserId: viewerId,
      limit: 10,
    );
    final row = rows.singleWhere((row) => row['id'] == 'M$pollId');
    final poll =
        jsonDecode(row['pollDataJson']! as String) as Map<String, dynamic>;
    expect(poll['id'], pollId);
    expect(poll['totalVotes'], 1);
    final variants = (poll['variants']! as List).cast<Map<String, dynamic>>();
    expect(variants, hasLength(2));
    expect(
      variants.singleWhere(
        (variant) => variant['id'] == 'V${pollId}yes',
      )['votesCount'],
      1,
    );
    expect(
      variants.singleWhere(
        (variant) => variant['id'] == 'V${pollId}no',
      )['votesCount'],
      0,
    );
    return poll;
  }

  void expectHiddenVoters(Map<String, dynamic> poll) {
    for (final variant in poll['variants']! as List) {
      expect(variant as Map, isNot(contains('voterIds')));
    }
  }

  test(
    'room polls reveal voters to non-voting poll authors while preserving anonymity and observer privacy',
    () async {
      final writer = session.writer;
      final users = [authorId, voterId, observerId];
      for (var i = 0; i < users.length; i++) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {
            'id': users[i],
            'key': pgTestPublicKey('pollvoters', i + 1),
          },
        );
      }
      // The room owner and message author differ from the poll author.
      await writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description) '
        "VALUES ('$beaconId', '$observerId', 'Planning', 'Choose a day')",
      );
      for (final pollId in ['Pnamed', 'Panonymous']) {
        final anonymous = pollId == 'Panonymous';
        await writer.execute(
          'INSERT INTO public.polling (id, author_id, question, is_anonymous) '
          "VALUES ('$pollId', '$authorId', 'Which day?', $anonymous)",
        );
        await writer.execute(
          'INSERT INTO public.polling_variant (id, polling_id, description) '
          "VALUES ('V${pollId}yes', '$pollId', 'Monday'), "
          "('V${pollId}no', '$pollId', 'Tuesday')",
        );
        await writer.execute(
          'INSERT INTO public.polling_act '
          '(author_id, polling_id, polling_variant_id) '
          "VALUES ('$voterId', '$pollId', 'V${pollId}yes')",
        );
        await writer.execute(
          'INSERT INTO public.beacon_room_message '
          '(id, beacon_id, author_id, body, linked_polling_id) '
          "VALUES ('M$pollId', '$beaconId', '$observerId', '', '$pollId')",
        );
      }

      final observerPoll = await readPoll('Pnamed', observerId);
      expect(observerPoll['myVariantIds'], isEmpty);
      expectHiddenVoters(observerPoll);

      final voterPoll = await readPoll('Pnamed', voterId);
      expect(voterPoll['isAnonymous'], isFalse);
      expect(voterPoll['myVariantIds'], ['VPnamedyes']);
      final voterVariants = (voterPoll['variants']! as List)
          .cast<Map<String, dynamic>>();
      expect(
        voterVariants.singleWhere(
          (variant) => variant['id'] == 'VPnamedyes',
        )['voterIds'],
        unorderedEquals([voterId]),
        reason: 'A non-author who voted retains access to voter identities',
      );
      expect(
        voterVariants.singleWhere(
          (variant) => variant['id'] == 'VPnamedno',
        )['voterIds'],
        isEmpty,
      );

      // An anonymous poll hides identities even from someone who has voted.
      for (final viewerId in users) {
        final poll = await readPoll('Panonymous', viewerId);
        expect(poll['isAnonymous'], isTrue);
        expect(
          poll['myVariantIds'],
          viewerId == voterId ? ['VPanonymousyes'] : isEmpty,
        );
        expectHiddenVoters(poll);
      }

      // Also exercise an anonymous author who has voted.
      await writer.execute(
        "UPDATE public.polling SET author_id = '$voterId' "
        "WHERE id = 'Panonymous'",
      );
      expectHiddenVoters(await readPoll('Panonymous', voterId));

      final authorPoll = await readPoll('Pnamed', authorId);
      expect(authorPoll['isAnonymous'], isFalse);
      expect(authorPoll['myVariantIds'], isEmpty);
      final variants = (authorPoll['variants']! as List)
          .cast<Map<String, dynamic>>();
      expect(
        variants.singleWhere(
          (variant) => variant['id'] == 'VPnamedyes',
        )['voterIds'],
        unorderedEquals([voterId]),
        reason: 'The poll author can identify voters without casting a vote',
      );
      expect(
        variants.singleWhere(
          (variant) => variant['id'] == 'VPnamedno',
        )['voterIds'],
        isEmpty,
      );
    },
    skip: skipReason,
  );
}
