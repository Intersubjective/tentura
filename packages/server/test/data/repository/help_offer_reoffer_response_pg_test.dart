@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';

import '../../support/disposable_pg_target.dart';

/// #399: a helper who withdrew and offers again gets a fresh offer. The
/// author's answer to the earlier offer (accept or decline) lives in
/// `beacon_help_offer_coordination` and must not survive the re-offer, or the
/// People tab files the new offer under "Not fitting".
Future<void> main() async {
  const beaconId = 'Breoffer00001';
  const authorId = 'Ureofferauth1';
  const helperId = 'Ureofferhelp1';

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_OFFER_REOFFER_TEST_DB',
    defaultNamePrefix: 'tentura_test_offer_reoffer',
  );
  final skip = await pgSkipReason(target);

  group('re-offer after withdrawal (#399)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late HelpOfferRepository offers;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = openDisposablePgDatabase(target);
      offers = HelpOfferRepository(db);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    setUp(() async {
      await writer.execute('''
        TRUNCATE TABLE public.beacon_help_offer_coordination,
          public.beacon_help_offer, public.beacon, public."user" CASCADE
      ''');
      for (final id in [authorId, helperId]) {
        await writer.execute(
          Sql.named('''
            INSERT INTO public."user" (id, display_name, public_key)
            VALUES (@id, @id, @key)
          '''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute(
        Sql.named('''
          INSERT INTO public.beacon (id, user_id, title, description, status)
          VALUES (@beacon, @author, 'Request', 'Needs help', 0)
        '''),
        parameters: {'beacon': beaconId, 'author': authorId},
      );
      await offers.upsert(
        beaconId: beaconId,
        userId: helperId,
        message: 'I can carry the parcel',
      );
    });

    Future<void> authorResponds(CoordinationResponseType response) =>
        writer.execute(
          Sql.named('''
            INSERT INTO public.beacon_help_offer_coordination
              (offer_beacon_id, offer_user_id, author_user_id, response_type)
            VALUES (@beacon, @helper, @author, @response)
            ON CONFLICT (offer_beacon_id, offer_user_id)
            DO UPDATE SET response_type = EXCLUDED.response_type
          '''),
          parameters: {
            'beacon': beaconId,
            'helper': helperId,
            'author': authorId,
            'response': response.smallintValue,
          },
        );

    Future<int?> responseType() async {
      final rows = await writer.execute(
        Sql.named('''
          SELECT response_type FROM public.beacon_help_offer_coordination
          WHERE offer_beacon_id = @beacon AND offer_user_id = @helper
        '''),
        parameters: {'beacon': beaconId, 'helper': helperId},
      );
      return rows.isEmpty ? null : rows.single.first as int?;
    }

    Future<({int status, String message})> offerRow() async {
      final rows = await writer.execute(
        Sql.named('''
          SELECT status, message FROM public.beacon_help_offer
          WHERE beacon_id = @beacon AND user_id = @helper
        '''),
        parameters: {'beacon': beaconId, 'helper': helperId},
      );
      final row = rows.single.toColumnMap();
      return (
        status: row['status']! as int,
        message: row['message']! as String,
      );
    }

    test(
      'an admitted helper who withdrew and offers again has no answer yet',
      () async {
        await authorResponds(CoordinationResponseType.useful);
        await offers.withdraw(
          beaconId: beaconId,
          userId: helperId,
          withdrawReason: 'timing',
        );
        await offers.upsert(
          beaconId: beaconId,
          userId: helperId,
          message: 'Free again, offering once more',
        );

        expect(await responseType(), isNull);
        final row = await offerRow();
        expect(row.status, 0);
        expect(row.message, 'Free again, offering once more');
      },
      skip: skip,
    );

    test('a declined offer withdrawn and offered again is fresh', () async {
      await authorResponds(CoordinationResponseType.notSuitable);
      await offers.withdraw(
        beaconId: beaconId,
        userId: helperId,
        withdrawReason: 'other',
      );
      await offers.upsert(
        beaconId: beaconId,
        userId: helperId,
        message: 'Different plan this time',
      );

      expect(await responseType(), isNull);
    }, skip: skip);

    test('editing an active offer keeps the author answer', () async {
      await authorResponds(CoordinationResponseType.notSuitable);
      await offers.upsert(
        beaconId: beaconId,
        userId: helperId,
        message: 'I can carry the parcel at 10',
      );

      expect(
        await responseType(),
        CoordinationResponseType.notSuitable.smallintValue,
      );
    }, skip: skip);

    test('a withdrawal itself keeps the answer on record', () async {
      await authorResponds(CoordinationResponseType.useful);
      await offers.withdraw(
        beaconId: beaconId,
        userId: helperId,
        withdrawReason: 'timing',
      );

      expect(
        await responseType(),
        CoordinationResponseType.useful.smallintValue,
      );
    }, skip: skip);
  });
}
