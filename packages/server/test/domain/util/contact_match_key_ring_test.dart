import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/util/contact_match_key_ring.dart';

const _alice = 'alice@example.com';
const _aliceV1 =
    '48aa1da12d16bf39ed58ccd4a9d6c4172114f7c24559042708a561fc5d3bb90c';
const _aliceV2 =
    'c783a52c10187f0bf32158a835c13374cc76fc19b20f616198ddcb819bfe3692';
const _bobV2 =
    '6aa4f7b41adbc0ead8c4d11bcf23d62767d603047cb6247194b7a02983dac8d7';

void main() {
  group('Email contact match keys', () {
    final ring = ContactMatchKeyRing.parse('2:secretB,1:secretA');

    test('loads both versions and chooses the highest in either order', () {
      for (final config in ['1:secretA,2:secretB', '2:secretB,1:secretA']) {
        final parsed = ContactMatchKeyRing.parse(config);
        expect(parsed.versions, unorderedEquals([1, 2]), reason: config);
        expect(parsed.newestVersion, 2, reason: config);
      }
    });

    test('writes a normalized email with the newest HMAC-SHA256 key', () {
      final hash = ring.hashForWrite(ContactKind.email, ' Alice@Example.COM ');
      expect(hash?.version, 2);
      expect(hash?.digest.toString(), _aliceV2);
      expect(hash, ring.hashForWrite(ContactKind.email, _alice));
    });

    test('produces different digests for different emails', () {
      final alice = ring.hashForWrite(ContactKind.email, _alice);
      final bob = ring.hashForWrite(ContactKind.email, 'bob@example.com');
      expect(alice?.digest.toString(), _aliceV2);
      expect(bob?.digest.toString(), _bobV2);
    });

    test('produces different digests across versions for the same email', () {
      final candidates = ring.candidateHashes(ContactKind.email, _alice, {
        1,
        2,
      });
      expect(
        {for (final hash in candidates) hash.version: hash.digest.toString()},
        {1: _aliceV1, 2: _aliceV2},
      );
    });

    test('excludes phone contacts from writes and match candidates', () {
      const phone = '+12025550100';
      expect(ring.hashForWrite(ContactKind.phone, phone), isNull);
      expect(ring.candidateHashes(ContactKind.phone, phone, {1, 2}), isEmpty);
    });

    test(
      'produces candidates only for keys still referenced by stored rows',
      () {
        final rotated = ContactMatchKeyRing.parse(
          '1:secretA,2:secretB,3:secretC',
        );
        final candidate = rotated.candidateHashes(ContactKind.email, _alice, {
          1,
        }).single;
        expect(candidate.version, 1);
        expect(candidate.digest.toString(), _aliceV1);
      },
    );
  });
}
