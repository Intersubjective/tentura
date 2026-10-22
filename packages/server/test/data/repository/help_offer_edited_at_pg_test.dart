@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/help_offer_repository.dart';

import '../../support/disposable_pg_target.dart';

/// #361: `beacon_help_offer.edited_at` moves only when the helper edits an
/// active offer, never on the writes accept/admission make (m0258).
Future<void> main() async {
  const beaconId = 'Bofferedit001';
  const authorId = 'Uofferedauth1';
  const helperId = 'Uofferedhelp1';

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_OFFER_EDITED_AT_TEST_DB',
    defaultNamePrefix: 'tentura_test_offer_edited',
  );
  final skip = await pgSkipReason(target);

  group('beacon_help_offer.edited_at (#361)', () {
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
        message: 'I can bring a van',
        helpTypes: const ['transport'],
      );
    });

    Future<({DateTime? editedAt, DateTime updatedAt})> read() async {
      final rows = await writer.execute(
        Sql.named('''
          SELECT edited_at, updated_at FROM public.beacon_help_offer
          WHERE beacon_id = @beacon AND user_id = @helper
        '''),
        parameters: {'beacon': beaconId, 'helper': helperId},
      );
      final row = rows.single.toColumnMap();
      return (
        editedAt: row['edited_at'] as DateTime?,
        updatedAt: row['updated_at']! as DateTime,
      );
    }

    test('a new offer is not edited', () async {
      expect((await read()).editedAt, isNull);
    }, skip: skip);

    test(
      'accept writes (stake, role label, author response) leave it NULL '
      'while updated_at moves',
      () async {
        final before = await read();
        // What accept/admission writes on the offer row.
        await writer.execute(
          Sql.named('''
            UPDATE public.beacon_help_offer
            SET stake_state = 2, role_label = 'Driver'
            WHERE beacon_id = @beacon AND user_id = @helper
          '''),
          parameters: {'beacon': beaconId, 'helper': helperId},
        );
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon_help_offer_coordination
              (offer_beacon_id, offer_user_id, author_user_id, response_type)
            VALUES (@beacon, @helper, @author, 0)
          '''),
          parameters: {
            'beacon': beaconId,
            'helper': helperId,
            'author': authorId,
          },
        );
        final after = await read();
        expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
        expect(after.editedAt, isNull);
      },
      skip: skip,
    );

    test('re-sending the same offer is not an edit', () async {
      await offers.upsert(
        beaconId: beaconId,
        userId: helperId,
        message: 'I can bring a van',
        helpTypes: const ['transport'],
      );
      expect((await read()).editedAt, isNull);
    }, skip: skip);

    test('the helper changing the text or help types sets it', () async {
      await offers.upsert(
        beaconId: beaconId,
        userId: helperId,
        message: 'I can bring a van at 10',
        helpTypes: const ['transport'],
      );
      final textEdit = await read();
      expect(textEdit.editedAt, isNotNull);

      await offers.upsert(
        beaconId: beaconId,
        userId: helperId,
        message: 'I can bring a van at 10',
        helpTypes: const ['transport', 'tools'],
      );
      final typesEdit = await read();
      expect(typesEdit.editedAt, isNotNull);
      expect(typesEdit.editedAt!.isAfter(textEdit.editedAt!), isTrue);

      // Later accept writes keep the edit time.
      await writer.execute(
        Sql.named('''
          UPDATE public.beacon_help_offer SET stake_state = 2
          WHERE beacon_id = @beacon AND user_id = @helper
        '''),
        parameters: {'beacon': beaconId, 'helper': helperId},
      );
      expect((await read()).editedAt, typesEdit.editedAt);
    }, skip: skip);

    test('withdrawal and removal are not edits', () async {
      await offers.withdraw(
        beaconId: beaconId,
        userId: helperId,
        withdrawReason: 'other',
        message: 'Sorry, the van broke',
      );
      expect((await read()).editedAt, isNull);

      await offers.upsert(
        beaconId: beaconId,
        userId: helperId,
        message: 'Van fixed, offering again',
      );
      expect((await read()).editedAt, isNull);

      await offers.deactivate(beaconId: beaconId, userId: helperId);
      await writer.execute(
        Sql.named('''
          UPDATE public.beacon_help_offer SET status = 0
          WHERE beacon_id = @beacon AND user_id = @helper
        '''),
        parameters: {'beacon': beaconId, 'helper': helperId},
      );
      expect((await read()).editedAt, isNull);
    }, skip: skip);

    test('the column cannot be written around the trigger', () async {
      await writer.execute(
        Sql.named('''
          UPDATE public.beacon_help_offer SET edited_at = now()
          WHERE beacon_id = @beacon AND user_id = @helper
        '''),
        parameters: {'beacon': beaconId, 'helper': helperId},
      );
      expect((await read()).editedAt, isNull);
    }, skip: skip);
  });
}
