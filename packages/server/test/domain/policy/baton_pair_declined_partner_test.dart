import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/baton_pair_policy.dart';

// A declined invitation keeps the named person on the inviter's row, so the
// inviter can be told who can't join.

final _now = DateTime.utc(2026, 1, 1, 12);

RoomBatonCandidate _asked() => const RoomBatonCandidate(
  batonId: 'L1',
  userId: 'A',
  tier: 1,
  response: BatonResponse.canHelp,
  partnerUserId: 'X',
  partnerResponse: BatonPartnerResponse.pending,
  partnerInvites: 1,
);

BatonPairResult _decline(List<RoomBatonCandidate> rows) =>
    BatonPairPolicy.partnerRespond(
      rows: rows,
      actorId: 'X',
      inviterId: 'A',
      accept: false,
      now: _now,
    );

void main() {
  group('BatonPairPolicy.partnerRespond decline', () {
    test('keeps the declined partner on the inviter row', () {
      final a = _decline([_asked()]).rows.singleWhere((c) => c.userId == 'A');

      expect(a.response, BatonResponse.waiting);
      expect(a.partnerResponse, BatonPartnerResponse.declined);
      expect(a.partnerUserId, 'X');
    });

    test('tells the inviter once that the partner did not accept', () {
      final r = _decline([_asked()]);

      expect(r.receipts, hasLength(1));
      expect(r.receipts.single.recipientId, 'A');
      expect(r.receipts.single.kind, BatonPairReceiptKind.partnerAnswered);
      expect(r.receipts.single.accepted, isFalse);
    });

    test('answering a declined invitation again is rejected', () {
      final rows = _decline([_asked()]).rows;

      for (final accept in [true, false]) {
        expect(
          () => BatonPairPolicy.partnerRespond(
            rows: rows,
            actorId: 'X',
            inviterId: 'A',
            accept: accept,
            now: _now,
          ),
          throwsA(isA<BatonNotPartnerException>()),
        );
      }
    });
  });
}
