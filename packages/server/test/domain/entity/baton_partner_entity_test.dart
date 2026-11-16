import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

void main() {
  group('BatonPartnerResponse', () {
    test('fromSmallint round-trips pending, accepted and declined', () {
      for (final v in [0, 1, 2]) {
        expect(BatonPartnerResponse.fromSmallint(v).smallintValue, v);
      }
      expect(BatonPartnerResponse.fromSmallint(0), BatonPartnerResponse.pending);
      expect(BatonPartnerResponse.fromSmallint(1), BatonPartnerResponse.accepted);
      expect(BatonPartnerResponse.fromSmallint(2), BatonPartnerResponse.declined);
    });

    test('fromSmallint rejects an unknown value with ArgumentError', () {
      expect(
        () => BatonPartnerResponse.fromSmallint(3),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('baton entities carry pair fields', () {
    test('a candidate built without pair fields is solo', () {
      const c = RoomBatonCandidate(
        batonId: 'L1',
        userId: 'A',
        tier: 1,
        response: BatonResponse.canHelp,
      );
      expect(c.partnerUserId, isNull);
      expect(c.partnerResponse, isNull);
      expect(c.partnerRespondedAt, isNull);
      expect(c.partnerInvites, 0);
    });

    test('a candidate keeps its partner marker', () {
      final at = DateTime.utc(2026);
      final c = RoomBatonCandidate(
        batonId: 'L1',
        userId: 'A',
        tier: 1,
        response: BatonResponse.canHelp,
        partnerUserId: 'X',
        partnerResponse: BatonPartnerResponse.accepted,
        partnerRespondedAt: at,
        partnerInvites: 2,
      );
      expect(c.partnerUserId, 'X');
      expect(c.partnerResponse, BatonPartnerResponse.accepted);
      expect(c.partnerRespondedAt, at);
      expect(c.partnerInvites, 2);
    });

    test('a baton has a nullable co-taker', () {
      final b = RoomBaton(
        id: 'L1',
        messageId: 'M1',
        beaconId: 'B1',
        authorId: 'U',
        status: BatonStatus.taken,
        createdAt: DateTime.utc(2026),
        takerId: 'A',
        coTakerId: 'X',
      );
      expect(b.coTakerId, 'X');
      expect(
        RoomBaton(
          id: 'L1',
          messageId: 'M1',
          beaconId: 'B1',
          authorId: 'U',
          status: BatonStatus.collecting,
          createdAt: DateTime.utc(2026),
        ).coTakerId,
        isNull,
      );
    });
  });

  group('pair exception codes', () {
    test('are appended after the last existing code', () {
      expect(const BatonPartnerInvalidException().code.codeNumber, 1355);
      expect(const BatonNotPartnerException().code.codeNumber, 1356);
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.factCopyAttachmentUnavailable,
        ).codeNumber,
        1354,
      );
    });

    test('every beacon exception code number is distinct', () {
      final numbers = BeaconExceptionCode.values
          .map((c) => BeaconExceptionCodes(c).codeNumber)
          .toList();
      expect(numbers.toSet().length, numbers.length);
    });

    test('existing baton code numbers are unchanged', () {
      expect(const BatonNotFoundException().code.codeNumber, 1322);
      expect(const BatonNotAuthorException().code.codeNumber, 1323);
      expect(const BatonNotCollectingException().code.codeNumber, 1325);
      expect(const BatonInvalidCandidatesException().code.codeNumber, 1326);
      expect(const BatonMessageNotEligibleException().code.codeNumber, 1329);
    });
  });
}
