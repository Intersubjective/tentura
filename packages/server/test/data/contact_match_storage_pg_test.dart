@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/contact_match_storage.dart';
import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/util/contact_match_key_ring.dart';

import '../support/disposable_pg_target.dart';

const _aliceId = 'Umatchalice01';
const _bobId = 'Umatchbob0002';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONTACT_MATCH_TEST_DB',
    defaultNamePrefix: 'tentura_test_contact_match',
  );
  final skipReason = await pgSkipReason(target);

  group('Verified email lookup across key rotations', () {
    late Connection writer;
    final ring = ContactMatchKeyRing.parse('1:secretA,2:secretB');

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      await writer.execute('''
ALTER TABLE public.account_verified_contact
  ADD COLUMN IF NOT EXISTS match_hmac bytea,
  ADD COLUMN IF NOT EXISTS hmac_key_version smallint
''');
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_aliceId', 'Alice', 'contact-match-alice'),
       ('$_bobId', 'Bob', 'contact-match-bob')
''');
      // Fixed vectors for the persisted emails under secretA and secretB.
      await writer.execute('''
INSERT INTO public.account_verified_contact
  (id, account_id, kind, value, last_source, match_hmac, hmac_key_version)
VALUES
  ('Vmatchalice1', '$_aliceId', 'email', 'alice@example.com', 'email',
   decode('48aa1da12d16bf39ed58ccd4a9d6c4172114f7c24559042708a561fc5d3bb90c', 'hex'), 1),
  ('Vmatchbob002', '$_bobId', 'email', 'bob@example.com', 'email',
   decode('6aa4f7b41adbc0ead8c4d11bcf23d62767d603047cb6247194b7a02983dac8d7', 'hex'), 2)
''');
    });

    test('finds a normalized email hashed before rotation', () async {
      final matches = await findMatchingVerifiedAccounts(
        writer,
        ring,
        kind: ContactKind.email,
        value: ' ALICE@example.com ',
      );
      expect(matches, {_aliceId});
      final wrongOldKey = ContactMatchKeyRing.parse('1:other,2:secretB');
      expect(
        await findMatchingVerifiedAccounts(
          writer,
          wrongOldKey,
          kind: ContactKind.email,
          value: 'alice@example.com',
        ),
        isEmpty,
      );
    });

    test('finds an email stored with the newest key', () async {
      expect(
        await findMatchingVerifiedAccounts(
          writer,
          ring,
          kind: ContactKind.email,
          value: 'bob@example.com',
        ),
        {_bobId},
      );
    });

    test('returns no match for an absent email', () async {
      expect(
        await findMatchingVerifiedAccounts(
          writer,
          ring,
          kind: ContactKind.email,
          value: 'absent@example.com',
        ),
        isEmpty,
      );
    });

    test(
      'returns no match for a phone lookup even with a matching value',
      () async {
        expect(
          await findMatchingVerifiedAccounts(
            writer,
            ring,
            kind: ContactKind.phone,
            value: 'alice@example.com',
          ),
          isEmpty,
        );
      },
    );
  }, skip: skipReason);
}
